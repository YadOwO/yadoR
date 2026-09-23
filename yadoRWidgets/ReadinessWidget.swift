import SwiftUI
import WidgetKit
import ReadinessCore

struct ReadinessEntry: TimelineEntry {
    var date: Date
    var snapshot: ReadinessSnapshot
}

struct ReadinessProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReadinessEntry {
        ReadinessEntry(date: .now, snapshot: .empty(watch: true))
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadinessEntry) -> Void) {
        let now = Date.now
        let snapshot = context.isPreview ? ReadinessFixtures.snapshot(at: now) : read(at: now)
        completion(ReadinessEntry(date: now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadinessEntry>) -> Void) {
        let now = Date.now
        let snapshot = read(at: now)
        let midnight = Calendar.current.date(byAdding: .day, value: 1,
                                             to: Calendar.current.startOfDay(for: now))!
        let entries = [
            ReadinessEntry(date: now, snapshot: snapshot),
            ReadinessEntry(date: midnight, snapshot: snapshot.visible(at: midnight))
        ]
        completion(Timeline(entries: entries, policy: .after(min(now.addingTimeInterval(3600), midnight))))
    }

    private func read(at date: Date) -> ReadinessSnapshot {
        let envelope = try? SnapshotCache().load()
        return (envelope?.snapshot ?? .empty(watch: true)).visible(at: date)
    }
}

struct ReadinessWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReadinessEntry

    private var snapshot: ReadinessSnapshot { entry.snapshot.visible(at: entry.date) }
    private var score: String { snapshot.score.map(String.init) ?? "—" }
    private var title: String { snapshot.band?.title ?? "暂无结果" }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(snapshot.score == nil ? "准备度 · 暂无结果" : "准备度 \(score) · \(title)")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text(score).font(.system(.title2, design: .rounded, weight: .semibold))
                    Text("准备度").font(.system(size: 9))
                }
            case .accessoryCorner:
                Text(score).font(.system(.title3, design: .rounded, weight: .semibold))
                    .widgetLabel { Text(title) }
            default:
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("yadoR").font(.caption2)
                        Spacer()
                        Text(score).font(.system(.title3, design: .rounded, weight: .semibold))
                    }
                    Text(title).font(.headline)
                    if snapshot.status == .ready {
                        Text("更新于 \(snapshot.generatedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("打开 App 查看").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "yador://today"))
        .privacySensitive()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(snapshot.score == nil ? "准备度，暂无当日结果" : "准备度 \(score) 分，\(title)，更新于 \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
    }
}

@main
struct ReadinessWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SnapshotCache.widgetKind, provider: ReadinessProvider()) { entry in
            ReadinessWidgetView(entry: entry)
        }
        .configurationDisplayName("今日准备度")
        .description("查看准备状态和最近更新时间。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}
