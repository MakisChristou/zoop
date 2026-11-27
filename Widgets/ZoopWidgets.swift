import Charts
import SwiftUI
import WidgetKit

private struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ZoopWidgetEntry { .sample }
    func getSnapshot(in context: Context, completion: @escaping (ZoopWidgetEntry) -> Void) {
        completion(context.isPreview ? .sample : ZoopWidgetEntry(date: Date(), data: .read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ZoopWidgetEntry>) -> Void) {
        let now = Date(), data = WidgetSnapshot.read()
        let midnight = Calendar.current.dateInterval(of: .day, for: now)!.end
        completion(Timeline(entries: [ZoopWidgetEntry(date: now, data: data), ZoopWidgetEntry(date: midnight, data: data)], policy: .after(midnight)))
    }
}

private struct WidgetContent: View {
    @Environment(\.widgetFamily) var family
    let kind: ZoopWidgetKind
    let entry: ZoopWidgetEntry

    var body: some View {
        ZoopWidgetPanel(kind: kind, entry: entry, family: family)
    }
}

private protocol ZoopWidget: Widget { var kind: ZoopWidgetKind { get } }
private struct TodayWidget: ZoopWidget { let kind = ZoopWidgetKind.today }
private struct RecoveryWidget: ZoopWidget { let kind = ZoopWidgetKind.recovery }
private struct StepsWidget: ZoopWidget { let kind = ZoopWidgetKind.steps }
private struct EveryDayWidget: ZoopWidget { let kind = ZoopWidgetKind.everyDay }
private struct WeightWidget: ZoopWidget { let kind = ZoopWidgetKind.weight }
private struct SleepStagesWidget: ZoopWidget { let kind = ZoopWidgetKind.stages }
private struct RecentActivitiesWidget: ZoopWidget { let kind = ZoopWidgetKind.workouts }
private struct NightlyMetricsWidget: ZoopWidget { let kind = ZoopWidgetKind.metrics }
private extension ZoopWidget {
    @MainActor var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Zoop" + kind.rawValue, provider: Provider()) { entry in
            WidgetContent(kind: kind, entry: entry)
                .privacySensitive()
                .containerBackground(for: .widget) { Color(white: 0.085) }
        }
        .configurationDisplayName(kind.rawValue)
        .description(kind.detail)
        .supportedFamilies(kind.families)
    }
}
@main
struct ZoopWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RecoveryWidget()
        WeightWidget()
        StepsWidget()
        EveryDayWidget()
        SleepStagesWidget()
        RecentActivitiesWidget()
        NightlyMetricsWidget()
    }
}
