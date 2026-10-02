import Foundation

public struct SnapshotEnvelope: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var origin: String
    public var revision: Int
    public var fingerprint: String?
    public var snapshot: ReadinessSnapshot
    public var retiredOrigins: Set<String>?

    public init(origin: String, revision: Int, fingerprint: String?, snapshot: ReadinessSnapshot) {
        self.origin = origin; self.revision = revision
        self.fingerprint = fingerprint; self.snapshot = snapshot
    }

    public func supersedes(_ existing: Self?) -> Bool {
        guard let existing else { return true }
        if origin == existing.origin { return revision > existing.revision }
        return existing.retiredOrigins?.contains(origin) != true
    }

    public func accepted(after existing: Self?) -> Self? {
        guard isValid, supersedes(existing) else { return nil }
        var next = self
        var retired = existing?.retiredOrigins ?? []
        if let existing, existing.origin != origin { retired.insert(existing.origin) }
        next.retiredOrigins = retired
        return next
    }

    public var isValid: Bool {
        guard schemaVersion == 1, !origin.isEmpty, revision >= 0, !snapshot.isDemo,
              snapshot.generatedAt.timeIntervalSince1970.isFinite,
              snapshot.day.timeIntervalSince1970.isFinite,
              snapshot.validNights >= 0, snapshot.requiredNights > 0 else { return false }
        if snapshot.status == .ready {
            guard let score = snapshot.score, (0...10).contains(score),
                  snapshot.dataThrough != nil else { return false }
        } else if snapshot.score != nil { return false }
        return true
    }
}
