import ReadinessCore
import SwiftUI

struct FactorDetailView: View {
    @Environment(ReadinessStore.self) private var store
    let kind: FactorKind

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = store.snapshot.visible(at: context.date)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.isDemo {
                        DemoNotice()
                    }

                    if let factor = snapshot.factors.first(where: { $0.kind == kind }) {
                        factorContent(factor)
                        SnapshotMetadataView(snapshot: snapshot)
                    } else {
                        ReadinessCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("暂无当天因素")
                                    .font(.headline)
                                Text(snapshot.message)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    ReadinessCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("核对原始记录")
                                .font(.headline)
                            Text(recordGuidance)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: 640)
                .padding(ReadinessStyle.pagePadding)
                .frame(maxWidth: .infinity)
            }
            .background(ReadinessStyle.background)
        }
        .navigationTitle(kind.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func factorContent(_ factor: ReadinessFactor) -> some View {
        ReadinessCard {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: kind.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(ReadinessStyle.accent)
                    .accessibilityHidden(true)
                Text(factor.summary)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(factor.explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        ForEach(factor.metrics) { metric in
            ReadinessCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(metric.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(metric.value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                    if let reference = metric.reference {
                        Text(reference)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }

        if !factor.omitted.isEmpty {
            ReadinessCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("本次未计入", systemImage: "info.circle")
                        .font(.headline)
                    ForEach(factor.omitted, id: \.self) { item in
                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var recordGuidance: String {
        switch kind {
        case .sleep:
            "在 iPhone 的「健康」App 中查看「睡眠」，可以核对原始睡眠记录。"
        case .vitals:
            "在 iPhone 的「健康」App 中查看心脏、呼吸等分类，可以核对原始生命体征记录。"
        case .activity:
            "在 iPhone 的「健身」App 中查看活动与体能训练，或在「健康」App 中核对活动记录。"
        }
    }
}
