import Foundation

/// An independent, experimental rule model. Its parameters are not clinically validated.
public struct ReadinessEngine: Sendable {
    public init() {}

    public func evaluate(_ input: ReadinessInput, at now: Date = .now,
                         calendar: Calendar = .current) -> ReadinessSnapshot {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -48, to: today) ?? today
        let sessions = uniqueSessions(input.nights).filter {
            isUsableSession($0) && $0.end <= now && $0.end >= windowStart
        }
        let current = mainSession(sessions.filter { calendar.isDate($0.end, inSameDayAs: today) })
        let cutoff = input.dataThrough.flatMap { isFinite($0) && $0 <= now ? $0 : nil }

        func unavailable(_ status: AssessmentStatus, _ message: String, nights: Int = 0) -> ReadinessSnapshot {
            ReadinessSnapshot(status: status, day: today, generatedAt: now,
                              timeZoneIdentifier: calendar.timeZone.identifier, dataThrough: cutoff,
                              validNights: nights, message: message, sourceName: current?.sourceName)
        }

        guard let current else {
            return unavailable(input.nights.isEmpty ? .buildingBaseline : .missingData,
                               "未读到今天结束的主要睡眠。请佩戴手表睡眠，并在数据同步后刷新。")
        }
        let sameSource = sessions.filter { $0.sourceID == current.sourceID }
        let mains = Dictionary(grouping: sameSource, by: { calendar.startOfDay(for: $0.end) })
            .values.compactMap { mainSession($0) }.sorted { $0.end < $1.end }
        let completeNights = mains.filter { isValidNight($0) && isValidHRV($0) }
        guard isValidNight(current) else {
            return unavailable(.missingData,
                               "最近主要睡眠需要至少 3 小时，并有至少 3 次、覆盖 1 小时的有效夜间心率。",
                               nights: completeNights.count)
        }
        guard isValidHRV(current) else {
            return unavailable(.missingData,
                               "未读到本次主要睡眠中的有效 SDNN。不会用之前的 HRV 代替今天的记录。",
                               nights: completeNights.count)
        }
        guard completeNights.count >= Parameters.requiredNights else {
            return unavailable(.buildingBaseline,
                               "过去 49 天已获得同一来源的 \(completeNights.count) 个有效夜晚，需要至少 7 晚。更换手表来源后会重新检查基线。",
                               nights: completeNights.count)
        }
        let previous = completeNights.filter { !calendar.isDate($0.end, inSameDayAs: today) }
        guard previous.count >= Parameters.requiredNights - 1 else {
            return unavailable(.buildingBaseline, "还需要更多不同日期的有效历史睡眠记录。",
                               nights: completeNights.count)
        }

        let activityStart = calendar.date(byAdding: .day, value: -28, to: today) ?? today
        let activity = uniqueActivity(input.activity, calendar: calendar).filter {
            $0.day >= activityStart && $0.day <= today
        }
        let currentActivity = activity.first { calendar.isDate($0.day, inSameDayAs: today) }
        let priorActivity = activity.filter { $0.day < today && validEnergy($0.activeEnergy) != nil }
        guard let currentActivity, let todayEnergy = validEnergy(currentActivity.activeEnergy) else {
            return unavailable(.missingData, "未读到今天的活动能量，暂时无法评估。没有记录与实际活动量为零不同。",
                               nights: completeNights.count)
        }
        guard priorActivity.count >= 6 else {
            return unavailable(.buildingBaseline,
                               "睡眠基线已具备；过去 28 天还需要至少 6 天有记录的活动能量，目前有 \(priorActivity.count) 天。",
                               nights: completeNights.count)
        }

