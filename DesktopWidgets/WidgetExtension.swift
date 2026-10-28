import SwiftUI
import WidgetKit

struct MintDashboardEntry: TimelineEntry {
    var date: Date
    var snapshot: MintWidgetSnapshot
    var message: String?
}

struct MintDashboardProvider: TimelineProvider {
    func placeholder(in context: Context) -> MintDashboardEntry {
        MintDashboardEntry(date: Date(), snapshot: .sample())
    }
    func getSnapshot(in context: Context, completion: @escaping (MintDashboardEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MintDashboardEntry>) -> Void) {
        completion(Timeline(entries: [load()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }
    private func load() -> MintDashboardEntry {
        do { return MintDashboardEntry(date: Date(), snapshot: try MintWidgetFiles().displayedSnapshot()) }
        catch {
            return MintDashboardEntry(date: Date(), snapshot: MintWidgetSnapshot(), message: "请先打开 Mint Todo 试用版")
        }
    }
}

struct MintDashboardEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MintDashboardEntry
    var body: some View {
        MintWidgetCard(snapshot: entry.snapshot,
                       size: family == .systemSmall ? .small : family == .systemMedium ? .medium : .large,
                       message: entry.message, now: entry.date)
            .containerBackground(for: .widget) { MintWidgetBackground(theme: entry.snapshot.theme) }
            .widgetURL(URL(string: "minttodo-widgets-trial://preview"))
    }
}

struct MintDashboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MintWidgetFiles.kind, provider: MintDashboardProvider()) { entry in
            MintDashboardEntryView(entry: entry)
        }
        .configurationDisplayName("Mint Todo · 试用")
        .description("Small 看进度，Medium 勾选全部待办，Large 查看多个目标与阶段。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main struct MintWidgetsBundle: WidgetBundle {
    var body: some Widget { MintDashboardWidget() }
}
