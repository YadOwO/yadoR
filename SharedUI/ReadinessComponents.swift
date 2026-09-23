import ReadinessCore
import SwiftUI

enum ReadinessStyle {
    static var toolbarForeground: Color {
        #if os(watchOS)
        .black
        #else
        .primary
        #endif
    }
    static var accent: Color {
        #if os(watchOS)
        Color(red: 0.32, green: 0.84, blue: 0.82)
        #else
        Color(red: 0.02, green: 0.43, blue: 0.42)
        #endif
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
        8
        #endif
    }

    static var cardPadding: CGFloat {
        #if os(iOS)
        24
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
    var body: some View {
        #if os(watchOS)
        Text("演示数据 · 非个人评估")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("demo_notice")
        #else
        Label("演示数据 · 非个人评估", systemImage: "testtube.2")
            .font(.caption.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .foregroundStyle(.orange)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("demo_notice")
        #endif
    }
}

struct ReadinessScoreView: View {
    let score: Int
    let band: ReadinessBand

    #if os(iOS)
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 94.0
    #else
    @ScaledMetric(relativeTo: .largeTitle) private var scoreSize = 50.0
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("今日准备度")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(score, format: .number)
                        .font(.system(size: scoreSize, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(ReadinessStyle.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("/ 10")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Text(band.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日准备度，\(score) 分，满分 10 分，\(band.title)")
            .accessibilityIdentifier("readiness_score")

            ReadinessScale(score: score)
                .accessibilityHidden(true)

            Text(band.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var verticalSpacing: CGFloat {
        #if os(watchOS)
        8
        #else
        16
        #endif
    }
}

private struct ReadinessScale: View {
    let score: Int
    private let bands = [Array(0...1), Array(2...4), Array(5...7), Array(8...10)]

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 7) {
                ForEach(bands.indices, id: \.self) { bandIndex in
                    HStack(spacing: 3) {
                        ForEach(bands[bandIndex], id: \.self) { position in
                            Capsule()
                                .fill(position == score ? ReadinessStyle.accent : ReadinessStyle.accent.opacity(0.18))
                                .frame(maxWidth: .infinity)
                                .frame(height: position == score ? 14 : 6)
                        }
                    }
                }
            }
            .frame(height: 16)

            HStack {
                Text("0")
                Spacer()
                Text("10")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }
}

struct FactorRow: View {
    let factor: ReadinessFactor

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: factor.kind.symbol)
                .font(.title3)
                .foregroundStyle(ReadinessStyle.accent)
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
        .background(ReadinessStyle.surface, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
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
