import Foundation
import Testing
@testable import ReadinessCore

struct SleepNormalizerTests {
    private let origin = Date(timeIntervalSince1970: 1_784_156_400)

    private func segment(_ id: String, _ start: Double, _ end: Double,
                         stage: SleepSegment.Stage = .core, source: String = "watch-a") -> SleepSegment {
        SleepSegment(id: id, sourceID: source, sourceName: source,
                     start: origin.addingTimeInterval(start * 3_600),
                     end: origin.addingTimeInterval(end * 3_600), stage: stage)
    }

    private func normalize(_ segments: [SleepSegment]) -> [NightRecord] {
        SleepNormalizer.normalize(segments, through: origin.addingTimeInterval(30 * 3_600))
    }

    @Test func overlappingStagesAndUnspecifiedSleepCountOnce() throws {
        let records = normalize([
            segment("summary", 0, 8, stage: .asleep), segment("core", 0, 4),
            segment("rem", 3, 6, stage: .rem), segment("deep", 6, 8, stage: .deep),
            segment("awake", 2, 3, stage: .awake), segment("awake-copy", 2.5, 3, stage: .awake)
        ])
        let night = try #require(records.first)
        #expect(records.count == 1)
        #expect(night.asleepSeconds == 7 * 3_600)
        #expect(night.awakeSeconds == 3_600)
    }

    @Test func smallUnobservedGapIsNotInventedAsSleepOrAwake() throws {
        let night = try #require(normalize([
            segment("first", 0, 3), segment("second", 3.5, 7.5)
        ]).first)
        #expect(night.asleepSeconds == 7 * 3_600)
        #expect(night.awakeSeconds == 0)
        #expect(night.end.timeIntervalSince(night.start) == 7.5 * 3_600)
    }

    @Test func explicitAwakeInGapIsIncludedButExteriorAwakeIsClipped() throws {
        let night = try #require(normalize([
            segment("first", 0, 3), segment("second", 4, 8), segment("awake", 3, 4, stage: .awake),
            segment("before", -2, 0, stage: .awake), segment("after", 8, 10, stage: .awake)
        ]).first)
        #expect(night.asleepSeconds == 7 * 3_600)
        #expect(night.awakeSeconds == 3_600)
        #expect(night.start == origin)
        #expect(night.end == origin.addingTimeInterval(8 * 3_600))
    }

    @Test func crossMidnightSessionIsNotSplit() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let midnight = calendar.startOfDay(for: origin)
        let values = [
            SleepSegment(id: "before", sourceID: "watch", sourceName: "Watch",
                         start: midnight.addingTimeInterval(-2 * 3_600), end: midnight, stage: .core),
            SleepSegment(id: "after", sourceID: "watch", sourceName: "Watch",
                         start: midnight, end: midnight.addingTimeInterval(6 * 3_600), stage: .rem)
        ]
        let nights = SleepNormalizer.normalize(values, through: midnight.addingTimeInterval(8 * 3_600))
        #expect(nights.count == 1)
        let night = try #require(nights.first)
        #expect(night.asleepSeconds == 8 * 3_600)
        #expect(calendar.isDate(night.end, inSameDayAs: midnight))
    }

    @Test func alternateSourcesDoNotCreateExtraBaselineNights() throws {
        let records = normalize([segment("short", 0, 6, source: "watch-a"),
                                 segment("complete", 0, 8, source: "watch-b")])
        let night = try #require(records.first)
        #expect(records.count == 1)
        #expect(night.sourceID == "watch-b")
        #expect(night.asleepSeconds == 8 * 3_600)
    }

    @Test func equallyLongSourcesPreferDetailedStagesDeterministically() {
        let values = [segment("a", 0, 8, stage: .asleep, source: "watch-a"),
                      segment("b", 0, 8, stage: .core, source: "watch-b")]
        #expect(normalize(values).first?.sourceID == "watch-b")
        #expect(normalize(values) == normalize(Array(values.reversed())))
    }

    @Test func napAndItsDuplicateRemainOneSeparateSession() {
        let records = normalize([segment("night", 0, 8), segment("nap", 13, 14),
                                 segment("nap-copy", 13, 14, source: "watch-b")])
        #expect(records.count == 2)
        #expect(records.map(\.asleepSeconds) == [8 * 3_600, 3_600])
    }

    @Test func allDayAwakeRecordCannotJoinANightToANap() {
        let records = normalize([segment("night", 0, 8), segment("nap", 13, 14),
                                 segment("awake", 8, 13, stage: .awake)])
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.awakeSeconds == 0 })
    }

    @Test func incompleteAndInvalidSamplesDoNotCreateSleep() {
        let values = [segment("future", 0, 32), segment("empty", 2, 2),
                      segment("reversed", 4, 3), segment("awake", 0, 8, stage: .awake)]
        #expect(normalize(values).isEmpty)
    }

    @Test func repeatedSampleAndNewStageDoNotChangeSessionIdentity() throws {
        let first = segment("first", 0, 4)
        let initial = try #require(normalize([first]).first)
        let expanded = try #require(normalize([first, first, segment("later", 4, 8)]).first)
        #expect(initial.id == expanded.id)
        #expect(expanded.asleepSeconds == 8 * 3_600)
    }
}
