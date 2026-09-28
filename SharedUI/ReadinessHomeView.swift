import ReadinessCore
import SwiftUI

struct ReadinessHomeView: View {
    @Environment(ReadinessStore.self) private var store
    @State private var navigationID = UUID()

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                ReadinessDashboard(snapshot: store.snapshot.visible(at: context.date), date: context.date)
            }
            #if os(iOS)
            .navigationTitle("准备度")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ReadinessSettingsView()
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("说明与设置")
                    .accessibilityIdentifier("open_settings")
                }
            }
            #endif
        }
        .id(navigationID)
        .onOpenURL { url in
            if url.scheme == "yador", url.host == "today" { navigationID = UUID() }
        }
        .tint(ReadinessStyle.accent)
    }
}

private struct ReadinessDashboard: View {
    @Environment(ReadinessStore.self) private var store
    let snapshot: ReadinessSnapshot
    let date: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                #if os(iOS)
                Text(dateHeading)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                if store.isDemo {
                    DemoNotice()
                }
                #endif

                mainContent

                #if os(watchOS)
                if store.isDemo {
                    DemoNotice()
                }
                if let band = snapshot.band, snapshot.status == .ready {
                    Text(band.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                #endif

                if let error = store.errorMessage {
                    ReadinessCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("暂时无法更新", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text(error)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityIdentifier("refresh_error")
                }

                #if os(iOS)
                if snapshot.status == .ready, !snapshot.factors.isEmpty {
                    factorLinks
                }
                #endif

                if let syncMessage = store.syncMessage {
                    Label(syncMessage, systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SnapshotMetadataView(snapshot: snapshot)

                if showRefresh {
                    refreshButton
                }

                #if os(watchOS)
                NavigationLink {
                    ReadinessSettingsView()
                } label: {
                    Label("说明与设置", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("open_settings")
                #endif

                #if DEBUG
                if store.isDemo {
                    Button("退出演示") {
                        Task { await store.exitDemo() }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("exit_demo")
                }
                #endif
            }
            .frame(maxWidth: 640)
            #if os(watchOS)
            .padding(.horizontal, ReadinessStyle.pagePadding)
            #else
            .padding(ReadinessStyle.pagePadding)
            #endif
            .frame(maxWidth: .infinity)
        }
        .background(ReadinessStyle.background)
        #if os(iOS)
        .refreshable {
            if store.hasConnectedHealth && !store.isDemo {
                await store.refresh()
            }
        }
        #endif
    }

    private var dateHeading: String {
        #if os(watchOS)
        date.formatted(.dateTime.month(.wide).day())
        #else
        date.formatted(.dateTime.month(.wide).day().weekday(.wide))
        #endif
    }

    private var sectionSpacing: CGFloat {
        #if os(watchOS)
        8
        #else
        16
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        if store.isRefreshing && snapshot.status == .notSetUp {
            ReadinessCard {
                VStack(alignment: .leading, spacing: 16) {
                    ProgressView()
                    Text("正在读取已有记录")
                        .font(.title3.weight(.semibold))
                    Text("先检查可用历史，再建立你的个人基线。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("initializing_state")
        } else if snapshot.status == .ready, let score = snapshot.score, let band = snapshot.band {
            #if os(watchOS)
            VStack(spacing: 8) {
                ReadinessScoreView(score: score, band: band)
                factorShortcuts
            }
            .background {
                RadialGradient(colors: [ReadinessStyle.accent.opacity(0.12), .clear],
                               center: .center, startRadius: 0, endRadius: 80)
                    .allowsHitTesting(false)
            }
            #else
            ReadinessCard {
                VStack(spacing: 20) {
                    HStack {
                        Text("今日准备度")
                            .font(.headline)
                        Spacer()
                        Text("0–10 分")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ReadinessScoreView(score: score, band: band)
                    Text(band.explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            #endif
        } else if snapshot.status == .notSetUp {
            #if os(iOS)
            ConnectHealthView()
            #else
            ReadinessStateCard(snapshot: .empty(watch: true))
            #endif
        } else {
            ReadinessStateCard(snapshot: snapshot)
        }
    }

    private var factorLinks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("影响因素")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(snapshot.factors) { factor in
                    NavigationLink {
                        FactorDetailView(kind: factor.kind)
                    } label: {
                        FactorRow(factor: factor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("factor_\(factor.kind.rawValue)")

                    if factor.id != snapshot.factors.last?.id {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(ReadinessStyle.surface, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    #if os(watchOS)
    private var factorShortcuts: some View {
        HStack(spacing: 4) {
            ForEach([FactorKind.activity, .vitals, .sleep]) { kind in
                if let factor = snapshot.factors.first(where: { $0.kind == kind }) {
                    NavigationLink {
                        FactorDetailView(kind: kind)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: ReadinessStyle.symbol(for: kind))
                                .font(.title3)
                            Text(kind.title)
                                .font(.caption2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(kind.title)，\(factor.summary)")
                    .accessibilityIdentifier("factor_\(kind.rawValue)")
                }
            }
        }
    }
    #endif

    private var showRefresh: Bool {
        #if os(watchOS)
        !store.isDemo
        #else
        store.hasConnectedHealth && !store.isDemo
        #endif
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            HStack(spacing: 8) {
                #if os(watchOS)
                Image(systemName: "arrow.clockwise")
                Text("请求同步")
                #else
                if store.isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(store.isRefreshing ? "正在更新" : "检查新数据")
                #endif
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(store.isRefreshing)
        .accessibilityIdentifier("refresh_readiness")
    }
}

private struct ReadinessStateCard: View {
    let snapshot: ReadinessSnapshot

    var body: some View {
        ReadinessCard {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(ReadinessStyle.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if snapshot.status == .buildingBaseline {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("有效夜晚 \(snapshot.validNights) / \(snapshot.requiredNights)")
                            .font(.headline.monospacedDigit())
                        ProgressView(
                            value: Double(min(max(0, snapshot.validNights), snapshot.requiredNights)),
                            total: Double(max(1, snapshot.requiredNights))
                        )
                        .tint(ReadinessStyle.accent)
                        .accessibilityLabel("个人基线")
                        .accessibilityValue("需要 \(snapshot.requiredNights) 晚，已有 \(snapshot.validNights) 晚")
                    }
                }

                Text(snapshot.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if snapshot.status == .buildingBaseline {
                    Text("继续佩戴手表入睡。已有的有效历史也会计入，不要求连续记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityIdentifier("state_\(snapshot.status.rawValue)")
    }

    private var title: String {
        switch snapshot.status {
        case .buildingBaseline: "正在了解你的节奏"
        case .waitingForPhone, .notSetUp: "从 iPhone 开始"
        case .missingData, .ready: "暂无法评估"
        }
    }

    private var symbol: String {
        switch snapshot.status {
        case .buildingBaseline: "moon.stars"
        case .waitingForPhone, .notSetUp: "iphone.and.arrow.forward"
        case .missingData, .ready: "clock.badge.questionmark"
        }
    }
}

#if os(iOS)
private struct ConnectHealthView: View {
    @Environment(ReadinessStore.self) private var store
    @State private var confirmsAge = false

    var body: some View {
        ReadinessCard {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "sun.horizon")
                    .font(.largeTitle)
                    .foregroundStyle(ReadinessStyle.accent)
                    .accessibilityHidden(true)

                Text("了解状态，\n找到今天的节奏。")
                    .font(.largeTitle.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("结合睡眠、生命体征与活动记录，用独立算法提供每日准备度参考。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 14) {
                    Label("先读取已有历史，至少需要 7 个有效夜晚。", systemImage: "moon.zzz")
                    Label("只读健康数据，在设备上处理，不上传服务器。", systemImage: "lock.shield")
                }
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)

                Toggle("我已年满 13 岁", isOn: $confirmsAge)
                    .accessibilityIdentifier("confirm_age")

                Button {
                    Task { await store.connectHealth() }
                } label: {
                    Text("连接健康数据")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!confirmsAge || store.isRefreshing)
                .accessibilityIdentifier("connect_health")
            }
        }
    }
}
#endif

#Preview("建立基线") {
    ReadinessStateCard(snapshot: ReadinessSnapshot(
        status: .buildingBaseline,
        day: .now,
        generatedAt: .now,
        validNights: 3,
        message: "还需要更多同时包含睡眠和夜间生命体征的记录。"
    ))
    .padding()
    .background(ReadinessStyle.background)
}

#Preview("当日缺少数据") {
    ReadinessStateCard(snapshot: ReadinessSnapshot(
        status: .missingData,
        day: .now,
        generatedAt: .now,
        message: "尚未读到昨晚的主要睡眠记录。佩戴手表入睡后，再检查新数据。"
    ))
    .padding()
    .background(ReadinessStyle.background)
}
