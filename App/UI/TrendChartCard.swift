import Charts
import ZoopData
import SwiftUI

/// Selection stays inside the card; inspecting never rebuilds the history snapshot.
struct TrendChartCard: View {
    let metric: TrendMetric
    let range: TrendRange
    let interval: DateInterval
    let calendar: Calendar
    let series: TrendSeries
    var pattern: TrendSeries?
    var insights: MorningInsights?
    let canGoBack: Bool
    let canGoForward: Bool
    let page: (Int) -> Void
    let open: (TrendPoint) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedDate: Date?
    @State private var showComparisons = false
    private var selected: TrendPoint? { selectedDate.flatMap { date in series.points.first { $0.date == date } } }
    private var displayed: TrendPoint? { selected ?? series.points.last }
    private var description: String {
        guard let point = displayed else { return "No readings" }
        return "\(metric.formatted(point.value)) \(metric.readoutUnit), \(point.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            periodNavigation
            readout
            chart
            if !series.points.isEmpty {
                DisclosureGroup(isExpanded: $showComparisons) {
                    comparisonDetails.padding(.top, 8)
                } label: {
                    Text(insights == nil ? "Comparisons" : "Comparison details")
                        .font(.subheadline).frame(minHeight: 44)
                }.tint(ZoopStyle.secondary).accessibilityIdentifier("trendComparisons")
            }
        }
        .zoopCard()
        .onChange(of: metric) { _, _ in selectedDate = nil }
        .onChange(of: interval) { _, _ in selectedDate = nil }
        .onChange(of: series.points) { _, points in
            if let selectedDate, !points.contains(where: { $0.date == selectedDate }) { self.selectedDate = nil }
        }
    }
    private var periodNavigation: some View {
        HStack(spacing: 4) {
            Button { page(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                .disabled(!canGoBack).accessibilityLabel("Previous period").accessibilityIdentifier("trendPreviousPeriod")
            Text(range.title(interval, calendar: calendar))
                .font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).accessibilityIdentifier("trendPeriod")
            Button { page(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                .disabled(!canGoForward).accessibilityLabel("Next period").accessibilityIdentifier("trendNextPeriod")
        }.buttonStyle(.plain)
    }
    private var readout: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        return layout {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(metric.rawValue)
                    if selected != nil { Image(systemName: "chevron.right").font(.caption2).accessibilityHidden(true) }
                }.font(.caption.weight(.semibold)).foregroundStyle(ZoopStyle.secondary)
                MetricValue(displayed.map { metric.formatted($0.value) } ?? "—", unit: metric.readoutUnit, size: 36)
                    .foregroundStyle(metric.color).accessibilityIdentifier("trendReadingValue")
                Text(displayed.map { $0.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()) } ?? "No readings")
                    .font(.caption).foregroundStyle(ZoopStyle.secondary).accessibilityIdentifier("trendReadingDate")
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityHidden(selected != nil)
            .overlay {
                if selected != nil {
                    Button { openReading() } label: { Color.clear.contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("View \(metric == .steps ? "steps" : "sleep") details")
                        .accessibilityValue(description).accessibilityIdentifier("trendOpenDetail")
                }
            }
            Button("Latest") { selectedDate = nil }
                .font(.subheadline.weight(.medium)).buttonStyle(.bordered).buttonBorderShape(.capsule)
                .frame(minHeight: 44).opacity(selected == nil ? 0 : 1)
                .allowsHitTesting(selected != nil).accessibilityHidden(selected == nil)
                .accessibilityIdentifier("trendLatest")
        }
    }
    private var chart: some View {
        Chart {
            if showComparisons {
                ForEach(series.rolling) { point in
                    LineMark(x: .value("Date", point.date), y: .value("7-day average", point.value), series: .value("Series", "mean-\(series.segmentByDate[point.date] ?? 0)"))
                        .foregroundStyle(metric.color.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                if let average = series.average {
                    RuleMark(y: .value("Period average", average))
                        .foregroundStyle(ZoopStyle.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            ForEach(series.points) { point in
                LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value), series: .value("Series", "daily-\(series.segmentByDate[point.date] ?? 0)"))
                    .foregroundStyle(metric.color).lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                    .foregroundStyle(metric.color).symbolSize(range == .week ? 24 : range == .all ? 5 : 12)
            }
            if let selected {
                RuleMark(x: .value("Selected date", selected.date)).foregroundStyle(ZoopStyle.secondary.opacity(0.6))
                PointMark(x: .value("Date", selected.date), y: .value(metric.rawValue, selected.value))
                    .foregroundStyle(metric.color).symbolSize(65)
            }
        }
        .chartXScale(domain: interval.start...interval.end.addingTimeInterval(-1))
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: range == .week ? 7 : 4)) { value in
                AxisGridLine().foregroundStyle(ZoopStyle.separator)
                if let date = value.as(Date.self) {
                    AxisValueLabel { Text(date.formatted(range == .week ? .dateTime.weekday(.narrow) : range == .all ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))) }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
            AxisGridLine().foregroundStyle(ZoopStyle.separator)
            AxisValueLabel { if let number = value.as(Double.self) { Text(metric.axisLabel(number)) } }
        } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: 210)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let anchor = proxy.plotFrame {
                    let plot = geo[anchor]
                    CalendarChartGesture(select: { point in
                        guard plot.contains(point), let date: Date = proxy.value(atX: point.x - plot.minX), let index = series.nearestIndex(to: date) else { return }
                        selectedDate = series.points[index].date
                    }, page: page)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.rawValue) trend chart").accessibilityValue(description)
        .accessibilityHint("Swipe up or down to inspect readings. Use the actions to change period or view details.")
        .accessibilityAdjustableAction { moveSelection($0 == .increment ? 1 : -1) }
        .accessibilityAction(named: "Previous period") { if canGoBack { page(-1) } }
        .accessibilityAction(named: "Next period") { if canGoForward { page(1) } }
        .accessibilityAction(named: "View \(metric == .steps ? "steps" : "sleep") details", openReading)
        .accessibilityAction(named: "Latest reading") { selectedDate = nil }
        .accessibilityIdentifier("trendsChart")
    }
    private var yDomain: ClosedRange<Double> {
        guard let low = series.minimum, let high = series.maximum else { return 0...1 }
        let minimumPadding: Double = metric == .sleep ? 0.5 : metric == .skinTemp ? 0.2 : metric == .steps ? 500 : 1
        let padding = max((high - low) * 0.15, minimumPadding)
        return max(0, low - padding)...(high + padding)
    }
    private var comparisonDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let insights { InsightComparisonDetails(insights: insights, metric: metric) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: typeSize.isAccessibilitySize ? 2 : 4), alignment: .leading, spacing: 12) {
                stat("Min", series.minimum); stat("Average", series.average); stat("Max", series.maximum)
                VStack(alignment: .leading, spacing: 4) { Text("Days").font(.caption2); Text(series.points.count.formatted()).font(.subheadline.weight(.medium)) }
            }
            HStack(spacing: 12) {
                Label("7-day average", systemImage: "line.diagonal").symbolRenderingMode(.hierarchical)
                Label("Period average", systemImage: "ellipsis")
            }.font(.caption2).foregroundStyle(ZoopStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let pattern { TrendWeekdayPattern(metric: metric, series: pattern, calendar: calendar) }
        }
    }
    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(ZoopStyle.secondary)
            Text(value.map(metric.formatted) ?? "—").font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }
    private func openReading() { if let displayed { open(displayed) } }
    private func moveSelection(_ delta: Int) {
        guard !series.points.isEmpty else { return }
        let index = selected.flatMap { series.nearestIndex(to: $0.date) } ?? series.points.count - 1
        selectedDate = series.points[min(max(index + delta, 0), series.points.count - 1)].date
    }
}
