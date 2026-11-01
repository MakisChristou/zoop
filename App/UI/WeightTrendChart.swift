import Charts
import SwiftUI
import SnoopHealth

/// Displays recorded measurements without smoothing or summary statistics.
struct WeightTrendChart: View {
    let data: WeightChartData
    let unit: String
    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 210
    private func display(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    private var selected: WeightChartData.Point? {
        guard let selectedDate else { return nil }
        return data.points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
    private var displayed: WeightChartData.Point? { selected ?? data.points.last }
    private var days: Int { Calendar.current.dateComponents([.day], from: data.range.start, to: data.range.end).day ?? 1 }
    private var dates: [Date] {
        let cal = Calendar.current
        if days <= 7 { return (0..<days).compactMap { cal.date(byAdding: .day, value: $0, to: data.range.start) } }
        return [0, (days - 1) / 3, (days - 1) * 2 / 3, days - 1].compactMap { cal.date(byAdding: .day, value: $0, to: data.range.start) }
    }
    private var dateFormat: Date.FormatStyle {
        if days <= 7 { return .dateTime.weekday(.narrow) }
        return days > 366 ? .dateTime.month(.abbreviated).year() : .dateTime.day().month(.abbreviated)
    }
    private var rangeLabel: String {
        let last = Calendar.current.date(byAdding: .day, value: -1, to: data.range.end) ?? data.range.end
        return data.range.start.formatted(.dateTime.day().month(.abbreviated).year()) + " – " + last.formatted(.dateTime.day().month(.abbreviated).year())
    }
    private var scale: (range: ClosedRange<Double>, ticks: [Double]) {
        let values = data.points.map { display($0.kg) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let span = max(high - low, unit == "lb" ? 4 : 2)
        let target = span / 4
        let magnitude = pow(10, floor(log10(target)))
        let step = ([1.0, 2, 2.5, 5, 10].first { $0 >= target / magnitude } ?? 10) * magnitude
        let middle = (low + high) / 2
        let bottom = floor((middle - span * 0.6) / step) * step
        let top = ceil((middle + span * 0.6) / step) * step
        return (bottom...top, Array(stride(from: bottom, through: top + step * 0.01, by: step)))
    }
    private var selectionText: String {
        guard let displayed else { return "No weigh-ins in this range." }
        return "\(display(displayed.kg).formatted(.number.precision(.fractionLength(1)))) \(unit), \(displayed.date.formatted(date: .abbreviated, time: .shortened)), \(displayed.reading.sourceName)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(rangeLabel).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                .accessibilityIdentifier("weightChartDates")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selected == nil ? "Latest weigh-in" : "Weigh-in")
                        .font(.subheadline.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
                        .accessibilityIdentifier("weightChartMetric")
                    (Text(display(displayed?.kg ?? 0).formatted(.number.precision(.fractionLength(1))))
                        .font(.largeTitle.weight(.semibold)) + Text(" \(unit)").font(.title3).foregroundColor(SnoopStyle.secondary))
                        .monospacedDigit().accessibilityIdentifier("weightChartValue")
                    Text(displayed.map { "\($0.date.formatted(date: .abbreviated, time: .shortened)) · \($0.reading.sourceName)" } ?? "")
                        .font(.subheadline).foregroundStyle(SnoopStyle.secondary)
                }
                Spacer(minLength: 0)
                if selected != nil {
                    Button { selectedDate = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(SnoopStyle.secondary).frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel("Clear chart selection")
                }
            }
            Chart {
                ForEach(data.points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Weight", display(point.kg)), series: .value("Segment", point.segment))
                        .foregroundStyle(SnoopStyle.load).lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    PointMark(x: .value("Date", point.date), y: .value("Weight", display(point.kg)))
                        .foregroundStyle(SnoopStyle.load).symbolSize(days <= 30 ? 30 : 14)
                }
                if let selected {
                    RuleMark(x: .value("Selected", selected.date)).foregroundStyle(SnoopStyle.secondary.opacity(0.55))
                    PointMark(x: .value("Date", selected.date), y: .value("Weight", display(selected.kg)))
                        .foregroundStyle(SnoopStyle.load).symbolSize(80)
                }
            }
            .chartXScale(domain: data.range.start...data.range.end).chartYScale(domain: scale.range)
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) } }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: dates) { mark in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3])).foregroundStyle(SnoopStyle.separator)
                    AxisValueLabel(format: dateFormat, anchor: mark.index == dates.count - 1 ? .topTrailing : .topLeading)
                        .foregroundStyle(SnoopStyle.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: scale.ticks) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(SnoopStyle.separator)
                    AxisValueLabel(format: FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))).foregroundStyle(SnoopStyle.secondary)
                }
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore).accessibilityLabel("Weight chart")
            .accessibilityValue(selectionText).accessibilityHint("Swipe up or down to inspect measurements")
            .accessibilityAdjustableAction { direction in
                guard !data.points.isEmpty else { return }
                let current = selected.flatMap { point in data.points.firstIndex { $0.id == point.id } } ?? data.points.count - 1
                let next = direction == .increment ? min(current + 1, data.points.count - 1) : max(current - 1, 0)
                selectedDate = data.points[next].date
            }
            Text("Tap the chart to see a weigh-in").font(.caption).foregroundStyle(SnoopStyle.secondary)
        }
        .onChange(of: data.range) { _, _ in selectedDate = nil }
        .onChange(of: data.points.map(\.id)) { _, _ in selectedDate = nil }
    }
}
