import ReadinessCore
import SwiftUI

enum ReadinessStyle {
    static var accent: Color {
        adaptiveColor(light: (0, 0.46, 0.43), dark: (0, 0.84, 0.76))
    }

    static func color(for band: ReadinessBand) -> Color {
        switch band {
        case .recover: adaptiveColor(light: (0.70, 0.12, 0.40), dark: (1, 0.40, 0.71))
        case .gentle: adaptiveColor(light: (0.48, 0.20, 0.72), dark: (0.74, 0.47, 1))
        case .ready: adaptiveColor(light: (0.12, 0.36, 0.76), dark: (0.35, 0.67, 1))
        case .strong: accent
        }
    }

    static func color(for kind: FactorKind) -> Color {
        switch kind {
        case .activity: color(for: ReadinessBand.recover)
        case .vitals: adaptiveColor(light: (0, 0.42, 0.55), dark: (0.30, 0.82, 0.95))
        case .sleep: .indigo
        }
    }

    static func symbol(for kind: FactorKind) -> String {
        switch kind {
        case .activity: "figure.walk"
        case .vitals: "waveform.path.ecg"
        case .sleep: "bed.double.fill"
        }
    }

    static var background: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        .black
        #endif
    }

    static var surface: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(white: 0.10)
        #endif
    }

    static var pagePadding: CGFloat {
        #if os(iOS)
        20
        #else
        10
        #endif
    }

    static var cardPadding: CGFloat {
        #if os(iOS)
        20
        #else
        14
        #endif
    }

    private static func adaptiveColor(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat(rgb.0), green: CGFloat(rgb.1), blue: CGFloat(rgb.2), alpha: 1)
        })
        #else
        Color(red: dark.0, green: dark.1, blue: dark.2)
        #endif
    }
}

struct ReadinessCard<Content: View>: View {
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ReadinessStyle.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .fill(ReadinessStyle.surface)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: 24)
                                .fill(LinearGradient(colors: [tint.opacity(0.08), .clear],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
            }
    }
}

struct DemoNotice: View {
    #if os(watchOS)
    @ScaledMetric(relativeTo: .caption2) private var noticeSize = 10.0
    #endif

    var body: some View {
        Text("演示数据 · 非个人评估")
            #if os(watchOS)
            .font(.system(size: noticeSize))
            #else
            .font(.caption2)
            #endif
            .frame(maxWidth: .infinity)
            .foregroundStyle(.orange)
            .accessibilityIdentifier("demo_notice")
    }
}

struct ReadinessScoreView: View {
    let score: Int
    let band: ReadinessBand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    #if os(iOS)
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 64.0
    #else
    @ScaledMetric(relativeTo: .title) private var scoreSize = 30.0
    #endif

    var body: some View {
        VStack(spacing: 12) {
            if dynamicTypeSize >= .xxxLarge {
                ReadinessArcGauge(score: score, tint: ReadinessStyle.color(for: band))
                scoreLabel
            } else {
                ReadinessArcGauge(score: score, tint: ReadinessStyle.color(for: band))
                    .overlay(alignment: .bottom) { scoreLabel }
            }
        }
        .frame(maxWidth: gaugeWidth)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日准备度，\(score) 分，满分 10 分，\(band.title)")
        .accessibilityIdentifier("readiness_score")
    }

    private var scoreLabel: some View {
        VStack(spacing: 0) {
            Text(score, format: .number)
                .font(.system(size: scoreSize, weight: .semibold))
                .monospacedDigit()
            Text(band.title)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ReadinessStyle.color(for: band))
        .multilineTextAlignment(.center)
    }

    private var gaugeWidth: CGFloat {
        #if os(iOS)
        300
        #else
        150
        #endif
    }
}

private struct ReadinessArcGauge: View {
    let score: Int
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thickness = width * 0.11
            let radius = (width - thickness) / 2
            let center = CGPoint(x: width / 2, y: width / 2)
            let degrees = -170 + Double(min(10, max(0, score))) * 16
            let angle = Angle.degrees(degrees)

            ZStack {
                Path { path in
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(-170), endAngle: .degrees(-10), clockwise: false)
                }
                .stroke(tint.opacity(0.16), style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                Path { path in
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(max(-170, degrees - 12)),
                                endAngle: .degrees(min(-10, degrees + 12)), clockwise: false)
                }
                .stroke(tint.opacity(0.22), style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                Circle()
                    .fill(tint)
                    .frame(width: thickness * 0.55, height: thickness * 0.55)
                    .position(x: center.x + radius * cos(angle.radians),
                              y: center.y + radius * sin(angle.radians))
            }
        }
        .aspectRatio(1.5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct FactorRow: View {
    let factor: ReadinessFactor

    var body: some View {
        #if os(watchOS)
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: ReadinessStyle.symbol(for: factor.kind))
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(factor.kind.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(factor.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(ReadinessStyle.surface, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        #else
        ReadinessCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(factor.kind.title, systemImage: ReadinessStyle.symbol(for: factor.kind))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ReadinessStyle.color(for: factor.kind))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Text(factor.summary)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let metric = factor.metrics.first {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(metric.title).foregroundStyle(.secondary)
                            Spacer(minLength: 16)
                            Text(metric.value).foregroundStyle(.primary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.title).foregroundStyle(.secondary)
                            Text(metric.value).foregroundStyle(.primary)
                        }
                    }
                    .font(.subheadline)
                    .monospacedDigit()
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        #endif
    }
}

struct SnapshotMetadataView: View {
    let snapshot: ReadinessSnapshot

    var body: some View {
        if let dataThrough = snapshot.dataThrough {
            VStack(alignment: .leading, spacing: 6) {
                Text("结果更新 \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                Text("数据截至 \(dataThrough.formatted(date: .abbreviated, time: .shortened))")
                if let sourceName = snapshot.sourceName {
                    Text("来源：\(sourceName)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview("准备度 · 就绪") {
    ReadinessScoreView(score: 7, band: .ready)
        .padding()
        .background(ReadinessStyle.background)
}

#Preview("准备度 · 0 分") {
    ReadinessScoreView(score: 0, band: .recover)
        .padding()
        .background(ReadinessStyle.background)
}

#Preview("准备度 · 放缓") {
    ReadinessScoreView(score: 3, band: .gentle)
        .padding()
        .background(ReadinessStyle.background)
}

#Preview("准备度 · 挑战 · 深色") {
    ReadinessScoreView(score: 9, band: .strong)
        .padding()
        .background(ReadinessStyle.background)
        .preferredColorScheme(.dark)
}

#Preview("准备度 · 10 分 · 大字体") {
    ReadinessScoreView(score: 10, band: .strong)
        .padding()
        .background(ReadinessStyle.background)
        .environment(\.dynamicTypeSize, .accessibility3)
}
