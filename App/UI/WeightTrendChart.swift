import Charts
import SwiftUI
import SnoopHealth

/// Recorded measurements, with native horizontal scrolling and tap selection.
struct WeightTrendChart: View {
    typealias Period = WeightChartData.Period
    private struct PlotPoint: Identifiable {
        let observation: WeightChartData.Point
        let x: Double
        var id: String { observation.id }
    }
    let readings: [WeightReading]
    let unit: String
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var period: Period = .month
    @State private var window = WeightChartWindow(first: Date(), last: Date())
    @State private var points: [PlotPoint] = []
    @State private var position = 0.0
    @State private var selectedX: Double?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 240

    private var range: DateInterval { window.range(position: position, days: period.days) }
    private var visible: [PlotPoint] {
        let interval = range
        return points.filter { $0.observation.date >= interval.start && $0.observation.date < interval.end }
    }
    private var selected: PlotPoint? {
        guard let selectedX else { return nil }
        return visible.min { abs($0.x - selectedX) < abs($1.x - selectedX) }
    }
    private var displayed: PlotPoint? { selected ?? visible.last }
    private var isLatest: Bool { period.days.map { abs(position - window.latestStart(days: $0)) < 0.5 } ?? true }
    private var canReturn: Bool { !isLatest || selected != nil }
    private var days: Int { period.days ?? window.historyEnd }
    private func display(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    private var rangeLabel: String {
        let last = window.calendar.date(byAdding: .day, value: -1, to: range.end)!
        let sameYear = window.calendar.component(.year, from: range.start) == window.calendar.component(.year, from: last)
        let start = range.start.formatted(sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year())
        return start + " – " + last.formatted(.dateTime.day().month(.abbreviated).year())
    }
    private var ticks: [Double] {
        let start = Int(window.coordinate(range.start).rounded())
        let offsets: [Int]
        if days <= 7 { offsets = Array(0..<days) }
        else if dynamicTypeSize.isAccessibilitySize { offsets = [0, (days - 1) / 2, days - 1] }
        else { offsets = [0, (days - 1) / 3, (days - 1) * 2 / 3, days - 1] }
        return Array(Set(offsets)).sorted().map { Double(start + $0) + 0.5 }
    }
    private var dateFormat: Date.FormatStyle {
        if days <= 7 { return .dateTime.weekday(.narrow) }
        return days > 366 ? .dateTime.month(.abbreviated).year() : .dateTime.day().month(.abbreviated)
    }
    private var scale: (range: ClosedRange<Double>, ticks: [Double]) {
        // An empty period has no headline value; retain a sensible axis around the
        // last actual observation instead of showing a misleading zero-weight scale.
        let values = (visible.isEmpty ? Array(points.suffix(1)) : visible).map { display($0.observation.kg) }
        let low = values.min() ?? 80, high = values.max() ?? low
        let span = max(high - low, unit == "lb" ? 4 : 2), target = span / 4
        let magnitude = pow(10, floor(log10(target)))
        let step = ([1.0, 2, 2.5, 5, 10].first { $0 >= target / magnitude } ?? 10) * magnitude
        let middle = (low + high) / 2
        let bottom = floor((middle - span * 0.6) / step) * step
        let top = ceil((middle + span * 0.6) / step) * step
        return (bottom...top, Array(stride(from: bottom, through: top + step * 0.01, by: step)))
    }
    private var selectionText: String {
        guard let reading = displayed?.observation.reading else { return "No weigh-ins in this period." }
        return "\(display(reading.kg).formatted(.number.precision(.fractionLength(1)))) \(unit), \(reading.measuredAt.formatted(date: .abbreviated, time: .shortened)), \(reading.sourceName)"
    }
    private var measurementDate: String {
        guard let date = displayed?.observation.date else { return "No weigh-ins" }
        let sameYear = window.calendar.component(.year, from: date) == window.calendar.component(.year, from: Date())
        let day = date.formatted(sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year())
        return day + " · " + date.formatted(date: .omitted, time: .shortened)
    }
    private var weightValue: some View {
        (Text(displayed.map { display($0.observation.kg).formatted(.number.precision(.fractionLength(1))) } ?? "—")
            .font(.largeTitle.weight(.semibold)) + Text(" \(unit)").font(.title3).foregroundColor(SnoopStyle.secondary))
            .monospacedDigit().accessibilityIdentifier("weightChartValue")
    }
    private var latestButton: some View {
        Button("Latest") { returnToLatest() }
            .font(.subheadline.weight(.medium)).buttonStyle(.bordered).buttonBorderShape(.capsule)
            .frame(minHeight: 44).opacity(canReturn ? 1 : 0)
            .disabled(!canReturn).accessibilityHidden(!canReturn).accessibilityIdentifier("weightChartLatest")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Chart range", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        weightValue.fixedSize()
                        Spacer(minLength: 8)
                        latestButton.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) { weightValue; latestButton }
                }
                Text(measurementDate)
                    .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    .accessibilityIdentifier("weightChartMeasurementDate")
            }
            VStack(alignment: .leading, spacing: 14) {
                // The range and reset control keep their space while browsing.
                Text(rangeLabel).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                    .accessibilityIdentifier("weightChartDates")
                navigableChart
                    .frame(height: min(chartHeight, 320))
                    // Axis labels stay compact; the headline, history list and
                    // VoiceOver measurement controls provide fully scalable values.
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .overlay {
                        if visible.isEmpty { Text("No weigh-ins in this period").font(.subheadline).foregroundStyle(SnoopStyle.secondary).allowsHitTesting(false) }
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel("Weight chart")
                    .accessibilityValue("\(rangeLabel). \(selectionText)")
                    .accessibilityHint("Swipe up or down to inspect measurements. Use the previous or next period actions to browse history.")
                    .accessibilityAdjustableAction { direction in
                        guard !visible.isEmpty else { return }
                        let current = selected.flatMap { point in visible.firstIndex { $0.id == point.id } } ?? visible.count - 1
                        let next = direction == .increment ? min(current + 1, visible.count - 1) : max(current - 1, 0)
                        selectedX = visible[next].x
                    }
                    .accessibilityAction(named: "Previous period") { movePeriod(-1) }
                    .accessibilityAction(named: "Next period") { movePeriod(1) }
                    .accessibilityScrollAction { edge in
                        if edge == .leading { movePeriod(-1) }
                        if edge == .trailing { movePeriod(1) }
                    }
            }
        }
        .onChange(of: readings, initial: true) { _, _ in reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in reload() }
        .onChange(of: period) { old, new in
            let end = window.range(position: position, days: old.days).end
            position = new.days.map { window.position(endingAt: end, days: $0) } ?? 0
            selectedX = nil
        }
        .onChange(of: position) { old, new in if abs(new - old) > 0.01 { selectedX = nil } }
    }
    @ViewBuilder private var navigableChart: some View {
        if let count = period.days {
            chart
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: count)
                .chartScrollPosition(x: $position)
                .chartScrollTargetBehavior(.valueAligned(unit: 1, majorAlignment: .page))
                .id(period)
        } else { chart }
    }
    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Day", point.x), y: .value("Weight", display(point.observation.kg)), series: .value("Segment", point.observation.segment))
                    .foregroundStyle(SnoopStyle.load).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                PointMark(x: .value("Day", point.x), y: .value("Weight", display(point.observation.kg)))
                    .foregroundStyle(SnoopStyle.load).symbolSize(days <= 30 ? 28 : 12)
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.x)).foregroundStyle(SnoopStyle.secondary.opacity(0.45))
                PointMark(x: .value("Day", selected.x), y: .value("Weight", display(selected.observation.kg)))
                    .foregroundStyle(SnoopStyle.load).symbolSize(80)
            }
        }
        .chartXScale(domain: window.domain(days: period.days)).chartYScale(domain: scale.range)
        .chartXSelection(value: $selectedX)
        .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { mark in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(SnoopStyle.separator)
                AxisValueLabel(anchor: mark.index == 0 ? .topLeading : mark.index == ticks.count - 1 ? .topTrailing : .top) {
                    if let day = mark.as(Double.self) {
                        Text(window.date(at: Int(floor(day))), format: dateFormat).foregroundStyle(SnoopStyle.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: scale.ticks) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(SnoopStyle.separator)
                AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))).foregroundStyle(SnoopStyle.secondary)
            }
        }
    }
    private func returnToLatest() {
        selectedX = nil
        if let count = period.days { position = window.latestStart(days: count) }
    }
    private func movePeriod(_ direction: Int) {
        guard let count = period.days else { return }
        selectedX = nil
        position = window.clamp(position + Double(direction * count), days: count)
    }
    private func reload() {
        let end = range.end, wasLatest = isLatest, firstLoad = points.isEmpty
        let now = Date()
        let fullRange = Period.all.range(now: now, first: readings.map(\.measuredAt).min(), last: now)
        let data = WeightChartData(readings, range: fullRange, now: now)
        window = WeightChartWindow(first: data.points.first?.date ?? now, last: data.points.last?.date ?? now, now: now)
        points = data.points.map { PlotPoint(observation: $0, x: window.coordinate($0.date)) }
        if firstLoad, let last = data.points.last, last.date < Period.month.range(now: now).start { period = .all }
        position = period.days.map { wasLatest ? window.latestStart(days: $0) : window.position(endingAt: end, days: $0) } ?? 0
        selectedX = nil
    }
}
