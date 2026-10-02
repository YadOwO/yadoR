import Foundation
import ReadinessCore
@preconcurrency import WatchConnectivity

@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    var onReceive: ((SnapshotEnvelope) -> Void)?
    var onRefreshRequest: (() async -> Void)?
    var onStatus: ((String?) -> Void)?
    private(set) var pending: SnapshotEnvelope?
    private let enabled: Bool
    private var started = false
    private var requestInFlight = false
    #if os(watchOS)
    private var pendingObservation: NSKeyValueObservation?
    private var backgroundWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    #endif

    init(enabled: Bool = true) { self.enabled = enabled }

    func start() {
        guard enabled, !started, WCSession.isSupported() else { return }
        started = true
        WCSession.default.delegate = self
        #if os(watchOS)
        pendingObservation = WCSession.default.observe(\.hasContentPending, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.completeBackgroundDeliveryIfReady() }
        }
        #endif
        WCSession.default.activate()
    }

    func publish(_ envelope: SnapshotEnvelope) {
        guard envelope.isValid else { return }
        stage(envelope)
        guard enabled else { return }
        sendPending()
    }

    func stage(_ envelope: SnapshotEnvelope) {
        guard envelope.isValid else { return }
        pending = envelope
    }

    func requestLatest() {
        guard enabled, WCSession.isSupported(), !requestInFlight else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            onStatus?("正在连接 iPhone…")
            return
        }
        if !session.receivedApplicationContext.isEmpty {
            receive(session.receivedApplicationContext)
        }
        guard session.isReachable else {
            onStatus?("iPhone 暂不可达；打开手机上的 yadoR 后会继续同步。")
            return
        }
        onStatus?("已请求 iPhone 更新。")
        requestInFlight = true
        session.sendMessage(["request": "refresh"], replyHandler: { [weak self] _ in
            Task { @MainActor in self?.requestInFlight = false }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.requestInFlight = false
                self?.onStatus?("暂时无法连接 iPhone，已保留最近结果。")
            }
        })
    }

    private func sendPending() {
        guard let pending, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else {
            onStatus?("在配对的 Apple Watch 上安装 yadoR 后即可同步。")
            return
        }
        #endif
        do {
            let data = try JSONEncoder().encode(pending)
            try session.updateApplicationContext(["snapshot": data])
            onStatus?(nil)
        } catch {
            onStatus?("结果已保存在本机，稍后重试同步。")
        }
    }

    private func receive(_ context: [String: Any]) {
        #if os(watchOS)
        guard let data = context["snapshot"] as? Data, data.count <= 65_536,
              let envelope = try? JSONDecoder().decode(SnapshotEnvelope.self, from: data),
              envelope.isValid else { return }
        onReceive?(envelope)
        onStatus?(nil)
        #endif
    }

    #if os(watchOS)
    func finishBackgroundDelivery() async {
        guard enabled, WCSession.isSupported(), !Task.isCancelled else { return }
        start()
        let identifier = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                backgroundWaiters[identifier] = continuation
                completeBackgroundDeliveryIfReady()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.backgroundWaiters.removeValue(forKey: identifier)?.resume()
            }
        }
    }

    private func completeBackgroundDeliveryIfReady() {
        let session = WCSession.default
        guard session.activationState == .activated, !session.hasContentPending else { return }
        receive(session.receivedApplicationContext)
        let waiters = Array(backgroundWaiters.values)
        backgroundWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }
    #endif

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: (any Error)?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if error != nil {
                self.onStatus?("设备连接暂不可用，请稍后重试。")
                #if os(watchOS)
                let waiters = Array(self.backgroundWaiters.values)
                self.backgroundWaiters.removeAll()
                for waiter in waiters { waiter.resume() }
                #endif
            }
            guard activationState == .activated else { return }
            self.sendPending()
            #if os(watchOS)
            self.requestLatest()
            self.completeBackgroundDeliveryIfReady()
            #endif
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Extract Sendable bytes before crossing actor boundaries.
        guard let data = applicationContext["snapshot"] as? Data else { return }
        Task { @MainActor [weak self] in self?.receive(["snapshot": data]) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? String == "refresh" else {
            replyHandler(["accepted": false]); return
        }
        replyHandler(["accepted": true])
        Task { @MainActor [weak self] in
            await self?.onRefreshRequest?()
            self?.sendPending()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            #if os(iOS)
            self?.sendPending()
            #else
            if WCSession.default.isReachable { self?.requestLatest() }
            #endif
        }
    }

    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.sendPending() }
    }
    #endif
}
