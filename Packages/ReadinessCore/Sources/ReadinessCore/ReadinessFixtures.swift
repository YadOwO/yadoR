import Foundation

/// Explicit preview/UI-test fixtures. Never used by the health data pipeline.
public enum ReadinessFixtures {
    public static func snapshot(status: AssessmentStatus = .ready, at date: Date = .now) -> ReadinessSnapshot {
        let factors = [
            ReadinessFactor(kind: .sleep, summary: "睡眠接近平时",
                explanation: "主要睡眠较完整，入睡时间也接近你的近期作息。",
                metrics: [.init(title: "睡眠时长", value: "7 小时 42 分", reference: "个人参考 7 小时 35 分"),
                          .init(title: "睡眠中清醒", value: "18 分钟")]),
            ReadinessFactor(kind: .vitals, summary: "夜间体征平稳",
                explanation: "夜间心率和 HRV 与你的近期个人基线接近。",
                metrics: [.init(title: "夜间心率", value: "56 次/分", reference: "个人参考 58 次/分"),
                          .init(title: "夜间 HRV · SDNN", value: "48 毫秒", reference: "个人参考 45 毫秒")],
                omitted: ["腕温、呼吸频率和血氧未计入本版评分"]),
            ReadinessFactor(kind: .activity, summary: "活动负荷适中",
                explanation: "最近的活动量接近平时，今天尚未出现明显额外负荷。",
                metrics: [.init(title: "今日活动能量", value: "236 千卡"),
                          .init(title: "近期每日参考", value: "420 千卡")],
                omitted: ["使用活动能量估计负荷，未使用苹果训练负荷结果"])
        ]
        let message: String
        switch status {
        case .ready: message = ReadinessBand.ready.explanation
        case .buildingBaseline: message = "已获得 3 晚有效记录，继续睡眠佩戴以建立个人基线。"
        case .missingData: message = "未读到昨晚足够的 HRV 记录，暂时无法评估。"
        case .notSetUp: message = "连接健康数据，了解今天的准备状态。"
        case .waitingForPhone: message = "在 iPhone 上打开 yadoR，完成设置后即可查看。"
        }
        return ReadinessSnapshot(status: status, day: Calendar.current.startOfDay(for: date),
            generatedAt: date.addingTimeInterval(-720), dataThrough: date.addingTimeInterval(-900),
            score: status == .ready ? 7 : nil, validNights: status == .buildingBaseline ? 3 : 14,
            message: message, factors: status == .ready ? factors : [],
            sourceName: "Apple Watch · 示例", isDemo: true)
    }
}
