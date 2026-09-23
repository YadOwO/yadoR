import Foundation
import Testing
import ReadinessCore
@testable import yadoR

@MainActor
struct ReadinessStoreTests {
    private func environment() throws -> (SnapshotCache, UserDefaults, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        defaults.set(true, forKey: "healthConnectionStarted")
        return (SnapshotCache(directory: directory), defaults, directory)
    }

    @Test func sameInputDoesNotAdvanceDisplayedUpdateTime() async throws {
        let (cache, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadinessStore(cache: cache, defaults: defaults, bridge: WatchBridge(enabled: false))
        let reader = FakeHealthReader()
        store.useHealthReaderForTesting(reader)
        await store.refresh()
        let first = try #require(try cache.load())
        await store.refresh()
        let second = try #require(try cache.load())
        #expect(reader.reads == 2)
        #expect(first == second)
        #expect(store.snapshot.score == nil)
    }

    @Test func deletedInputsReplacePreviouslyValidScore() async throws {
        let (cache, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        var old = ReadinessFixtures.snapshot()
        old.isDemo = false
        try cache.save(SnapshotEnvelope(origin: "old", revision: 1, fingerprint: "old-input", snapshot: old))
        let store = ReadinessStore(cache: cache, defaults: defaults, bridge: WatchBridge(enabled: false))
        store.useHealthReaderForTesting(FakeHealthReader())
        await store.refresh()
        #expect(store.snapshot.score == nil)
        #expect(try cache.load()?.snapshot.score == nil)
        #expect(store.snapshot.status != .ready)
    }

    @Test func readErrorPreservesOriginalTimestampAndReportsFailure() async throws {
        let (cache, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        var old = ReadinessFixtures.snapshot()
        old.isDemo = false
        try cache.save(SnapshotEnvelope(origin: "phone", revision: 1, fingerprint: "old", snapshot: old))
        let store = ReadinessStore(cache: cache, defaults: defaults, bridge: WatchBridge(enabled: false))
        let reader = FakeHealthReader()
        reader.shouldFail = true
        store.useHealthReaderForTesting(reader)
        await store.refresh()
        #expect(store.snapshot == old)
        #expect(store.errorMessage != nil)
    }

    @Test func clearingDuringReadCannotRestoreScore() async throws {
        let (cache, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadinessStore(cache: cache, defaults: defaults, bridge: WatchBridge(enabled: false))
        let reader = FakeHealthReader()
        reader.suspend = true
        store.useHealthReaderForTesting(reader)
        let reading = Task { await store.refresh() }
        for _ in 0..<100 where reader.pending == nil { await Task.yield() }
        let pending = try #require(reader.pending)
        await store.clearLocalData()
        pending.resume(returning: reader.input)
        await reading.value
        #expect(!store.hasConnectedHealth)
        #expect(store.snapshot.status == .notSetUp)
        #expect(try cache.load()?.snapshot.status == .notSetUp)
        #expect(reader.stopped)
    }

    @Test func demoNeverEntersPersistentCache() async throws {
        let (cache, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ReadinessStore(cache: cache, defaults: defaults, bridge: WatchBridge(enabled: false))
        store.showDemo()
        await store.refresh()
        #expect(store.snapshot.isDemo)
        #expect(try cache.load() == nil)
    }

    @Test func failedDemoExitCannotExposeExampleAsRealScore() async throws {
        let (cache, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        defaults.set(false, forKey: "healthConnectionStarted")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid json".utf8).write(to: directory.appendingPathComponent("current.json"))
        let store = ReadinessStore(preview: true, cache: cache, defaults: defaults, bridge: WatchBridge(enabled: false))
        await store.exitDemo()
        #expect(!store.isDemo)
        #expect(store.snapshot.score == nil)
        #expect(store.snapshot.status == .notSetUp)
    }

    @Test func failedCacheWriteStillReplacesQueuedWatchResultWithClear() async throws {
        let (_, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let cache = SnapshotCache(directory: directory)
        let bridge = WatchBridge(enabled: false)
        var old = ReadinessFixtures.snapshot()
        old.isDemo = false
        bridge.publish(SnapshotEnvelope(origin: "old", revision: 1, fingerprint: "old", snapshot: old))
        let store = ReadinessStore(cache: cache, defaults: defaults, bridge: bridge)
        store.useHealthReaderForTesting(FakeHealthReader())
        await store.clearLocalData()
        #expect(bridge.pending?.snapshot.status == .notSetUp)
        #expect(bridge.pending?.snapshot.score == nil)
        #expect(store.snapshot.score == nil)
        #expect(store.errorMessage != nil)
    }

    @Test func backgroundLaunchStagesCacheBeforeAnUnchangedRefresh() async throws {
        let (cache, defaults, directory) = try environment()
        defer { try? FileManager.default.removeItem(at: directory) }
        var saved = ReadinessFixtures.snapshot()
        saved.isDemo = false
        let previous = SnapshotEnvelope(origin: "phone", revision: 3, fingerprint: "empty", snapshot: saved)
        try cache.save(previous)
        let bridge = WatchBridge(enabled: false)
        let store = ReadinessStore(cache: cache, defaults: defaults, bridge: bridge)
        store.useHealthReaderForTesting(FakeHealthReader())
        store.activateServices()
        #expect(bridge.pending == previous)
        await store.refresh()
        #expect(bridge.pending == previous)
        #expect(store.snapshot.generatedAt == saved.generatedAt)
    }
}

@MainActor
private final class FakeHealthReader: HealthReading {
    var reads = 0
    var shouldFail = false
    var suspend = false
    var stopped = false
    var pending: CheckedContinuation<ReadinessInput, any Error>?
    let input = ReadinessInput(nights: [], activity: [], dataThrough: nil, fingerprint: "empty")
    func authorize() async throws {}
    func readInput(now: Date) async throws -> ReadinessInput {
        reads += 1
        if shouldFail { throw CocoaError(.fileReadNoPermission) }
        if suspend { return try await withCheckedThrowingContinuation { pending = $0 } }
        return input
    }
    func startObserving(onChange: @escaping @MainActor () async -> Void,
                        onStatus: @escaping @MainActor (String?) -> Void) {}
    func stopObserving() { stopped = true }
}