        let sleep = sleepAssessment(current: current, previous: previous, sessions: sameSource,
                                    today: today, calendar: calendar)
        let vitals = vitalsAssessment(current: current, previous: previous,
                                      currentActivity: currentActivity, activity: activity)
        let load = activityAssessment(todayEnergy: todayEnergy, current: currentActivity,
                                      previous: priorActivity, today: today, calendar: calendar)
        let rawScore = Parameters.startingScore - sleep.penalty + vitals.adjustment - load.penalty
        let score = Int(clamp(rawScore, 0, 10).rounded())
        return ReadinessSnapshot(status: .ready, day: today, generatedAt: now,
                                 timeZoneIdentifier: calendar.timeZone.identifier,
                                 dataThrough: cutoff ?? sameSource.map(\.end).max(), score: score,
                                 validNights: completeNights.count,
                                 message: ReadinessBand(score: score).explanation,
                                 factors: [sleep.factor, vitals.factor, load.factor],
                                 sourceName: current.sourceName)
    }
}

private enum Parameters {
    static let requiredNights = 7
    static let startingScore = 8.0
    static let minimumSleep = 3.0 * 3_600
    static let hrvLogScaleFloor = 0.15
    static let heartRateScaleFloor = 3.0
    static let energyReferenceFloor = 100.0
}

private struct PenaltyAssessment {
    var penalty: Double
    var factor: ReadinessFactor
}

private struct VitalsAssessment {
    var adjustment: Double
    var factor: ReadinessFactor
}

private extension ReadinessEngine {
    func sleepAssessment(current: NightRecord, previous: [NightRecord], sessions: [NightRecord],
                         today: Date, calendar: Calendar) -> PenaltyAssessment {
        let hours = current.asleepSeconds / 3_600
        let reference = clamp(median(previous.map { $0.asleepSeconds / 3_600 }), 7, 9)
        let deficit = max(0, reference - hours)
        let naps = sessions.filter {
            $0.id != current.id && $0.start >= current.end && calendar.isDate($0.end, inSameDayAs: today)
                && $0.asleepSeconds >= 600 && $0.asleepSeconds < Parameters.minimumSleep
        }
        let napHours = combinedAsleepSeconds(naps) / 3_600
        // A nap offsets only an existing duration deficit; no fixed reward or time-based recovery.
        let napOffset = min(deficit, min(napHours * 0.5, 1))
        let durationPenalty = min((deficit - napOffset) * 1.25, 4)
        let bedtime = clockMinutes(current.start, calendar: calendar)
        let usualBedtime = circularMedian(previous.map { clockMinutes($0.start, calendar: calendar) })
        let shift = abs(clockDifference(bedtime, usualBedtime))
        let regularityPenalty = min(max(0, shift - 30) / 60 * 0.5, 1.2)
        let awakeFraction = current.awakeSeconds / (current.asleepSeconds + current.awakeSeconds)
        let awakePenalty = min(max(0, awakeFraction - 0.1) * 5, 1.2)
        let penalty = durationPenalty + regularityPenalty + awakePenalty
        var metrics = [
            FactorMetric(title: "主要睡眠", value: duration(current.asleepSeconds),
                         reference: "时长比较参考 \(duration(reference * 3_600))"),
            FactorMetric(title: "入睡时间偏移", value: "\(integer(shift)) 分钟",
                         reference: "与个人历史入睡时刻比较"),
            FactorMetric(title: "记录到的清醒", value: duration(current.awakeSeconds),
                         reference: "占已记录睡眠及清醒的 \(integer(awakeFraction * 100))%")
        ]
        if napHours > 0 {
            metrics.append(FactorMetric(title: "主要睡眠后的补觉", value: duration(napHours * 3_600),
                                        reference: deficit > 0 ? "仅有限补偿主要睡眠的时长不足" : "主要睡眠时长充足，不额外加分"))
        }
        let explanation = "主要睡眠 \(duration(current.asleepSeconds))，相对时长参考\(deficit > 0 ? "不足 \(duration(deficit * 3_600))" : "已达到参考")。入睡时刻偏移 \(integer(shift)) 分钟；记录到 \(duration(current.awakeSeconds)) 清醒。"
        return PenaltyAssessment(penalty: penalty,
                                 factor: ReadinessFactor(kind: .sleep,
                                                         summary: penalty >= 1.5 ? "睡眠恢复有所不足" : "睡眠接近个人参考",
                                                         explanation: explanation, metrics: metrics))
    }

