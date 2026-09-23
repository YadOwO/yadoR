import ReadinessCore
import SwiftUI

struct ReadinessSettingsView: View {
    @Environment(ReadinessStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsClear = false

    var body: some View {
        List {
            if store.isDemo {
                DemoNotice()
            }

            Section("关于准备度") {
                Text("yadoR 根据睡眠、生命体征与活动相对个人基线的变化，计算 0–10 分的准备度。")
                Text("采用独立的实验算法，与 Apple 的准备指数算法不同。当前仍在校准，结果仅供日常状态参考，不能判断疾病或保证运动安全。")
                Text("适用于 13 岁及以上用户。")
                LabeledContent("算法版本", value: store.snapshot.algorithmVersion)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("四档状态") {
                bandRow("0–1", band: .recover)
                bandRow("2–4", band: .gentle)
                bandRow("5–7", band: .ready)
                bandRow("8–10", band: .strong)
            }

            Section("数据与隐私") {
                Text("只读取本次评估需要的健康数据：睡眠、心率、静息心率、HRV（SDNN）、呼吸频率、腕温、血氧、活动能量和体能训练。")
                Text("数据在设备上处理，不上传服务器。仅保存评分及解释等派生结果，并在配对的 iPhone、Apple Watch 和手表组件之间同步。")
                Text("部分指标没有可读记录时会注明未计入；核心记录不足时不生成分数。")
            }

            Section("检查健康数据权限") {
                Text("在 iPhone 的「健康」App 中打开个人资料，找到 yadoR 的数据访问权限，检查所需记录是否允许读取。")
                Text("未读到数据也可能因为手表记录尚未同步，或可读历史范围有限。授权完成不代表每一种记录都可读取。")
            }

            Section("更新与同步") {
                Text("iPhone 读取新的健康记录后更新评估，Apple Watch 显示最近同步的当天结果。手机暂不可达或系统尚未调度时，结果可能需要等待更新。")
                Text("页面分别显示结果更新时间和所用数据的截止时间。检查新数据不会凭时间流逝改变分数。")
            }

            Section {
                Button("清除本地派生结果", role: .destructive) {
                    confirmsClear = true
                }
                .accessibilityIdentifier("clear_local_results")
            } footer: {
                Text(clearFooter)
            }

            #if DEBUG
            Section("开发演示（仅调试版）") {
                Text("演示使用固定示例，不代表你的健康状态，不写入正式缓存或同步到其他设备。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                demoButton("查看评分示例", status: .ready)
                    .accessibilityIdentifier("demo_ready")
                demoButton("查看建立基线示例", status: .buildingBaseline)
                    .accessibilityIdentifier("demo_baseline")
                demoButton("查看缺少数据示例", status: .missingData)
                    .accessibilityIdentifier("demo_missing")
                demoButton("查看等待 iPhone 示例", status: .waitingForPhone)
                if store.isDemo {
                    Button("退出演示，恢复真实数据") {
                        Task {
                            await store.exitDemo()
                            dismiss()
                        }
                    }
                }
            }
            #endif
        }
        .navigationTitle("说明与设置")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog("清除本地派生结果？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清除结果", role: .destructive) {
                Task {
                    await store.clearLocalData()
                    dismiss()
                }
            }
        } message: {
            Text(clearMessage)
        }
    }

    private var clearFooter: String {
        #if os(watchOS)
        "只清除此手表上的评分缓存，不删除 iPhone 或 Apple「健康」中的数据。"
        #else
        "清除评分缓存并停止读取新记录，不删除 Apple「健康」中的原始记录。"
        #endif
    }

    private var clearMessage: String {
        #if os(watchOS)
        "只清除此手表上的派生结果，之后可以从 iPhone 重新同步。Apple「健康」中的原始记录不会删除。"
        #else
        "清除评分缓存并停止读取新记录，配对手表会在下次同步时清除结果。原始健康记录不会删除，之后可重新连接健康数据生成评估。"
        #endif
    }

    private func bandRow(_ range: String, band: ReadinessBand) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(range) 分 · \(band.title)")
                .font(.headline)
            Text(band.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    #if DEBUG
    private func demoButton(_ title: String, status: AssessmentStatus) -> some View {
        Button(title) {
            store.showDemo(status)
            dismiss()
        }
    }
    #endif
}
