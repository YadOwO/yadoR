import CryptoKit
import Foundation
import HealthKit
import ReadinessCore

/// iPhone owns the read pipeline. Nothing here writes or persists health samples.
@MainActor
final class HealthKitClient {
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    private var observationGeneration = UUID()
    private var backgroundFailures = Set<String>()
    private var observerFailures = Set<String>()
    /// Background registration is best effort; foreground reads still work.
    var hasBackgroundDeliveryFailure: Bool { !backgroundFailures.isEmpty }

    init() {}

    private var types: [HKSampleType] {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRate),
         HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.respiratoryRate),
         HKQuantityType(.appleSleepingWristTemperature), HKQuantityType(.oxygenSaturation),
         HKQuantityType(.activeEnergyBurned), HKQuantityType(.restingHeartRate),
         HKWorkoutType.workoutType()]
    }

    func authorize() async throws {
        guard Self.isAvailable else { throw HealthDataError.unavailable }
        // Completion confirms that the request was handled, not that reads were granted.
        try await store.requestAuthorization(toShare: [], read: Set(types))
    }

    func readInput(now: Date = .now) async throws -> ReadinessInput {
        guard Self.isAvailable else { throw HealthDataError.unavailable }
        try Task.checkCancellation()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // The extra boundary day captures a main sleep starting before midnight.
        let sleepStart = calendar.date(byAdding: .day, value: -49, to: today)!
        let activityStart = calendar.date(byAdding: .day, value: -28, to: today)!
        let healthStore = store
        let earliest = try await store.earliestAuthorizedSampleDate(for: Set(types.map { $0 as HKObjectType }))
        func descriptor(_ type: HKSampleType, windows: [DateInterval]) -> HKSampleQueryDescriptor<HKSample>? {
            let predicates = windows.compactMap { window -> NSPredicate? in
                let start = max(window.start, earliest[type] ?? window.start)
                let end = min(window.end, now)
                guard start < end else { return nil }
                return HKQuery.predicateForSamples(withStart: start, end: end,
                                                   options: [.strictStartDate, .strictEndDate])
            }
            guard !predicates.isEmpty else { return nil }
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
            return HKSampleQueryDescriptor(predicates: [.sample(type: type, predicate: predicate)],
                                           sortDescriptors: [SortDescriptor(\HKSample.startDate)])
        }
        // Read sleep first: daytime HR is not used by this algorithm and does not
        // need a 49-day all-day query or an update fingerprint entry.
        let sleepType = HKCategoryType(.sleepAnalysis)
        let sleepSamples: [HKSample]
        if let query = descriptor(sleepType, windows: [DateInterval(start: sleepStart, end: now)]) {
            sleepSamples = try await query.result(for: healthStore)
        } else {
            sleepSamples = []
        }
        let sleepWindows = HealthSampleProcessor.sleepWindows(samples: sleepSamples, now: now)
        let descriptors = types.filter { $0 != sleepType }.compactMap { type in
            let isActivity = type == HKQuantityType(.activeEnergyBurned)
                || type == HKQuantityType(.restingHeartRate) || type is HKWorkoutType
            return descriptor(type, windows: isActivity
                              ? [DateInterval(start: activityStart, end: now)] : sleepWindows)
        }
        // One failure aborts this refresh. A failed query must not erase data by
        // pretending that the user has an empty Health database.
        let samples = try await withThrowingTaskGroup(of: [HKSample].self) { group in
            for descriptor in descriptors {
                group.addTask { try await descriptor.result(for: healthStore) }
            }
            var result = sleepSamples
            for try await batch in group { result.append(contentsOf: batch) }
            return result
        }
        try Task.checkCancellation()
        let processing = Task.detached(priority: .utility) {
            try HealthSampleProcessor.input(samples: samples, now: now, calendar: calendar)
        }
        return try await withTaskCancellationHandler {
            try await processing.value
        } onCancel: {
            processing.cancel()
        }
    }

    /// Call only after the user has previously completed the authorization flow.
    func startObserving(onChange: @escaping @MainActor () async -> Void,
                        onStatus: @escaping @MainActor (String?) -> Void) {
        guard Self.isAvailable, observers.isEmpty else { return }
        let generation = UUID()
        observationGeneration = generation
        backgroundFailures.removeAll()
        observerFailures.removeAll()
        onStatus(nil)
        for type in types {
            let typeID = type.identifier
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                let finish = HealthObserverCompletion(completion)
                Task { @MainActor [weak self] in
                    guard let self, self.observationGeneration == generation else {
                        finish.call(); return
                    }
                    if error == nil { self.observerFailures.remove(typeID) }
                    else { self.observerFailures.insert(typeID) }
                    onStatus(self.observationStatus)
                    // Refresh also on observer errors; registration and observer
                    // failures remain visible even if the foreground query works.
                    await onChange()
                    finish.call()
                }
            }
            observers.append(query)
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { [weak self] success, error in
                Task { @MainActor [weak self] in
                    guard let self, self.observationGeneration == generation else { return }
                    if success && error == nil { self.backgroundFailures.remove(typeID) }
                    else { self.backgroundFailures.insert(typeID) }
                    onStatus(self.observationStatus)
                }
            }
        }
    }

    private var observationStatus: String? {
        guard !backgroundFailures.isEmpty || !observerFailures.isEmpty else { return nil }
        if !backgroundFailures.isEmpty && !observerFailures.isEmpty {
            return "部分健康数据的后台更新和变更观察暂不可用，请打开 App 刷新。"
        }
        return backgroundFailures.isEmpty
            ? "部分健康数据的变更观察暂不可用，请打开 App 刷新。"
            : "部分健康数据的后台更新暂不可用，请打开 App 刷新。"
    }

    func stopObserving() {
        observationGeneration = UUID()
        for query in observers { store.stop(query) }
        observers.removeAll()
        for type in types {
            store.disableBackgroundDelivery(for: type) { _, _ in }
        }
    }
}

