import ReadinessCore
import SwiftUI

enum ReadinessStyle {
    static var accent: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0, green: 0.84, blue: 0.76, alpha: 1)
                : UIColor(red: 0, green: 0.46, blue: 0.43, alpha: 1)
        })
        #else
        Color(red: 0, green: 0.84, blue: 0.76)
        #endif
    }

    static func color(for kind: FactorKind) -> Color {
        switch kind {
        case .activity: .pink
        case .vitals: .cyan
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
}

struct ReadinessCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ReadinessStyle.cardPadding)
            .background(ReadinessStyle.surface, in: RoundedRectangle(cornerRadius: 24))
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
            if dynamicTypeSize.isAccessibilitySize {
                ReadinessArcGauge(score: score)
                scoreLabel
            } else {
                ReadinessArcGauge(score: score)
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
                .font(.system(size: scoreSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(band.title)
                .font(.title3.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ReadinessStyle.accent)
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

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let thickness = width * 0.11
            let radius = (width - thickness) / 2
            let center = CGPoint(x: width / 2, y: width / 2)
            let angle = Angle.degrees(-170 + Double(min(10, max(0, score))) * 16)

            ZStack {
                Path { path in
                    path.addArc(center: center, radius: radius,
                                startAngle: .degrees(-170), endAngle: .degrees(-10), clockwise: false)
                }
                .stroke(ReadinessStyle.accent.opacity(0.18), style: StrokeStyle(lineWidth: thickness, lineCap: .round))

                Circle()
                    .fill(ReadinessStyle.accent.opacity(0.18))
                    .frame(width: thickness * 1.15, height: thickness * 1.15)
                    .overlay {
                        Circle()
                            .fill(ReadinessStyle.accent)
                            .padding(thickness * 0.23)
                    }
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
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: ReadinessStyle.symbol(for: factor.kind))
                .font(.title3)
                .foregroundStyle(ReadinessStyle.color(for: factor.kind))
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(factor.kind.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(factor.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(ReadinessStyle.cardPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

#Preview("准备度 · 10 分 · 大字体") {
    ReadinessScoreView(score: 10, band: .strong)
        .padding()
        .background(ReadinessStyle.background)
        .environment(\.dynamicTypeSize, .accessibility3)
}
