import Foundation
import Observation
import ReadinessCore
import WidgetKit

#if os(iOS)
@MainActor
protocol HealthReading: AnyObject {
    func authorize() async throws
    func readInput(now: Date) async throws -> ReadinessInput
    func startObserving(onChange: @escaping @MainActor () async -> Void,
                        onStatus: @escaping @MainActor (String?) -> Void)
    func stopObserving()
}
extension HealthKitClient: HealthReading {}
#endif

@MainActor
@Observable
final class ReadinessStore {
    private(set) var snapshot: ReadinessSnapshot
    private(set) var isRefreshing = false
    private(set) var hasConnectedHealth: Bool
    private(set) var errorMessage: String?
    private var connectionMessage: String?
    private var healthMessage: String?
    var syncMessage: String? {
        let messages = [healthMessage, connectionMessage].compactMap { $0 }
        return messages.isEmpty ? nil : messages.joined(separator: "\n")
    }
    var isDemo: Bool { snapshot.isDemo }

    @ObservationIgnored private let cache: SnapshotCache
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let bridge: WatchBridge
    @ObservationIgnored private var envelope: SnapshotEnvelope?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshRequested = false
    #if os(iOS)
    @ObservationIgnored private var health: any HealthReading
    #endif

    init(preview: Bool = false, cache: SnapshotCache = SnapshotCache(),
         defaults: UserDefaults = .standard, bridge: WatchBridge? = nil) {
        self.cache = cache
        self.defaults = defaults
        self.bridge = bridge ?? WatchBridge(enabled: !preview)
        #if os(iOS)
        self.health = HealthKitClient()
        #endif
        hasConnectedHealth = defaults.bool(forKey: "healthConnectionStarted")
        #if os(watchOS)
        snapshot = .empty(watch: true)
        #else
        snapshot = .empty()
        #endif
        if !preview {
            do {
                envelope = try cache.load()
                if let envelope { snapshot = envelope.snapshot }
                #if os(iOS)
                if !hasConnectedHealth, snapshot.status != .notSetUp {
                    snapshot = .empty()
                    envelope = nil
                }
                #endif
            } catch { errorMessage = error.localizedDescription }
        }
        #if DEBUG
        if preview || ProcessInfo.processInfo.arguments.contains("--uitesting-ready") {
            showDemo()
        } else if ProcessInfo.processInfo.arguments.contains("--uitesting-baseline") {
            showDemo(.buildingBaseline)
        } else if ProcessInfo.processInfo.arguments.contains("--uitesting-missing") {
            showDemo(.missingData)
        } else if ProcessInfo.processInfo.arguments.contains("--uitesting-onboarding") {
            showDemo(.notSetUp)
        }
        #endif
    }

    /// Register delegates and observers during application launch, including a background launch.
    func activateServices() {
        guard !isDemo else { return }
        if !started {
            started = true
            bridge.onReceive = { [weak self] in self?.accept($0) }
            bridge.onRefreshRequest = { [weak self] in await self?.refresh() }
            bridge.onStatus = { [weak self] in self?.connectionMessage = $0 }
            #if os(iOS)
            if let envelope { bridge.stage(envelope) }
            else if !hasConnectedHealth {
                let cleared = makeEnvelope(.empty(), fingerprint: nil)
                envelope = cleared
                bridge.stage(cleared)
            }
            #endif
            bridge.start()
        }
        #if os(iOS)
        if hasConnectedHealth {
            health.startObserving(onChange: { [weak self] in await self?.refresh() },
                                  onStatus: { [weak self] in self?.healthMessage = $0 })
        }
        #endif
    }

    func start() async {
        guard !isDemo else { return }
        activateServices()
        #if os(iOS)
        if let envelope { bridge.publish(envelope) }
        else if !hasConnectedHealth {
            // Reassert a previously requested clear even if its cache could not be written.
            let cleared = makeEnvelope(.empty(), fingerprint: nil)
            envelope = cleared
            bridge.publish(cleared)
        }
        if hasConnectedHealth { await refresh() }
        #else
        bridge.requestLatest()
        #endif
    }

    #if os(watchOS)
    func receiveBackgroundUpdate() async {
        guard !isDemo else { return }
        activateServices()
        await bridge.finishBackgroundDelivery()
    }
    #endif

    func connectHealth() async {
        guard !isRefreshing, !isDemo else { return }
        #if os(iOS)
        guard HealthKitClient.isAvailable else {
            errorMessage = "此设备无法使用健康数据。"
            return
        }
        errorMessage = nil
        isRefreshing = true
        let token = generation
        do {
            try await health.authorize()
            guard token == generation else { return }
            // Completion means the request finished, not that every read type was granted.
            hasConnectedHealth = true
            defaults.set(true, forKey: "healthConnectionStarted")
            isRefreshing = false
            await start()
        } catch {
            guard token == generation else { return }
            isRefreshing = false
            errorMessage = "健康数据连接未完成，请重试。"
        }
        #else
        bridge.requestLatest()
        #endif
    }

