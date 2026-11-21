import SwiftUI
import ZoopData

/// The same calendar navigation and inspection surface in Trends and Morning.
struct TrendHistoryView: View {
    let snapshot: TrendSnapshot
    let metric: TrendMetric
    var initialDay: Date?
    var insights: MorningInsights?
    var integrated = false
    let open: (TrendPoint) -> Void
    @State private var range: TrendRange = .month
    @State private var anchor: Date?
    init(snapshot: TrendSnapshot, metric: TrendMetric, initialDay: Date? = nil,
         insights: MorningInsights? = nil, initialRange: TrendRange = .month, integrated: Bool = false, open: @escaping (TrendPoint) -> Void) {
        self.snapshot = snapshot; self.metric = metric; self.initialDay = initialDay
        self.integrated = integrated
        self.insights = insights; self.open = open; _range = State(initialValue: initialRange)
    }
    private var interval: DateInterval { range.interval(containing: anchor ?? initialDay ?? snapshot.now, calendar: snapshot.calendar) }
    private func destination(_ direction: Int) -> DateInterval? {
        let next = range.moved(interval, by: direction, calendar: snapshot.calendar)
        guard next.start <= snapshot.now, let first = snapshot.first, next.end > first else { return nil }
        return next
    }
    var body: some View {
        Group {
            if integrated { content.zoopCard() } else { content }
        }
        .onChange(of: range) { old, new in
            let oldPage = old.interval(containing: anchor ?? initialDay ?? snapshot.now, calendar: snapshot.calendar)
            anchor = min(oldPage.end.addingTimeInterval(-1), snapshot.now)
        }
        .onChange(of: initialDay) { _, _ in anchor = nil }
    }
    private var content: some View {
        VStack(spacing: 12) {
            Picker("Period", selection: $range) {
                ForEach(TrendRange.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            TrendChartCard(metric: metric, range: range,
                           interval: interval, now: snapshot.now, calendar: snapshot.calendar,
                           series: snapshot.series(metric, range: range, containing: interval.start),
                           pattern: snapshot.weekdayPattern(metric), insights: insights,
                           integrated: integrated, showsReadout: !integrated || !interval.contains(initialDay ?? snapshot.now),
                           canGoBack: destination(-1) != nil, canGoForward: destination(1) != nil,
                           page: move, open: open)
        }
    }
    private func move(_ direction: Int) {
        guard let next = destination(direction) else { return }
        anchor = next.start
    }
}