    func vitalsAssessment(current: NightRecord, previous: [NightRecord],
                          currentActivity: ActivityDay, activity: [ActivityDay]) -> VitalsAssessment {
        // Eligibility above establishes both current values and at least six comparable prior nights.
        let hrv = current.hrvSDNN!
        let heartRate = current.heartRate!
        let hrvValues = previous.compactMap(\.hrvSDNN)
        let heartRates = previous.compactMap(\.heartRate)
        let hrvLogValues = hrvValues.map { log($0) }
        let hrvZ = robustDeviation(log(hrv), values: hrvLogValues, floor: Parameters.hrvLogScaleFloor)
        let heartZ = robustDeviation(heartRate, values: heartRates, floor: Parameters.heartRateScaleFloor)
        let hrvPenalty = min(max(0, -hrvZ - 0.5) * 0.9, 2)
        let heartPenalty = min(max(0, heartZ - 0.5) * 0.8, 2)
        let benefit = min(max(0, hrvZ - 0.5) * 0.6, 1.5)
            + min(max(0, -heartZ - 0.5) * 0.2, 0.5)
        let adjustment = benefit - hrvPenalty - heartPenalty
        var metrics = [
            FactorMetric(title: "夜间 HRV · SDNN", value: "\(integer(hrv)) 毫秒",
                         reference: "同来源历史中位数 \(integer(median(hrvValues))) 毫秒"),
            FactorMetric(title: "夜间心率", value: "\(integer(heartRate)) 次/分",
                         reference: "同来源历史中位数 \(integer(median(heartRates))) 次/分")
        ]
        var omitted: [String] = []
        appendOptionalMetric(title: "呼吸频率", current: bounded(current.respiratoryRate, 5, 60),
                             previous: previous.compactMap { bounded($0.respiratoryRate, 5, 60) },
                             unit: "次/分", decimals: 1, metrics: &metrics, omitted: &omitted)
        appendOptionalMetric(title: "腕温", current: bounded(current.wristTemperature, 25, 45),
                             previous: previous.compactMap { bounded($0.wristTemperature, 25, 45) },
                             unit: "°C", decimals: 1, metrics: &metrics, omitted: &omitted)
        appendOptionalMetric(title: "血氧", current: bounded(current.oxygenSaturation, 0.5, 1).map { $0 * 100 },
                             previous: previous.compactMap { bounded($0.oxygenSaturation, 0.5, 1).map { $0 * 100 } },
                             unit: "%", decimals: 0, metrics: &metrics, omitted: &omitted)
        let priorResting = activity.filter { $0.day < currentActivity.day }
            .compactMap { bounded($0.restingHeartRate, 20, 250) }
        appendOptionalMetric(title: "全天静息心率", current: bounded(currentActivity.restingHeartRate, 20, 250),
                             previous: priorResting, unit: "次/分", decimals: 0,
                             metrics: &metrics, omitted: &omitted)
        let summary = adjustment <= -0.75 ? "夜间体征偏离个人参考" : "夜间体征接近个人参考"
        return VitalsAssessment(adjustment: adjustment,
                                factor: ReadinessFactor(kind: .vitals, summary: summary,
                                                        explanation: "评分比较本次主要睡眠的 SDNN 和夜间心率与同一来源历史。其余指标仅展示；全天静息心率使用自己的每日历史，不与夜间心率混用。",
                                                        metrics: metrics, omitted: omitted))
    }