    func refresh() async {
        guard !isDemo else { return }
        #if os(iOS)
        guard hasConnectedHealth else { return }
        refreshRequested = true
        if let refreshTask {
            await refreshTask.value
            return
        }
        let token = generation
        isRefreshing = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            while self.refreshRequested, token == self.generation, !Task.isCancelled {
                self.refreshRequested = false
                do {
                    let now = Date.now
                    let input = try await self.health.readInput(now: now)
                    guard token == self.generation, !Task.isCancelled, !self.isDemo else { break }
                    self.errorMessage = nil
                    if let old = self.envelope,
                       old.fingerprint == input.fingerprint,
                       old.snapshot.algorithmVersion == ReadinessSnapshot.algorithmVersion,
                       old.snapshot.timeZoneIdentifier == TimeZone.current.identifier,
                       Calendar.current.isDate(old.snapshot.day, inSameDayAs: now) {
                        continue
                    }
                    let snapshot = ReadinessEngine().evaluate(input, at: now)
                    try self.publish(snapshot, fingerprint: input.fingerprint)
                } catch {
                    guard token == self.generation, !Task.isCancelled else { break }
                    self.errorMessage = "暂时无法读取或保存结果。请解锁 iPhone 后重试；已有结果保留原更新时间。"
                }
            }
            if token == self.generation {
                self.isRefreshing = false
                self.refreshTask = nil
            }
        }
        refreshTask = task
        await task.value
        #else
        bridge.requestLatest()
        #endif
    }

    func clearLocalData() async {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshRequested = false
        isRefreshing = false
        errorMessage = nil
        healthMessage = nil
        #if os(iOS)
        health.stopObserving()
        hasConnectedHealth = false
        defaults.set(false, forKey: "healthConnectionStarted")
        // Revoke the in-memory and queued result even if the disk is full or locked.
        let cleared = makeEnvelope(.empty(), fingerprint: nil)
        envelope = cleared
        snapshot = cleared.snapshot
        bridge.publish(cleared)
        do { try cache.save(cleared) }
        catch {
            try? cache.clear()
            errorMessage = "已停止读取健康数据，共享缓存清除失败，请重试。"
        }
        WidgetCenter.shared.reloadTimelines(ofKind: SnapshotCache.widgetKind)
        #else
        snapshot = .empty(watch: true)
        envelope = nil
        do { try cache.clear() }
        catch { errorMessage = "本机缓存未能清除，请重试。" }
        connectionMessage = "本机记录已清除；重新更新可从 iPhone 获取结果。"
        WidgetCenter.shared.reloadTimelines(ofKind: SnapshotCache.widgetKind)
        #endif
    }

    func showDemo(_ status: AssessmentStatus = .ready) {
        #if DEBUG
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshRequested = false
        isRefreshing = false
        errorMessage = nil
        connectionMessage = nil
        healthMessage = nil
        snapshot = ReadinessFixtures.snapshot(status: status)
        #endif
    }

    func exitDemo() async {
        #if DEBUG
        // An unreadable cache must never leave a fixture visible without its demo marker.
        #if os(watchOS)
        snapshot = .empty(watch: true)
        #else
        snapshot = .empty()
        #endif
        do {
            envelope = try cache.load()
            #if os(watchOS)
            snapshot = envelope?.snapshot ?? .empty(watch: true)
            #else
            snapshot = envelope?.snapshot ?? .empty()
            #endif
        } catch { errorMessage = error.localizedDescription }
        await start()
        #endif
    }

    private func makeEnvelope(_ snapshot: ReadinessSnapshot, fingerprint: String?) -> SnapshotEnvelope {
        let origin = defaults.string(forKey: "readinessOrigin") ?? UUID().uuidString
        defaults.set(origin, forKey: "readinessOrigin")
        let revision = max(defaults.integer(forKey: "readinessRevision"), envelope?.revision ?? 0) + 1
        defaults.set(revision, forKey: "readinessRevision")
        return SnapshotEnvelope(origin: origin, revision: revision, fingerprint: fingerprint, snapshot: snapshot)
    }

    private func publish(_ snapshot: ReadinessSnapshot, fingerprint: String?) throws {
        let next = makeEnvelope(snapshot, fingerprint: fingerprint)
        try cache.save(next)
        self.envelope = next
        self.snapshot = snapshot
        bridge.publish(next)
        WidgetCenter.shared.reloadTimelines(ofKind: SnapshotCache.widgetKind)
    }

    private func accept(_ incoming: SnapshotEnvelope) {
        guard !isDemo, let accepted = incoming.accepted(after: envelope) else { return }
        do {
            try cache.save(accepted)
            envelope = accepted
            snapshot = accepted.snapshot
            errorMessage = nil
            WidgetCenter.shared.reloadTimelines(ofKind: SnapshotCache.widgetKind)
        } catch {
            errorMessage = "结果已收到，但无法保存。请检查共享缓存配置后重试。"
        }
    }

    #if DEBUG && os(iOS)
    func useHealthReaderForTesting(_ reader: any HealthReading) { health = reader }
    #endif
}
