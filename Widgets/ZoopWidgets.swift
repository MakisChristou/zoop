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

private protocol ZoopWidget: Widget { var kind: ZoopWidgetKind { get } }
private struct TodayWidget: ZoopWidget { let kind = ZoopWidgetKind.today }
private struct RecoveryWidget: ZoopWidget { let kind = ZoopWidgetKind.recovery }
private struct WeightWidget: ZoopWidget { let kind = ZoopWidgetKind.weight }
private extension ZoopWidget {
    @MainActor var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Zoop" + kind.rawValue, provider: Provider()) { entry in
            ZoopWidgetPanel(kind: kind, entry: entry)
                .privacySensitive()
                .containerBackground(for: .widget) { Color(white: 0.085) }
        }
        .configurationDisplayName(kind.rawValue)
        .description(kind.detail)
        .supportedFamilies([kind.family])
    }
}
@main
struct ZoopWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        RecoveryWidget()
        WeightWidget()
    }
}