private enum HealthDataError: LocalizedError {
    case unavailable
    var errorDescription: String? { "这台设备无法读取健康数据。" }
}

/// HealthKit owns a callback without a Sendable annotation. A lock provides its
/// one-shot lifetime while processing moves to the main actor.
private nonisolated final class HealthObserverCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (() -> Void)?
    nonisolated init(_ completion: @escaping () -> Void) { self.completion = completion }
    nonisolated func call() {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?()
    }
}

nonisolated enum HealthSampleProcessor {
    struct Source: Sendable {
        var id: String
        var name: String
        var bundle: String
        var product: String
        var deviceID: String?

        init(name: String, bundle: String, product: String, deviceID: String?) {
            self.bundle = bundle; self.product = product; self.deviceID = deviceID; self.name = name
            self.id = [bundle, product, deviceID ?? "unspecified-device"].joined(separator: "|")
        }

        init?(_ sample: HKSample) {
            let revision = sample.sourceRevision
            let product = revision.productType ?? sample.device?.model ?? ""
            guard product.lowercased().contains("watch") else { return nil }
            self.init(name: revision.source.name, bundle: revision.source.bundleIdentifier,
                      product: product, deviceID: sample.device?.localIdentifier)
        }

        func matches(_ other: Source) -> Bool {
            guard bundle == other.bundle, product == other.product else { return false }
            if let deviceID, let otherDeviceID = other.deviceID { return deviceID == otherDeviceID }
            // Some Watch sample types omit HKDevice. Never cross a known device
            // mismatch, and prefer exact identity before this documented fallback.
            return true
        }
    }

    struct Quantity: Sendable {
        var id: String
        var type: String
        var start: Date
        var end: Date
        var value: Double
        var source: Source
    }

    struct Work: Sendable {
        var id: String
        var start: Date
        var end: Date
        var duration: Double
        var source: Source
    }

    static func sleepWindows(samples: [HKSample], now: Date) -> [DateInterval] {
        let segments = samples.compactMap { sample -> SleepSegment? in
            guard let sleep = sample as? HKCategorySample,
                  sleep.categoryType == HKCategoryType(.sleepAnalysis),
                  sleep.startDate < sleep.endDate, sleep.endDate <= now,
                  (sleep.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue != true,
                  let source = Source(sleep), let stage = sleepStage(sleep.value) else { return nil }
            return SleepSegment(id: sleep.uuid.uuidString, sourceID: source.id, sourceName: source.name,
                                start: sleep.startDate, end: sleep.endDate, stage: stage)
        }
        return SleepNormalizer.normalize(segments, through: now).map { DateInterval(start: $0.start, end: $0.end) }
    }

    static func input(samples: [HKSample], now: Date, calendar: Calendar) throws -> ReadinessInput {
        var seen = Set<UUID>()
        var segments: [SleepSegment] = []
        var quantities: [Quantity] = []
        var workouts: [Work] = []
        var sources: [String: Source] = [:]
        for sample in samples.sorted(by: { $0.uuid.uuidString < $1.uuid.uuidString }) {
            try Task.checkCancellation()
            guard sample.startDate <= sample.endDate, sample.endDate <= now,
                  seen.insert(sample.uuid).inserted,
                  (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue != true,
                  let source = Source(sample) else { continue }
            let id = sample.uuid.uuidString
            sources[source.id] = source
            if let sleep = sample as? HKCategorySample, sleep.categoryType == HKCategoryType(.sleepAnalysis),
               sleep.startDate < sleep.endDate, let stage = sleepStage(sleep.value) {
                segments.append(SleepSegment(id: id, sourceID: source.id, sourceName: source.name,
                                             start: sleep.startDate, end: sleep.endDate, stage: stage))
            } else if let quantity = sample as? HKQuantitySample,
                      let value = quantityValue(quantity) {
                quantities.append(Quantity(id: id, type: quantity.quantityType.identifier,
                                           start: quantity.startDate, end: quantity.endDate,
                                           value: value, source: source))
            } else if let workout = sample as? HKWorkout, workout.duration.isFinite,
                      workout.duration > 0, workout.startDate < workout.endDate {
                workouts.append(Work(id: id, start: workout.startDate, end: workout.endDate,
                                     duration: min(workout.duration, workout.endDate.timeIntervalSince(workout.startDate)),
                                     source: source))
            }
        }

        return try normalize(segments: segments, quantities: quantities, workouts: workouts,
                             sources: sources, now: now, calendar: calendar)
    }

    /// Plain-value boundary allows the actual reduction rules to be verified
    /// without granting health access or synthesizing private HKSource objects.
    static func normalize(segments: [SleepSegment], quantities: [Quantity], workouts: [Work],
                          sources: [String: Source], now: Date, calendar: Calendar) throws -> ReadinessInput {
        var nights = SleepNormalizer.normalize(segments, through: now)
        var dataThrough = nights.map(\.end).max()
        let byType = Dictionary(grouping: quantities, by: \.type).mapValues { values in
            values.sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        }
        for index in nights.indices {
            try Task.checkCancellation()
            let night = nights[index]
            guard let source = sources[night.sourceID] else { continue }
            func values(_ identifier: HKQuantityTypeIdentifier) -> [Quantity] {
                let inSession = contained(byType[identifier.rawValue] ?? [], start: night.start, end: night.end).filter {
                    source.matches($0.source)
                }
                let exact = inSession.filter { $0.source.id == source.id }
                if !exact.isEmpty { return uniqueQuantities(exact) }
                // An identity-free night must not merge measurements from two
                // distinguishable Watches, even if both have the same model.
                guard Set(inSession.map { $0.source.id }).count <= 1 else { return [] }
                return uniqueQuantities(inSession)
            }
            let heart = values(.heartRate)
            let hrv = values(.heartRateVariabilitySDNN)
            nights[index].heartRate = median(heart.map(\.value))
            nights[index].heartRateSampleCount = heart.count
            // Temporal span is a quality gate, not a claim of continuous coverage.
            nights[index].heartRateCoverageSeconds = max(0, (heart.map(\.end).max() ?? night.start)
                .timeIntervalSince(heart.map(\.start).min() ?? night.start))
            nights[index].hrvSDNN = median(hrv.map(\.value))
            nights[index].hrvSampleCount = hrv.count
            nights[index].respiratoryRate = median(values(.respiratoryRate).map(\.value))
            nights[index].wristTemperature = median(values(.appleSleepingWristTemperature).map(\.value))
            nights[index].oxygenSaturation = median(values(.oxygenSaturation).map(\.value))
        }

        let preferred = nights.filter { calendar.isDate($0.end, inSameDayAs: now) }
            .sorted { $0.asleepSeconds == $1.asleepSeconds ? $0.id < $1.id : $0.asleepSeconds > $1.asleepSeconds }
            .first.flatMap { sources[$0.sourceID] }
        let energy = byType[HKQuantityTypeIdentifier.activeEnergyBurned.rawValue] ?? []
        let resting = byType[HKQuantityTypeIdentifier.restingHeartRate.rawValue] ?? []
        let today = calendar.startOfDay(for: now)
        var activity: [ActivityDay] = []
        for offset in -28...0 {
            try Task.checkCancellation()
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let end = min(calendar.date(byAdding: .day, value: 1, to: day)!, now)
            let dailyEnergy = energy.filter { $0.start < end && $0.end > day && $0.start < $0.end }
            let selectedEnergy = selectSource(dailyEnergy, preferred: preferred)
            let energyResult = integrate(selectedEnergy.map {
                WeightedInterval(id: $0.id, start: $0.start, end: $0.end, total: $0.value)
            }, start: day, end: end)
            let dailyResting = resting.filter { $0.end >= day && $0.end < end }
            let selectedResting = selectSource(dailyResting, preferred: preferred)
            let dailyWork = workouts.filter { $0.start < end && $0.end > day }
            let matchedWork = preferred.map { preferred in dailyWork.filter { preferred.matches($0.source) } } ?? dailyWork
            // A workout's own duration already excludes pauses. Integrate its
            // duration density; overlapping imports never add a second workout.
            let workoutResult = integrate(matchedWork.map {
                WeightedInterval(id: $0.id, start: $0.start, end: $0.end, total: $0.duration)
            }, start: day, end: end)
            for usedEnd in [energyResult.dataThrough, workoutResult.dataThrough, selectedResting.map(\.end).max()].compactMap({ $0 }) {
                dataThrough = max(dataThrough ?? usedEnd, usedEnd)
            }
            activity.append(ActivityDay(day: day, activeEnergy: selectedEnergy.isEmpty ? nil : energyResult.total,
                                        workoutMinutes: workoutResult.total / 60,
                                        effortLoad: nil, restingHeartRate: median(selectedResting.map(\.value))))
        }
        // Fingerprint the effective normalized input, not unused raw records or
        // import UUIDs. Empty calendar scaffolding must not manufacture new data.
        struct EffectiveInput: Encodable {
            var nights: [NightRecord]
            var activity: [ActivityDay]
            var dataThrough: Date?
        }
        let effective = EffectiveInput(nights: nights, activity: activity.filter {
            $0.activeEnergy != nil || $0.restingHeartRate != nil || $0.workoutMinutes > 0 || $0.effortLoad != nil
        }, dataThrough: dataThrough)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(effective)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return ReadinessInput(nights: nights, activity: activity, dataThrough: dataThrough, fingerprint: digest)
    }

    /// Each type is sorted by start time once. Binary search avoids rescanning
    /// every historical HR sample for each night's window.
    private static func contained(_ sorted: [Quantity], start: Date, end: Date) -> [Quantity] {
        var low = 0, high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle].start < start { low = middle + 1 } else { high = middle }
        }
        var result: [Quantity] = []
        while low < sorted.count, sorted[low].start <= end {
            if sorted[low].end <= end { result.append(sorted[low]) }
            low += 1
        }
        return result
    }

    private static func sleepStage(_ value: Int) -> SleepSegment.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepUnspecified: .asleep
        case .asleepCore: .core
        case .asleepDeep: .deep
        case .asleepREM: .rem
        case .awake: .awake
        default: nil
        }
    }

    private static func quantityValue(_ sample: HKQuantitySample) -> Double? {
        let unit: HKUnit
        let range: ClosedRange<Double>
        switch sample.quantityType.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue, HKQuantityTypeIdentifier.restingHeartRate.rawValue:
            unit = .count().unitDivided(by: .minute()); range = 20...250
        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            unit = .secondUnit(with: .milli); range = 0.001...500
        case HKQuantityTypeIdentifier.respiratoryRate.rawValue:
            unit = .count().unitDivided(by: .minute()); range = 4...60
        case HKQuantityTypeIdentifier.appleSleepingWristTemperature.rawValue:
            unit = .degreeCelsius(); range = 20...45
        case HKQuantityTypeIdentifier.oxygenSaturation.rawValue:
            unit = .percent(); range = 0.5...1
        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
            unit = .kilocalorie(); range = 0...100_000
        default: return nil
        }
        let value = sample.quantity.doubleValue(for: unit)
        return value.isFinite && range.contains(value) ? value : nil
    }

    private static func uniqueQuantities(_ values: [Quantity]) -> [Quantity] {
        var seen = Set<String>()
        return values.sorted { $0.id < $1.id }.filter {
            seen.insert("\($0.start.timeIntervalSince1970.bitPattern)|\($0.end.timeIntervalSince1970.bitPattern)|\($0.value.bitPattern)").inserted
        }
    }

    private static func selectSource(_ values: [Quantity], preferred: Source?) -> [Quantity] {
        let grouped = Dictionary(grouping: values, by: { $0.source.id })
        if let preferred {
            if let exact = grouped[preferred.id] { return uniqueQuantities(exact) }
            let matching = grouped.filter { $0.value.first.map { preferred.matches($0.source) } ?? false }
            if let key = rankedSource(matching) { return uniqueQuantities(matching[key]!) }
        }
        guard let key = rankedSource(grouped) else { return [] }
        return uniqueQuantities(grouped[key]!)
    }

    private static func rankedSource(_ groups: [String: [Quantity]]) -> String? {
        groups.keys.sorted {
            let lhs = groups[$0]!, rhs = groups[$1]!
            let leftSpan = (lhs.map(\.end).max() ?? .distantPast).timeIntervalSince(lhs.map(\.start).min() ?? .distantPast)
            let rightSpan = (rhs.map(\.end).max() ?? .distantPast).timeIntervalSince(rhs.map(\.start).min() ?? .distantPast)
            return leftSpan == rightSpan ? $0 < $1 : leftSpan > rightSpan
        }.first
    }

    private struct WeightedInterval {
        var id: String
        var start: Date
        var end: Date
        var total: Double
    }

    /// Sweep interval boundaries and use one observation at each instant. More
    /// granular records win over overlapping summaries; never sum both sources.
    private static func integrate(_ intervals: [WeightedInterval], start: Date, end: Date)
        -> (total: Double, dataThrough: Date?) {
        struct Event { var time: Date; var index: Int; var begins: Bool }
        let valid = intervals.filter { $0.start < $0.end && $0.start < end && $0.end > start }
        var events: [Event] = []
        for (index, interval) in valid.enumerated() {
            events.append(Event(time: max(interval.start, start), index: index, begins: true))
            events.append(Event(time: min(interval.end, end), index: index, begins: false))
        }
        events.sort { $0.time == $1.time ? (!$0.begins && $1.begins) : $0.time < $1.time }
        var active = Set<Int>()
        var previous = start
        var total = 0.0
        var dataThrough: Date?
        for event in events {
            if event.time > previous, let selected = active.min(by: {
                let lhs = valid[$0], rhs = valid[$1]
                let ld = lhs.end.timeIntervalSince(lhs.start), rd = rhs.end.timeIntervalSince(rhs.start)
                return ld == rd ? lhs.id < rhs.id : ld < rd
            }) {
                let interval = valid[selected]
                total += interval.total * event.time.timeIntervalSince(previous) / interval.end.timeIntervalSince(interval.start)
                dataThrough = event.time
            }
            if event.begins { active.insert(event.index) } else { active.remove(event.index) }
            previous = event.time
        }
        return (total, dataThrough)
    }

    private static func median(_ values: [Double]) -> Double? {
        let values = values.sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
    }
}
