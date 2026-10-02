import Foundation
import Testing
@testable import ReadinessCore

struct ReadinessEngineTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 22, hour: 16))!
    }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
    }
    private func night(_ offset: Int, asleep: Double = 8) -> NightRecord {
        let end = day(offset).addingTimeInterval(7 * 3_600)
        return NightRecord(id: "night-\(offset)", sourceID: "watch-a", sourceName: "我的 Apple Watch",
                           start: end.addingTimeInterval(-(asleep * 3_600 + 1_200)), end: end,
                           asleepSeconds: asleep * 3_600, awakeSeconds: 1_200,
                           heartRate: 55, heartRateSampleCount: 30,
                           heartRateCoverageSeconds: max(3_600, asleep * 3_600 - 600),
                           hrvSDNN: 45, hrvSampleCount: 2)
    }
    private func input(nights: Int = 7, activityDays: Int = 28) -> ReadinessInput {
        ReadinessInput(nights: (0..<nights).map { night(-$0) },
                       activity: (0...activityDays).map {
                           ActivityDay(day: day(-$0), activeEnergy: $0 == 0 ? 100 : 500)
                       }, dataThrough: now.addingTimeInterval(-60), fingerprint: "fixture")
    }
    private func evaluate(_ input: ReadinessInput, at date: Date? = nil) -> ReadinessSnapshot {
        ReadinessEngine().evaluate(input, at: date ?? now, calendar: calendar)
    }
    private func nap(id: String = "nap", startHour: Double = 12) -> NightRecord {
        let start = day(0).addingTimeInterval(startHour * 3_600)
        return NightRecord(id: id, sourceID: "watch-a", sourceName: "我的 Apple Watch",
                           start: start, end: start.addingTimeInterval(3_600), asleepSeconds: 3_600)
    }

    @Test func sevenNightsProduceOneExplainedVersionedResult() {
        let result = evaluate(input())
        #expect(result.status == .ready)
        #expect(result.validNights == 7)
        #expect(result.score == 8)
        #expect(result.day == day(0))
        #expect(result.timeZoneIdentifier == calendar.timeZone.identifier)
        #expect(result.dataThrough == now.addingTimeInterval(-60))
        #expect(result.generatedAt == now)
        #expect(result.factors.map(\.kind) == [.sleep, .vitals, .activity])
        #expect(result.algorithmVersion == "0.1-experimental")
        #expect(!result.isDemo)
    }

    @Test func insufficientHistoryDoesNotCreateADefaultScore() {
        let result = evaluate(input(nights: 1))
        #expect(result.status == .buildingBaseline)
        #expect(result.validNights == 1)
        #expect(result.score == nil)
        #expect(evaluate(ReadinessInput(nights: [], activity: [], dataThrough: nil, fingerprint: "empty")).score == nil)
    }

    @Test func yesterdayCannotReplaceCurrentSleepOrHRV() {
        var value = input(nights: 8)
        value.nights.removeFirst()
        #expect(evaluate(value).status == .missingData)
        #expect(evaluate(value).score == nil)
        value = input(nights: 12)
        value.nights[0].hrvSDNN = nil
        #expect(evaluate(value).status == .missingData)
        #expect(evaluate(value).score == nil)
        value.nights[0].hrvSDNN = 45
        value.nights[0].hrvSampleCount = 0
        #expect(evaluate(value).score == nil)
    }

    @Test(arguments: [0.0, -1.0, Double.nan, Double.infinity, 501.0])
    func invalidCurrentHRVPreventsScoring(_ hrv: Double) {
        var value = input(); value.nights[0].hrvSDNN = hrv
        #expect(evaluate(value).score == nil)
    }

    @Test func HRVCoverageRequiresSevenDistinctNights() {
        var value = input(); value.nights[1].hrvSDNN = nil
        #expect(evaluate(value).status == .buildingBaseline)
        #expect(evaluate(value).validNights == 6)
    }

    @Test func sparseHeartRateCannotBeReplacedByANap() {
        var value = input(); value.nights[0].heartRateSampleCount = 2
        value.nights.append(nap())
        #expect(evaluate(value).score == nil)
        value.nights[0].heartRateSampleCount = 3
        value.nights[0].heartRateCoverageSeconds = 3_599
        #expect(evaluate(value).score == nil)
        value.nights[0].heartRateCoverageSeconds = 3_600
        #expect(evaluate(value).status == .ready)
    }

    @Test func exactDuplicatesAndOrderDoNotChangeResults() {
        let value = input()
        var duplicated = value
        duplicated.nights += value.nights; duplicated.activity += value.activity
        duplicated.nights.reverse(); duplicated.activity.reverse()
        #expect(evaluate(duplicated) == evaluate(value))
    }

    @Test func conflictingRecordsAreExcluded() {
        var value = input(); var conflict = value.nights[0]
        conflict.hrvSDNN = 80; value.nights.append(conflict)
        #expect(evaluate(value).score == nil)
        value = input(); value.activity.append(ActivityDay(day: day(0), activeEnergy: 200))
        #expect(evaluate(value).score == nil)
    }

    @Test func severalSessionsOnOneDayOnlyCountOnce() {
        var value = input(nights: 1)
        for index in 0..<6 {
            var repeated = value.nights[0]; repeated.id = "different-\(index)"
            value.nights.append(repeated)
        }
        #expect(evaluate(value).validNights == 1)
        #expect(evaluate(value).score == nil)
    }

    @Test func windowIncludesTodayAnd48PriorDays() {
        var value = input(nights: 6); value.nights.append(night(-48))
        #expect(evaluate(value).status == .ready)
        value.nights.removeLast(); value.nights.append(night(-49))
        #expect(evaluate(value).status == .buildingBaseline)
        #expect(evaluate(value).validNights == 6)
    }

    @Test func changingWatchSourceRebuildsBaseline() {
        var value = input(); value.nights[0].sourceID = "watch-b"
        #expect(evaluate(value).status == .buildingBaseline)
        #expect(evaluate(value).validNights == 1)
        for index in value.nights.indices { value.nights[index].sourceID = "watch-b" }
        #expect(evaluate(value).status == .ready)
    }

    @Test func midnightSleepBelongsToEndDay() {
        let value = input()
        #expect(calendar.startOfDay(for: value.nights[0].start) == day(-1))
        #expect(evaluate(value).day == day(0))
        #expect(evaluate(value).validNights == 7)
    }

    @Test func napsOnlyOffsetDeficitAndOverlapsDoNotAccumulate() {
        var value = input(); value.nights[0] = night(0, asleep: 5)
        let before = evaluate(value)
        value.nights.append(nap()); let after = evaluate(value)
        #expect((after.score ?? -1) >= (before.score ?? -1))
        value.nights.append(nap())
        #expect(evaluate(value) == after)
        value.nights.append(nap(id: "overlap"))
        #expect(evaluate(value) == after)
        var rested = input(); let score = evaluate(rested).score
        rested.nights.append(nap())
        #expect(evaluate(rested).score == score)
    }

    @Test func futureAndDifferentSourceNapsAreIgnored() {
        let value = input(); var changed = value
        changed.nights.append(nap(startHour: 20))
        var other = nap(id: "other"); other.sourceID = "watch-b"
        changed.nights.append(other)
        #expect(evaluate(changed) == evaluate(value))
    }

    @Test func timePassingDoesNotRecoverScore() {
        var value = input(); value.activity[0].activeEnergy = 2_000
        let early = evaluate(value)
        let later = evaluate(value, at: now.addingTimeInterval(3 * 3_600))
        #expect(early.score == later.score)
        #expect(early.factors == later.factors)
        #expect(early.dataThrough == later.dataThrough)
    }

    @Test func currentLoadIsMonotonicAndWorkoutEnergyIsNotCountedTwice() throws {
        var value = input(); var last = 10
        for energy in [0.0, 100, 300, 500, 1_000, 2_000, 5_000, 30_000] {
            value.activity[0].activeEnergy = energy
            let score = try #require(evaluate(value).score)
            #expect(score <= last); last = score
        }
        let score = evaluate(value).score
        value.activity[0].workoutMinutes = 90; value.activity[0].effortLoad = 720
        #expect(evaluate(value).score == score)
    }

    @Test func missingActivityDiffersFromMeasuredZero() {
        var value = input(); value.activity[0].activeEnergy = nil
        #expect(evaluate(value).status == .missingData)
        value.activity[0].activeEnergy = 0
        #expect(evaluate(value).status == .ready)
    }

    @Test(arguments: [Double.nan, Double.infinity, -1.0, 30_001.0])
    func corruptCurrentEnergyDoesNotScore(_ energy: Double) {
        var value = input(); value.activity[0].activeEnergy = energy
        #expect(evaluate(value).score == nil)
    }

    @Test func provisionalAndLongActivityReferencesAreExplicit() throws {
        let provisional = evaluate(input(activityDays: 6))
        #expect(provisional.status == .ready)
        let factor = try #require(provisional.factors.first { $0.kind == .activity })
        #expect(factor.omitted.contains { $0.contains("临时日参考") })
        #expect(!factor.metrics.contains { $0.title == "近期活动参考" })
        #expect(evaluate(input(activityDays: 5)).status == .buildingBaseline)
        let complete = try #require(evaluate(input()).factors.first { $0.kind == .activity })
        #expect(complete.metrics.contains { $0.title == "近期活动参考" })
    }

    @Test func optionalMeasuresAreDescriptiveAndDoNotChangeScore() throws {
        var value = input(); let baseline = evaluate(value)
        for index in value.nights.indices {
            value.nights[index].respiratoryRate = 14; value.nights[index].wristTemperature = 36
            value.nights[index].oxygenSaturation = 0.97
        }
        for index in value.activity.indices { value.activity[index].restingHeartRate = 58 }
        value.activity[0].restingHeartRate = 90
        #expect(evaluate(value).score == baseline.score)
        let factor = try #require(evaluate(value).factors.first { $0.kind == .vitals })
        #expect(factor.metrics.contains { $0.title == "全天静息心率" && $0.reference?.contains("58") == true })
        value.nights[0].wristTemperature = .nan; value.nights[0].oxygenSaturation = .infinity
        value.activity[0].restingHeartRate = .nan
        #expect(evaluate(value).score == baseline.score)
        value.activity[0].workoutMinutes = Double.greatestFiniteMagnitude
        #expect(evaluate(value).status == .ready)
    }

    @Test func zeroMADAndHistoricalOutliersRemainBounded() throws {
        var value = input(nights: 14)
        value.nights[13].hrvSDNN = 450; value.nights[13].heartRate = 200
        #expect(evaluate(value).score == evaluate(input(nights: 14)).score)
        for hrv in [1.0, 5, 45, 150, 500] {
            value.nights[0].hrvSDNN = hrv
            #expect((0...10).contains(try #require(evaluate(value).score)))
        }
    }

    @Test func worseCoreVitalsDoNotImproveScore() throws {
        var value = input(); let baseline = try #require(evaluate(value).score)
        value.nights[0].hrvSDNN = 15; value.nights[0].heartRate = 80
        #expect(try #require(evaluate(value).score) < baseline)
    }

    @Test func longerSleepWithFixedBedtimeDoesNotReduceScore() throws {
        var value = input(); var previous = -1
        for hours in [3.0, 4, 5, 6, 7, 8] {
            let start = day(-1).addingTimeInterval(22 * 3_600)
            value.nights[0].start = start
            value.nights[0].end = start.addingTimeInterval(hours * 3_600 + 1_200)
            value.nights[0].asleepSeconds = hours * 3_600
            value.nights[0].heartRateCoverageSeconds = 3_600
            let score = try #require(evaluate(value).score)
            #expect(score >= previous); previous = score
        }
    }

    @Test(arguments: [0, 1, 2, 4, 5, 7, 8, 10])
    func bandsUseTheSpecifiedEdges(_ score: Int) {
        let expected: ReadinessBand = score <= 1 ? .recover : score <= 4 ? .gentle : score <= 7 ? .ready : .strong
        #expect(ReadinessBand(score: score) == expected)
    }

    @Test func staleSnapshotCannotExposeYesterdayAsToday() {
        let snapshot = evaluate(input())
        let next = snapshot.visible(at: day(1).addingTimeInterval(9 * 3_600), calendar: calendar)
        #expect(next.score == nil); #expect(next.status == .missingData); #expect(next.factors.isEmpty)
    }
}
