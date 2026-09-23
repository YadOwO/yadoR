import Foundation

public enum ReadinessBand: String, Codable, Sendable, CaseIterable {
    case recover, gentle, ready, strong

    public init(score: Int) {
        switch score {
        case ...1: self = .recover
        case 2...4: self = .gentle
        case 5...7: self = .ready
        default: self = .strong
        }
    }

    public var title: String {
        switch self {
        case .recover: "建议休整"
        case .gentle: "适当放缓"
        case .ready: "状态就绪"
        case .strong: "适合挑战"
        }
    }

    public var explanation: String {
        switch self {
        case .recover: "今天给自己多一些恢复的空间。"
        case .gentle: "放慢一点，留意身体的感受。"
        case .ready: "按自己的节奏，开始今天。"
        case .strong: "状态不错，结合身体感受安排活动。"
        }
    }
}

public enum AssessmentStatus: String, Codable, Sendable {
    case notSetUp, buildingBaseline, missingData, ready, waitingForPhone
}

public enum FactorKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case sleep, vitals, activity
    public var id: Self { self }
    public var title: String {
        switch self {
        case .sleep: "睡眠"
        case .vitals: "生命体征"
        case .activity: "活动"
        }
    }
    public var symbol: String {
        switch self {
        case .sleep: "moon.zzz.fill"
        case .vitals: "waveform.path.ecg"
        case .activity: "figure.walk"
        }
    }
}

public struct FactorMetric: Codable, Equatable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var value: String
    public var reference: String?
    public init(title: String, value: String, reference: String? = nil) {
        self.title = title; self.value = value; self.reference = reference
    }
}

public struct ReadinessFactor: Codable, Equatable, Sendable, Identifiable {
    public var id: FactorKind { kind }
    public var kind: FactorKind
    public var summary: String
    public var explanation: String
    public var metrics: [FactorMetric]
    public var omitted: [String]
    public init(kind: FactorKind, summary: String, explanation: String,
                metrics: [FactorMetric] = [], omitted: [String] = []) {
        self.kind = kind; self.summary = summary; self.explanation = explanation
        self.metrics = metrics; self.omitted = omitted
    }
}

public struct ReadinessSnapshot: Codable, Equatable, Sendable {
    public static let algorithmVersion = "0.1-experimental"
    public var status: AssessmentStatus
    public var day: Date
    public var timeZoneIdentifier: String
    public var generatedAt: Date
    public var dataThrough: Date?
    public var score: Int?
    public var validNights: Int
    public var requiredNights: Int
    public var message: String
    public var factors: [ReadinessFactor]
    public var sourceName: String?
    public var algorithmVersion: String
    public var isDemo: Bool

    public init(status: AssessmentStatus, day: Date, generatedAt: Date,
                timeZoneIdentifier: String = TimeZone.current.identifier,
                dataThrough: Date? = nil, score: Int? = nil, validNights: Int = 0,
                requiredNights: Int = 7, message: String, factors: [ReadinessFactor] = [],
                sourceName: String? = nil, algorithmVersion: String = Self.algorithmVersion,
                isDemo: Bool = false) {
        self.status = status; self.day = day; self.generatedAt = generatedAt
        self.timeZoneIdentifier = timeZoneIdentifier; self.dataThrough = dataThrough
        self.score = score; self.validNights = validNights; self.requiredNights = requiredNights
        self.message = message; self.factors = factors; self.sourceName = sourceName
        self.algorithmVersion = algorithmVersion; self.isDemo = isDemo
    }

    public var band: ReadinessBand? { score.map(ReadinessBand.init(score:)) }

    /// A previous day's result must never be presented as today's score.
    public func visible(at date: Date, calendar: Calendar = .current) -> Self {
        guard status == .ready, !calendar.isDate(day, inSameDayAs: date) else { return self }
        var result = self
        result.status = .missingData
        result.score = nil
        result.factors = []
        result.message = "今天的结果尚未更新，请在 iPhone 上打开 yadoR。"
        return result
    }

    public static func empty(at date: Date = .now, watch: Bool = false) -> Self {
        Self(status: watch ? .waitingForPhone : .notSetUp,
             day: Calendar.current.startOfDay(for: date), generatedAt: date,
             message: watch ? "在 iPhone 上打开 yadoR，连接健康数据后即可查看。" : "连接健康数据，了解今天的准备状态。")
    }
}

public struct NightRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var sourceID: String
    public var sourceName: String
    public var start: Date
    public var end: Date
    public var asleepSeconds: Double
    public var awakeSeconds: Double
    public var heartRate: Double?
    public var heartRateSampleCount: Int
    public var heartRateCoverageSeconds: Double
    public var hrvSDNN: Double?
    public var hrvSampleCount: Int
    public var respiratoryRate: Double?
    public var wristTemperature: Double?
    public var oxygenSaturation: Double?

    public init(id: String, sourceID: String, sourceName: String, start: Date, end: Date,
                asleepSeconds: Double, awakeSeconds: Double = 0, heartRate: Double? = nil,
                heartRateSampleCount: Int = 0, heartRateCoverageSeconds: Double = 0,
                hrvSDNN: Double? = nil, hrvSampleCount: Int = 0,
                respiratoryRate: Double? = nil, wristTemperature: Double? = nil,
                oxygenSaturation: Double? = nil) {
        self.id = id; self.sourceID = sourceID; self.sourceName = sourceName
        self.start = start; self.end = end; self.asleepSeconds = asleepSeconds
        self.awakeSeconds = awakeSeconds; self.heartRate = heartRate
        self.heartRateSampleCount = heartRateSampleCount
        self.heartRateCoverageSeconds = heartRateCoverageSeconds
        self.hrvSDNN = hrvSDNN; self.hrvSampleCount = hrvSampleCount
        self.respiratoryRate = respiratoryRate; self.wristTemperature = wristTemperature
        self.oxygenSaturation = oxygenSaturation
    }
}

public struct ActivityDay: Codable, Equatable, Sendable {
    public var day: Date
    /// nil means unavailable, not zero activity.
    public var activeEnergy: Double?
    public var workoutMinutes: Double
    public var effortLoad: Double?
    public var restingHeartRate: Double?
    public init(day: Date, activeEnergy: Double? = nil, workoutMinutes: Double = 0,
                effortLoad: Double? = nil, restingHeartRate: Double? = nil) {
        self.day = day; self.activeEnergy = activeEnergy
        self.workoutMinutes = workoutMinutes; self.effortLoad = effortLoad
        self.restingHeartRate = restingHeartRate
    }
}

public struct ReadinessInput: Codable, Equatable, Sendable {
    public var nights: [NightRecord]
    public var activity: [ActivityDay]
    public var dataThrough: Date?
    /// Stable digest of all relevant samples, including values and deletions.
    public var fingerprint: String
    public init(nights: [NightRecord], activity: [ActivityDay], dataThrough: Date?, fingerprint: String) {
        self.nights = nights; self.activity = activity; self.dataThrough = dataThrough
        self.fingerprint = fingerprint
    }
}
