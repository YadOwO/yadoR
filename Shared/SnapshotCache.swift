import Foundation
import ReadinessCore

/// App Group is shared on a single device; WatchConnectivity handles cross-device transport.
struct SnapshotCache: Sendable {
    static let groupID = "group.com.yado.yadoR"
    static let widgetKind = "ReadinessWidget"
    private let directory: URL?

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID
        )?.appendingPathComponent("Readiness", isDirectory: true)
    }

    func load() throws -> SnapshotEnvelope? {
        guard let directory else { throw CacheError.appGroupUnavailable }
        let file = directory.appendingPathComponent("current.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        guard data.count <= 65_536 else { throw CacheError.invalidSnapshot }
        let envelope = try JSONDecoder().decode(SnapshotEnvelope.self, from: data)
        guard envelope.isValid else { throw CacheError.invalidSnapshot }
        return envelope
    }

    func save(_ envelope: SnapshotEnvelope) throws {
        guard envelope.isValid else { throw CacheError.invalidSnapshot }
        guard var directory else { throw CacheError.appGroupUnavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let data = try JSONEncoder().encode(envelope)
        guard data.count <= 65_536 else { throw CacheError.invalidSnapshot }
        try data.write(to: directory.appendingPathComponent("current.json"),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() throws {
        guard let directory else { throw CacheError.appGroupUnavailable }
        let file = directory.appendingPathComponent("current.json")
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    enum CacheError: LocalizedError {
        case appGroupUnavailable, invalidSnapshot
        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable: "无法访问共享缓存，请检查 App Groups 签名配置。"
            case .invalidSnapshot: "本地结果无法读取，请重新更新。"
            }
        }
    }
}