    func activityAssessment(todayEnergy: Double, current: ActivityDay, previous: [ActivityDay],
                            today: Date, calendar: Calendar) -> PenaltyAssessment {
        let energies = previous.compactMap { validEnergy($0.activeEnergy) }
        let reference = median(energies)
        let recentStart = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let recent = previous.filter { $0.day >= recentStart }.compactMap { validEnergy($0.activeEnergy) }
        let hasLongReference = energies.count >= 21 && recent.count >= 5
        let todayRatio = todayEnergy / max(reference, Parameters.energyReferenceFloor)
        let todayPenalty = min(max(0, todayRatio - 0.5) * 0.75, 2)
        var historyPenalty = 0.0
        var metrics = [
            FactorMetric(title: "今日活动能量", value: "\(integer(todayEnergy)) 千卡",
                         reference: "历史日中位数 \(integer(reference)) 千卡 · \(energies.count) 天有记录")
        ]
        var omitted: [String] = []
        if let minutes = bounded(current.workoutMinutes, 0, 1_440) {
            metrics.append(FactorMetric(title: "体能训练时长", value: duration(minutes * 60),
                                        reference: "用于说明；不把训练能量再次叠加到活动能量"))
        } else {
            omitted.append("体能训练时长：记录无效，未展示或计入评分。")
        }
        if hasLongReference {
            let recentMean = mean(recent)
            let longMean = mean(energies)
            let ratio = recentMean / max(longMean, Parameters.energyReferenceFloor)
            historyPenalty = min(max(0, ratio - 1.2) * 1.5, 1.5)
            metrics.append(FactorMetric(title: "近期活动参考", value: "近 7 天日均 \(integer(recentMean)) 千卡",
                                        reference: "近 28 天日均 \(integer(longMean)) 千卡；分别有 \(recent.count) / \(energies.count) 天记录"))
        } else {
            omitted.append("7 / 28 天负荷比较：历史覆盖不足，暂用现有 \(energies.count) 天的活动能量中位数作为临时日参考。")
        }
        if let effort = validEnergy(current.effortLoad) {
            metrics.append(FactorMetric(title: "已记录运动耗能负荷", value: decimal(effort, places: 0),
                                        reference: "评级 × 分钟，仅展示，首版不参与评分"))
        } else {
            omitted.append("运动耗能评级：未读到有效数据；未推算评级，评分使用活动能量。")
        }
        let penalty = todayPenalty + historyPenalty
        return PenaltyAssessment(penalty: penalty,
                                 factor: ReadinessFactor(kind: .activity,
                                                         summary: penalty >= 1 ? "活动消耗较多" : "活动消耗较平缓",
                                                         explanation: "今天已记录 \(integer(todayEnergy)) 千卡活动能量。消耗增加只会维持或降低本次参考分数；没有新数据时，不因时间经过自动恢复。活动能量是负荷的粗略替代，并非苹果训练负荷。",
                                                         metrics: metrics, omitted: omitted))
    }
}

private func appendOptionalMetric(title: String, current: Double?, previous: [Double], unit: String,
                                  decimals: Int, metrics: inout [FactorMetric], omitted: inout [String]) {
    guard let current else {
        omitted.append("\(title)：未读到有效记录，未参与评分。")
        return
    }
    let reference = previous.count >= 6
        ? "历史中位数 \(decimal(median(previous), places: decimals)) \(unit)；仅展示，不参与评分"
        : "可用历史不足 6 天；仅展示，不参与评分"
    metrics.append(FactorMetric(title: title, value: "\(decimal(current, places: decimals)) \(unit)", reference: reference))
}

