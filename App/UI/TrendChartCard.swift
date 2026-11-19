import Charts
import ZoopData
import SwiftUI

/// Selection stays inside the card; inspecting never rebuilds the history snapshot.
struct TrendChartCard: View {
    let metric: TrendMetric
    let range: TrendRange
    let interval: DateInterval
    let now: Date
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
        VStack(alignment: .leading, spacing: 8) {
            periodNavigation
            VStack(alignment: .leading, spacing: 20) {
                readout
                chart
            }.padding(.bottom, 6).zoopCard()
            if !series.points.isEmpty {
                let comparisonLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0)) : AnyLayout(HStackLayout(alignment: .top))
                comparisonLayout {
                    DisclosureGroup(isExpanded: $showComparisons) {
                        comparisonDetails.padding(.top, 8)
                    } label: {
                        Text(typeSize.isAccessibilitySize ? "Compare" : "Comparisons")
                            .font(ZoopType.caption).frame(minHeight: 44)
                    }.tint(ZoopStyle.secondary).accessibilityIdentifier("trendComparisons")
                    if selected != nil {
                        Button("Latest") { selectedDate = nil }.font(ZoopType.caption).frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("trendLatest")
                    }
                }
            }
        }
        .onChange(of: metric) { _, _ in selectedDate = nil }
        .onChange(of: interval) { _, _ in selectedDate = nil }
        .onChange(of: series.points) { _, points in
            if let selectedDate, !points.contains(where: { $0.date == selectedDate }) { self.selectedDate = nil }
        }
    }
    private var periodNavigation: some View {
        VStack(spacing: 4) {
            if typeSize.isAccessibilitySize { periodTitle }
            HStack(spacing: 4) {
                Button { page(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .disabled(!canGoBack).accessibilityLabel("Previous period").accessibilityIdentifier("trendPreviousPeriod")
                if typeSize.isAccessibilitySize { Spacer() } else { periodTitle }
                Button { page(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .disabled(!canGoForward).accessibilityLabel("Next period").accessibilityIdentifier("trendNextPeriod")
            }.buttonStyle(.plain)
        }
    }
    private var periodTitle: some View {
        Text(range.title(interval, calendar: calendar))
            .font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)).multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).accessibilityIdentifier("trendPeriod")
    }
    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { metricTitle; Spacer(minLength: 12); readingValue }
                VStack(alignment: .leading, spacing: 6) { metricTitle; readingValue }
            }
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .accessibilityHidden(selected != nil)
            .overlay {
                if selected != nil {
                    Button { openReading() } label: { Color.clear.frame(minHeight: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("View \(metric == .steps ? "steps" : "sleep") details")
                        .accessibilityValue(description).accessibilityIdentifier("trendOpenDetail")
                }
            }

        }
    }
    private var metricTitle: some View {
        HStack(spacing: 4) {
            Text(selected.map { $0.date.formatted(.dateTime.day().month(.abbreviated)) } ?? metric.rawValue).font(ZoopType.headline).accessibilityIdentifier("trendReadingDate")
            if selected != nil { Image(systemName: "chevron.right").font(ZoopType.caption2) }
        }
    }
    private var readingValue: some View {
        Text((displayed.map { metric.formatted($0.value) } ?? "—") + " " + metric.readoutUnit)
            .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).monospacedDigit()
            .accessibilityIdentifier("trendReadingValue")
    }
    private var plotDomain: ClosedRange<Date> { ChartPresentation.dateDomain(interval, now: now) }
    private var axisDates: [Date] { ChartPresentation.dateTicks(plotDomain) }
    private var axisValues: [Double] { ChartPresentation.ticks(yDomain) }
    private var chart: some View {
        let isolated = Set(Dictionary(grouping: series.points) { series.segmentByDate[$0.date] ?? 0 }.values.filter { $0.count == 1 }.compactMap { $0.first?.date })
        return Chart {
            if showComparisons {
                ForEach(series.rolling) { point in
                    LineMark(x: .value("Date", point.date), y: .value("7-day average", point.value), series: .value("Series", "mean-\(series.segmentByDate[point.date] ?? 0)"))
                        .foregroundStyle(metric.color).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                if let average = series.average {
                    RuleMark(y: .value("Period average", average))
                        .foregroundStyle(ZoopStyle.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
            ForEach(series.points) { point in
                LineMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value), series: .value("Series", "daily-\(series.segmentByDate[point.date] ?? 0)"))
                    .foregroundStyle(metric.color.opacity(showComparisons ? 0.35 : 1)).lineStyle(StrokeStyle(lineWidth: showComparisons ? 1 : 2, lineCap: .round))
                PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                    .foregroundStyle(metric.color).symbolSize(isolated.contains(point.date) ? 30 : 0)
            }
            if let point = selected ?? series.points.last {
                PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                    .foregroundStyle(metric.color.opacity(0.18)).symbolSize(170)
                PointMark(x: .value("Date", point.date), y: .value(metric.rawValue, point.value))
                    .foregroundStyle(metric.color).symbolSize(65)
            }
            if let selected {
                RuleMark(x: .value("Selected date", selected.date)).foregroundStyle(ZoopStyle.secondary.opacity(0.6))
                PointMark(x: .value("Date", selected.date), y: .value(metric.rawValue, selected.value))
                    .foregroundStyle(metric.color).symbolSize(65)
            }
        }
        .chartXScale(domain: plotDomain).chartXScale(range: .plotDimension(startPadding: 0, endPadding: 6))
        .chartYScale(domain: axisValues[0]...axisValues[2])
        .chartLegend(.hidden).font(ZoopType.caption2)
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                if let date = value.as(Date.self) {
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : value.index == 2 ? .topTrailing : .top) { Text(date.formatted(range == .all ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated))).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary) }
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: axisValues) { value in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(ZoopStyle.chartGrid)
            AxisValueLabel { if let number = value.as(Double.self) { Text(metric.axisLabel(number)).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary) } }
        } }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(height: 164)
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
                VStack(alignment: .leading, spacing: 4) { Text("Days").font(ZoopType.caption2); Text(series.points.count.formatted()).font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)) }
            }
            HStack(spacing: 12) {
                Label("7-day average", systemImage: "line.diagonal").symbolRenderingMode(.hierarchical)
                Label("Period average", systemImage: "ellipsis")
            }.font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary).fixedSize(horizontal: false, vertical: true)
            if let pattern { TrendWeekdayPattern(metric: metric, series: pattern, calendar: calendar) }
        }
    }
    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary)
            Text(value.map(metric.formatted) ?? "—").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)).monospacedDigit()
        }
    }
    private func openReading() { if let displayed { open(displayed) } }
    private func moveSelection(_ delta: Int) {
        guard !series.points.isEmpty else { return }
        let index = selected.flatMap { series.nearestIndex(to: $0.date) } ?? series.points.count - 1
        selectedDate = series.points[min(max(index + delta, 0), series.points.count - 1)].date
    }
}
