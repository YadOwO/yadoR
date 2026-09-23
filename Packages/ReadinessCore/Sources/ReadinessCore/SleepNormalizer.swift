import Foundation

/// A completed, automatic Watch sample. The HealthKit adapter is responsible for
/// filtering in-bed, manually entered and non-Watch records before conversion.
public struct SleepSegment: Equatable, Sendable {
    public enum Stage: String, Sendable {
        case asleep, core, deep, rem, awake
        var isAsleep: Bool { self != .awake }
        var isDetailed: Bool { self == .core || self == .deep || self == .rem }
    }

    public var id: String
    public var sourceID: String
    public var sourceName: String
    public var start: Date
    public var end: Date
    public var stage: Stage

    public init(id: String, sourceID: String, sourceName: String,
                start: Date, end: Date, stage: Stage) {
        self.id = id; self.sourceID = sourceID; self.sourceName = sourceName
        self.start = start; self.end = end; self.stage = stage
    }
}

public enum SleepNormalizer {
    /// Gaps join a session, but do not become sleep or explicit awake time.
    /// A session crossing midnight stays intact; consumers assign its end day.
    public static func normalize(_ segments: [SleepSegment], through now: Date,
                                 maximumGap: TimeInterval = 90 * 60) -> [NightRecord] {
        var seen = Set<String>()
        let valid = segments.filter {
            $0.start < $0.end && $0.end <= now && !$0.sourceID.isEmpty
        }.sorted(by: segmentOrder).filter { seen.insert($0.id).inserted }
        let grouped = Dictionary(grouping: valid, by: \.sourceID)
        var candidates: [(record: NightRecord, detailed: Double)] = []

        for sourceID in grouped.keys.sorted() {
            let sourceSegments = grouped[sourceID]!.filter { $0.stage.isAsleep }.sorted(by: segmentOrder)
            let sourceAwake = grouped[sourceID]!.filter { $0.stage == .awake }
            var session: [SleepSegment] = []
            var sessionEnd: Date?
            for segment in sourceSegments {
                if let end = sessionEnd, segment.start.timeIntervalSince(end) > max(0, maximumGap) {
                    if let candidate = makeSession(session + sourceAwake) { candidates.append(candidate) }
                    session = []
                    sessionEnd = nil
                }
                session.append(segment)
                sessionEnd = max(sessionEnd ?? segment.end, segment.end)
            }
            if let candidate = makeSession(session + sourceAwake) { candidates.append(candidate) }
        }

        // Alternate apps/devices may describe the same sleep. Keep one complete
        // source instead of joining their stages or creating extra baseline nights.
        candidates.sort {
            if $0.record.asleepSeconds != $1.record.asleepSeconds {
                return $0.record.asleepSeconds > $1.record.asleepSeconds
            }
            if $0.detailed != $1.detailed { return $0.detailed > $1.detailed }
            return $0.record.id < $1.record.id
        }
        var selected: [NightRecord] = []
        for candidate in candidates {
            let record = candidate.record
            if !selected.contains(where: { $0.start < record.end && record.start < $0.end }) {
                selected.append(record)
            }
        }
        return selected.sorted {
            $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start
        }
    }

    private static func segmentOrder(_ lhs: SleepSegment, _ rhs: SleepSegment) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        if lhs.sourceID != rhs.sourceID { return lhs.sourceID < rhs.sourceID }
        if lhs.stage != rhs.stage { return lhs.stage.rawValue < rhs.stage.rawValue }
        return lhs.id < rhs.id
    }

    private static func makeSession(_ segments: [SleepSegment]) -> (record: NightRecord, detailed: Double)? {
        let asleep = union(segments.filter { $0.stage.isAsleep }.map { DateInterval(start: $0.start, end: $0.end) })
        guard let first = asleep.first, let last = asleep.last, let source = segments.first else { return nil }
        let bounds = DateInterval(start: first.start, end: last.end)
        let awake = union(segments.filter { $0.stage == .awake }.compactMap {
            intersect(DateInterval(start: $0.start, end: $0.end), bounds)
        })
        let removed = asleep.reduce(0.0) { total, interval in
            total + awake.compactMap { intersect(interval, $0)?.duration }.reduce(0, +)
        }
        let asleepSeconds = asleep.map(\.duration).reduce(0, +) - removed
        guard asleepSeconds > 0 else { return nil }
        let detailed = union(segments.filter { $0.stage.isDetailed }.map {
            DateInterval(start: $0.start, end: $0.end)
        }).map(\.duration).reduce(0, +)
        // Start time and source identify a session independently of extra stages
        // arriving later. No current-time value enters this identifier.
        let identifier = "\(source.sourceID)|\(first.start.timeIntervalSince1970.bitPattern)"
        let record = NightRecord(id: identifier, sourceID: source.sourceID, sourceName: source.sourceName,
                                 start: bounds.start, end: bounds.end, asleepSeconds: asleepSeconds,
                                 awakeSeconds: awake.map(\.duration).reduce(0, +))
        return (record, detailed)
    }

    private static func union(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }

    private static func intersect(_ lhs: DateInterval, _ rhs: DateInterval) -> DateInterval? {
        let start = max(lhs.start, rhs.start)
        let end = min(lhs.end, rhs.end)
        return start < end ? DateInterval(start: start, end: end) : nil
    }
}
