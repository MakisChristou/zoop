import Charts
import ZoopData
import ZoopHealth
import SwiftUI

/// Raw readings and calendar paging; preparation runs only when the source changes.
struct WeightTrendChart: View {
    let readings: [WeightReading]
    let unit: String
    var target: WeightChartTarget? = nil
    var logWeight: () -> Void = {}
    var openReading: (WeightReading) -> Void = { _ in }
    @AppStorage("weightMovingAverage") private var showAverage = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var period: WeightCalendarPeriod = .month
    @State private var anchor = Date()
    @State private var now = Date()
    @State private var points: [WeightChartData.Point] = []
    @State private var averages: [WeightTrend.Point] = []
    @State private var selectedID: String?
    @ScaledMetric(relativeTo: .body) private var chartHeight = 164.0
    private var calendar: Calendar { .current }
    private var first: Date { points.first?.date ?? now }
    private var last: Date { points.last?.date ?? now }
    private var range: DateInterval { period.range(containing: anchor, first: first, last: last, calendar: calendar) }
    private var latestRange: DateInterval { period.range(containing: now, first: first, last: last, calendar: calendar) }
    private var bounds: Range<Int> { SortedWindow.range(points, from: range.start.timeIntervalSince1970, to: range.end.timeIntervalSince1970) { $0.date.timeIntervalSince1970 } }
    private var visible: ArraySlice<WeightChartData.Point> { points[bounds] }
    private var selected: WeightChartData.Point? { visible.first { $0.id == selectedID } }
    private var displayed: WeightChartData.Point? { selected ?? visible.last }
    private var canReturn: Bool { selectedID != nil || range != latestRange }
    private var rangeLabel: String {
        if period == .month { return range.start.formatted(.dateTime.month(.wide).year()) }
        let end = calendar.date(byAdding: .day, value: -1, to: range.end)!
        let sameYear = calendar.component(.year, from: range.start) == calendar.component(.year, from: end)
        return range.start.formatted(sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year()) + " – " + end.formatted(.dateTime.day().month(.abbreviated).year())
    }
    private var measurementDate: String {
        guard let date = displayed?.date else { return "No weigh-ins in this period" }
        let prefix = calendar.isDateInToday(date) ? "Today" : date.formatted(.dateTime.day().month(.abbreviated).year())
        return prefix + " · " + date.formatted(date: .omitted, time: .shortened)
    }
    private func display(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    private var scale: (range: ClosedRange<Double>, ticks: [Double]) {
        let rawValues = (visible.isEmpty ? Array(points.suffix(1)) : Array(visible)).map { display($0.kg) }
        let averageValues = showAverage ? averages.filter { $0.date >= range.start && $0.date < range.end }.map { display($0.average) } : []
        let values = rawValues + averageValues + (targetSegment == nil ? [] : target.map { [display($0.kg)] } ?? [])
        let low = values.min() ?? 80, high = values.max() ?? low, span = max(high - low, unit == "lb" ? 4 : 2)
        let magnitude = pow(10, floor(log10(span / 4)))
        let step = ([1.0, 2, 2.5, 5, 10].first { $0 >= span / 4 / magnitude } ?? 10) * magnitude
        let middle = (low + high) / 2, bottom = floor((middle - span * 0.6) / step) * step, top = ceil((middle + span * 0.6) / step) * step
        return (bottom...top, Array(stride(from: bottom, through: top + step * 0.01, by: step)))
    }
    private var targetSegment: DateInterval? { target?.segment(in: DateInterval(start: plotDomain.lowerBound, end: plotDomain.upperBound)) }
    private var targetLabel: String { target.map { "Target \(display($0.kg).formatted(.number.precision(.fractionLength(1)))) \(unit)" } ?? "" }
    private var plotDomain: ClosedRange<Date> { ChartPresentation.dateDomain(range, now: now) }
    private var ticks: [Date] { ChartPresentation.dateTicks(plotDomain) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Chart range", selection: $period) { ForEach(WeightCalendarPeriod.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented)
            HStack {
                periodButton(-1)
                Text(rangeLabel).font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center).accessibilityIdentifier("weightChartDates")
                periodButton(1)
            }
            VStack(alignment: .leading, spacing: 20) {
                Button { if let displayed { openReading(displayed.reading) } } label: {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) { headlineLabel; Spacer(minLength: 12); readingValue }
                        VStack(alignment: .leading, spacing: 6) { headlineLabel; readingValue }
                    }.frame(maxWidth: .infinity, minHeight: 20, alignment: .leading).padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.vertical, -12).disabled(displayed == nil)
                    .accessibilityIdentifier("openWeightReading")
                    .accessibilityHint(displayed?.reading.source == "snoop" ? "Edit this weigh-in" : "View this weigh-in")
            chart.frame(height: min(chartHeight, 320)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .overlay { if visible.isEmpty { Text("No weigh-ins in this period").font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).allowsHitTesting(false) } }
                .accessibilityElement(children: .ignore).accessibilityLabel("Weight chart").accessibilityIdentifier("weightChart")
                .accessibilityValue("\(rangeLabel). \(displayed.map { "\(display($0.kg).formatted(.number.precision(.fractionLength(1)))) \(unit). \(measurementDate)" } ?? "No weigh-ins")" + (targetSegment == nil ? "" : ". " + targetLabel))
                .accessibilityHint((targetSegment == nil ? "" : targetLabel + ". ") + "Swipe up or down to inspect readings. Previous and next period actions browse history.")
                .accessibilityAdjustableAction { direction in
                    guard !visible.isEmpty else { return }
                    let index = selectedID.flatMap { id in visible.firstIndex { $0.id == id } } ?? bounds.upperBound - 1
                    selectedID = points[min(bounds.upperBound - 1, max(bounds.lowerBound, index + (direction == .increment ? 1 : -1)))].id
                }
                .accessibilityAction(named: "Previous period") { move(-1) }
                .accessibilityAction(named: "Next period") { move(1) }
                .accessibilityScrollAction { edge in if edge == .leading { move(-1) }; if edge == .trailing { move(1) } }
            }.padding(.bottom, 6).zoopCard()
            HStack(alignment: .top) {
                Text(measurementDate).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary).accessibilityIdentifier("weightChartMeasurementDate")
                Spacer()
                logButton
            }
            HStack {
                HStack(spacing: 6) {
                    if showAverage { Circle().fill(ZoopStyle.text).frame(width: 5, height: 5) }
                    if showAverage { Text("Weight") }
                    if showAverage {
                        Rectangle().fill(ZoopStyle.sleep).frame(width: 12, height: 2)
                        Text("7-day average")
                    }
                }.font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                Spacer(minLength: 4)
                if canReturn {
                    Button { anchor = now; selectedID = nil } label: {
                        Text("Latest")
                            .font(ZoopType.font(size: 12, weight: .medium, relativeTo: .caption))
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("weightChartLatest")
                } else {
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }
            }
        }
        .onChange(of: readings, initial: true) { _, _ in prepare() }
        .onChange(of: period) { _, _ in selectedID = nil }
        .onChange(of: scenePhase) { _, phase in if phase == .active { prepare() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in prepare() }
    }
    private var readingValue: some View {
        Text((displayed.map { display($0.kg).formatted(.number.precision(.fractionLength(1))) } ?? "—") + " " + unit)
            .font(ZoopType.subheadline).foregroundStyle(ZoopStyle.secondary).monospacedDigit().accessibilityIdentifier("weightChartValue")
    }
    private var headlineLabel: some View {
        Text(selected != nil ? "Selected weigh-in" : range == latestRange ? "Weight" : "Last in this period")
            .font(ZoopType.headline).foregroundStyle(ZoopStyle.text).accessibilityIdentifier("weightChartHeadline")
    }
    @ViewBuilder private var logButton: some View {
        if WeightReading.preferred(readings, on: now, calendar: calendar) == nil {
            Button(action: logWeight) { Label("Log weight", systemImage: "plus").font(ZoopType.font(size: 14, weight: .medium, relativeTo: .subheadline)) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).frame(minHeight: 44).accessibilityIdentifier("logWeight")
        }
    }
    private func periodButton(_ direction: Int) -> some View {
        Button { move(direction) } label: { Image(systemName: direction < 0 ? "chevron.left" : "chevron.right").font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .footnote)).frame(width: 44, height: 44) }
            .disabled(period.moved(range, by: direction, first: first, now: now) == nil)
            .accessibilityLabel(direction < 0 ? "Previous period" : "Next period")
            .accessibilityIdentifier(direction < 0 ? "weightPreviousPeriod" : "weightNextPeriod")
    }
    private var chart: some View {
        let isolated = Set(Dictionary(grouping: visible, by: \.segment).values.filter { $0.count == 1 }.compactMap { $0.first?.id })
        return Chart {
            if let target, let segment = targetSegment {
                RuleMark(xStart: .value("Cut start", segment.start), xEnd: .value("Cut finish", segment.end), y: .value("Target weight", display(target.kg)))
                    .foregroundStyle(ZoopStyle.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text(targetLabel).font(ZoopType.caption2).foregroundStyle(ZoopStyle.secondary).padding(.horizontal, 3).background(ZoopStyle.background)
                            .accessibilityIdentifier("weightChartTarget")
                    }
            }
            ForEach(visible) { point in
                LineMark(x: .value("Date", point.date), y: .value("Weight", display(point.kg)), series: .value("Series", "weight-\(point.segment)"))
                    .foregroundStyle(ZoopStyle.text).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                PointMark(x: .value("Date", point.date), y: .value("Weight", display(point.kg))).foregroundStyle(ZoopStyle.text).symbolSize(isolated.contains(point.id) ? 30 : 0)
            }
            if showAverage {
                ForEach(averages.filter { $0.date >= range.start && $0.date < range.end }) { point in
                    LineMark(x: .value("Date", point.date), y: .value("7-day average", display(point.average)), series: .value("Series", "average-\(point.segment)"))
                        .foregroundStyle(ZoopStyle.sleep).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
            }
            if let point = displayed {
                PointMark(x: .value("Date", point.date), y: .value("Weight", display(point.kg))).foregroundStyle(ZoopStyle.text.opacity(0.18)).symbolSize(170)
                PointMark(x: .value("Date", point.date), y: .value("Weight", display(point.kg))).foregroundStyle(ZoopStyle.text).symbolSize(65)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date)).foregroundStyle(ZoopStyle.secondary.opacity(0.6))
                PointMark(x: .value("Date", selected.date), y: .value("Weight", display(selected.kg))).foregroundStyle(ZoopStyle.text).symbolSize(80)
            }
        }.chartXScale(domain: plotDomain).chartXScale(range: .plotDimension(startPadding: 0, endPadding: 6)).chartYScale(domain: scale.range).chartLegend(.hidden).font(ZoopType.caption2)
        .chartXAxis {
            AxisMarks(values: ticks) { mark in
                AxisValueLabel(anchor: mark.index == 0 ? .topLeading : mark.index == ticks.count - 1 ? .topTrailing : .top) {
                    if let date = mark.as(Date.self) { Text(date, format: .dateTime.day().month(.abbreviated)).foregroundStyle(ZoopStyle.secondary) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [scale.range.lowerBound, (scale.range.lowerBound + scale.range.upperBound) / 2, scale.range.upperBound]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(ZoopStyle.chartGrid)
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))).foregroundStyle(ZoopStyle.secondary)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame {
                    let plot = geometry[plotFrame]
                    CalendarChartGesture(select: { location in
                        guard plot.contains(location), let date: Date = proxy.value(atX: location.x - plot.minX), !visible.isEmpty else { return }
                        let index = SortedWindow.lowerBound(points, value: date.timeIntervalSince1970) { $0.date.timeIntervalSince1970 }
                        let right = min(max(index, bounds.lowerBound), bounds.upperBound - 1), left = max(bounds.lowerBound, right - 1)
                        selectedID = abs(points[left].date.timeIntervalSince(date)) <= abs(points[right].date.timeIntervalSince(date)) ? points[left].id : points[right].id
                    }, page: move).accessibilityHidden(true)
                }
            }
        }
    }
    private func move(_ direction: Int) {
        guard let next = period.moved(range, by: direction, first: first, now: now) else { return }
        // Changing the date domain must not interpolate points across different periods.
        anchor = next.end.addingTimeInterval(-1); selectedID = nil
    }
    private func prepare() {
        let wasLatest = range == latestRange, firstLoad = points.isEmpty
        now = Date()
        let full = WeightCalendarPeriod.all.range(containing: now, first: readings.map(\.measuredAt).min() ?? now, last: now)
        points = WeightChartData(readings, range: full, now: now).points
        averages = WeightTrend(readings, through: now).points
        if wasLatest { anchor = now }
        if firstLoad, let last = points.last, last.date < latestRange.start { anchor = last.date }
        if anchor > now { anchor = now }
        selectedID = nil
    }
}