/// Conflicting copies of an identifier are excluded instead of selecting an arbitrary version.
private func uniqueSessions(_ records: [NightRecord]) -> [NightRecord] {
    Dictionary(grouping: records.filter { !$0.id.isEmpty }, by: \.id).values.compactMap { group in
        guard let first = group.first, group.dropFirst().allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

private func uniqueActivity(_ records: [ActivityDay], calendar: Calendar) -> [ActivityDay] {
    Dictionary(grouping: records.filter { isFinite($0.day) }, by: { calendar.startOfDay(for: $0.day) })
        .compactMap { day, group in
            let normalized = group.map { record in
                var value = record; value.day = day; return value
            }
            guard let first = normalized.first, normalized.dropFirst().allSatisfy({ $0 == first }) else { return nil }
            return first
        }.sorted { $0.day < $1.day }
}

private func mainSession(_ sessions: [NightRecord]) -> NightRecord? {
    sessions.sorted {
        if $0.asleepSeconds != $1.asleepSeconds { return $0.asleepSeconds > $1.asleepSeconds }
        if $0.end != $1.end { return $0.end < $1.end }
        if $0.sourceID != $1.sourceID { return $0.sourceID < $1.sourceID }
        return $0.id < $1.id
    }.first
}

private func isUsableSession(_ night: NightRecord) -> Bool {
    guard isFinite(night.start), isFinite(night.end), night.end > night.start,
          !night.sourceID.isEmpty, night.asleepSeconds.isFinite, night.awakeSeconds.isFinite,
          night.asleepSeconds > 0, night.awakeSeconds >= 0 else { return false }
    let span = night.end.timeIntervalSince(night.start)
    return span <= 24 * 3_600 && night.asleepSeconds + night.awakeSeconds <= span + 1
}

private func isValidNight(_ night: NightRecord) -> Bool {
    night.asleepSeconds >= Parameters.minimumSleep && bounded(night.heartRate, 20, 250) != nil
        && night.heartRateSampleCount >= 3 && night.heartRateCoverageSeconds.isFinite
        && night.heartRateCoverageSeconds >= 3_600
        && night.heartRateCoverageSeconds <= night.end.timeIntervalSince(night.start)
}

private func isValidHRV(_ night: NightRecord) -> Bool {
    guard let hrv = night.hrvSDNN else { return false }
    return hrv.isFinite && hrv > 0 && hrv <= 500 && night.hrvSampleCount >= 1
}

/// Overlapping session estimates contribute at most the highest asleep density at each instant.
private func combinedAsleepSeconds(_ sessions: [NightRecord]) -> Double {
    let boundaries = Array(Set(sessions.flatMap { [$0.start, $0.end] })).sorted()
    guard boundaries.count >= 2 else { return 0 }
    return zip(boundaries, boundaries.dropFirst()).reduce(0) { result, pair in
        let (start, end) = pair
        let density = sessions.filter { $0.start <= start && $0.end >= end }.map {
            min(1, $0.asleepSeconds / $0.end.timeIntervalSince($0.start))
        }.max() ?? 0
        return result + end.timeIntervalSince(start) * density
    }
}

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
}

private func mean(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    return values.reduce(0) { $0 + $1 / Double(values.count) }
}

private func robustDeviation(_ value: Double, values: [Double], floor: Double) -> Double {
    let center = median(values)
    let scale = max(median(values.map { abs($0 - center) }) * 1.4826, floor)
    return clamp((value - center) / scale, -3, 3)
}

private func clockMinutes(_ date: Date, calendar: Calendar) -> Double {
    let components = calendar.dateComponents([.hour, .minute, .second], from: date)
    return Double((components.hour ?? 0) * 60 + (components.minute ?? 0)) + Double(components.second ?? 0) / 60
}

private func clockDifference(_ lhs: Double, _ rhs: Double) -> Double {
    var difference = (lhs - rhs).truncatingRemainder(dividingBy: 1_440)
    if difference > 720 { difference -= 1_440 }
    if difference < -720 { difference += 1_440 }
    return difference
}

private func circularMedian(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let anchor = sorted.min { lhs, rhs in
        let left = sorted.reduce(0) { $0 + abs(clockDifference($1, lhs)) }
        let right = sorted.reduce(0) { $0 + abs(clockDifference($1, rhs)) }
        return left == right ? lhs < rhs : left < right
    } ?? 0
    return anchor + median(sorted.map { clockDifference($0, anchor) })
}

private func isFinite(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }
private func validEnergy(_ value: Double?) -> Double? { bounded(value, 0, 30_000) }
private func bounded(_ value: Double?, _ low: Double, _ high: Double) -> Double? {
    guard let value, value.isFinite, value >= low, value <= high else { return nil }
    return value
}
private func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(high, max(low, value)) }
private func integer(_ value: Double) -> String { decimal(value, places: 0) }
private func decimal(_ value: Double, places: Int) -> String {
    String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
}
private func duration(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分钟" : "\(minutes) 分钟"
}
