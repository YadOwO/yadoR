import Foundation
import HealthKit
import ReadinessCore
import Testing
@testable import yadoR

struct HealthSampleProcessorTests {
    private typealias Processor = HealthSampleProcessor
    private let primary = Processor.Source(name: "Watch A", bundle: "test.watch", product: "Watch7,5", deviceID: "A")
    private let other = Processor.Source(name: "Watch B", bundle: "test.watch", product: "Watch7,5", deviceID: "B")

    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private var day: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_784_160_000)) }
    private func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3_600) }

    private func sleep(_ id: String = "sleep", source: Processor.Source? = nil,
                       start: Double = 0, end: Double = 8) -> SleepSegment {
        let source = source ?? primary
        return SleepSegment(id: id, sourceID: source.id, sourceName: source.name,
                            start: at(start), end: at(end), stage: .core)
    }

    private func quantity(_ id: String, _ type: HKQuantityTypeIdentifier, _ value: Double,
                          start: Double, end: Double? = nil, source: Processor.Source? = nil) -> Processor.Quantity {
        Processor.Quantity(id: id, type: type.rawValue, start: at(start), end: at(end ?? start),
                           value: value, source: source ?? primary)
    }

    private var baseQuantities: [Processor.Quantity] {
        [quantity("hr-1", .heartRate, 60, start: 1), quantity("hr-2", .heartRate, 61, start: 2),
         quantity("hr-3", .heartRate, 59, start: 3), quantity("hrv", .heartRateVariabilitySDNN, 45, start: 3),
         quantity("energy", .activeEnergyBurned, 100, start: 10, end: 11),
         quantity("resting", .restingHeartRate, 58, start: 12)]
    }

    private func input(segments: [SleepSegment]? = nil, quantities: [Processor.Quantity]? = nil,
                       now: Date? = nil) throws -> ReadinessInput {
        try Processor.normalize(segments: segments ?? [sleep()], quantities: quantities ?? baseQuantities,
                                workouts: [], sources: [primary.id: primary, other.id: other],
                                now: now ?? at(18), calendar: calendar)
    }

    @Test func unusedDaytimeHeartRateDoesNotAdvanceResult() throws {
        let first = try input()
        let second = try input(quantities: baseQuantities + [quantity("day-hr", .heartRate, 110, start: 17)])
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.dataThrough == at(12))
        #expect(second.dataThrough == first.dataThrough)
    }

    @Test func unselectedWatchDoesNotAdvanceCutoffOrFingerprint() throws {
        let first = try input()
        let second = try input(segments: [sleep(), sleep("other-sleep", source: other, start: 1, end: 7)],
                               quantities: baseQuantities + [quantity("other-energy", .activeEnergyBurned, 900,
                                                                      start: 10, end: 17, source: other)])
        #expect(first.nights == second.nights)
        #expect(first.activity == second.activity)
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.dataThrough == second.dataThrough)
    }

    @Test func duplicateImportUUIDsDoNotChangeEffectiveInput() throws {
        let first = try input()
        let second = try input(segments: [sleep(), sleep("different-sleep-uuid")],
                               quantities: baseQuantities + [quantity("different-hr-uuid", .heartRate, 60, start: 1),
                                                             quantity("different-energy-uuid", .activeEnergyBurned, 100,
                                                                      start: 10, end: 11)])
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.nights.first?.heartRateSampleCount == second.nights.first?.heartRateSampleCount)
        #expect(first.activity == second.activity)
    }

    @Test func finerEnergyIntervalsReplaceOverlappingSummary() throws {
        let result = try input(quantities: [quantity("summary", .activeEnergyBurned, 200, start: 10, end: 12),
                                            quantity("first", .activeEnergyBurned, 80, start: 10, end: 11),
                                            quantity("second", .activeEnergyBurned, 120, start: 11, end: 12)])
        let today = try #require(result.activity.last)
        let energy = try #require(today.activeEnergy)
        #expect(energy == 200)
        #expect(result.dataThrough == at(12))
    }

    @Test func meaningfulQuantityChangeChangesFingerprint() throws {
        let first = try input()
        var changed = baseQuantities
        changed[4].value = 120
        let second = try input(quantities: changed)
        #expect(first.fingerprint != second.fingerprint)
        #expect(first.dataThrough == second.dataThrough)
    }

    @Test func unchangedSamplesAndEmptyDayScaffoldingDoNotInventAnUpdate() throws {
        let first = try input(segments: [], quantities: [], now: at(18))
        let second = try input(segments: [], quantities: [], now: at(42))
        #expect(first.dataThrough == nil)
        #expect(second.dataThrough == nil)
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.activity.allSatisfy { $0.activeEnergy == nil })
    }

    @Test func orderOfSamplesDoesNotChangeFingerprint() throws {
        let first = try input()
        let second = try input(quantities: Array(baseQuantities.reversed()))
        #expect(first.fingerprint == second.fingerprint)
        #expect(first.dataThrough == second.dataThrough)
    }
}
