import Charts
import SwiftUI
import SnoopHealth

struct WeightTrendChart: View {
    let points: [WeightTrend.Point]
    let readings: [WeightReading]
    let range: ClosedRange<Date>
    let unit: String
    @State private var selectedDate: Date?
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 190
    private func display(_ kg: Double) -> Double { unit == "lb" ? kg * 2.2046226218 : kg }
    private var ordered: [WeightReading] { readings.sorted { $0.measuredAt < $1.measuredAt } }
    private var selected: WeightReading? {
        guard let selectedDate else { return nil }
        return readings.min { abs($0.measuredAt.timeIntervalSince(selectedDate)) < abs($1.measuredAt.timeIntervalSince(selectedDate)) }
    }
    private var yRange: ClosedRange<Double> {
        let values = readings.map { display($0.kg) } + points.map { display($0.average) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = max((high - low) * 0.25, unit == "lb" ? 1 : 0.5)
        return (low - padding)...(high + padding)
    }
    private var dateFormat: Date.FormatStyle {
        range.upperBound.timeIntervalSince(range.lowerBound) > 366 * 24 * 3600
            ? .dateTime.month(.abbreviated).year() : .dateTime.day().month(.abbreviated)
    }
    private var selectionText: String {
        guard let selected else { return "\(readings.count) measurements. Seven-day average shown as a line." }
        return "\(display(selected.kg).formatted(.number.precision(.fractionLength(1)))) \(unit), \(selected.measuredAt.formatted(date: .abbreviated, time: .shortened)), \(selected.sourceName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if let selected {
                    Text("\(display(selected.kg).formatted(.number.precision(.fractionLength(1)))) \(unit)")
                        .font(.headline).monospacedDigit()
                    Text("\(selected.measuredAt.formatted(date: .abbreviated, time: .shortened)) · \(selected.sourceName)")
                        .font(.caption).foregroundStyle(SnoopStyle.secondary)
                } else {
                    Text("Your weight over time").font(.headline)
                    Text("Touch the chart to see a weigh-in").font(.caption).foregroundStyle(SnoopStyle.secondary)
                }
            }.frame(minHeight: 42, alignment: .topLeading)
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("7-day average", display(point.average)), series: .value("Segment", point.segment))
                        .foregroundStyle(SnoopStyle.load).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
                ForEach(readings) { row in
                    PointMark(x: .value("Date", row.measuredAt), y: .value("Weight", display(row.kg)))
                        .foregroundStyle(SnoopStyle.secondary.opacity(0.65)).symbolSize(24)
                }
                if let selected {
                    RuleMark(x: .value("Selected", selected.measuredAt))
                        .foregroundStyle(SnoopStyle.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3]))
                    PointMark(x: .value("Date", selected.measuredAt), y: .value("Weight", display(selected.kg)))
                        .foregroundStyle(SnoopStyle.load).symbolSize(65)
                }
            }
            .chartXScale(domain: range).chartYScale(domain: yRange)
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { proxy.selectXValue(at: $0.location.x) }
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel(format: dateFormat)
                        .foregroundStyle(SnoopStyle.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(SnoopStyle.separator)
                    AxisValueLabel().foregroundStyle(SnoopStyle.secondary)
                }
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore).accessibilityLabel("Weight chart")
            .accessibilityValue(selectionText).accessibilityHint("Swipe up or down to inspect measurements")
            .accessibilityAdjustableAction { direction in
                let rows = ordered
                guard !rows.isEmpty else { return }
                let current = selected.flatMap { row in rows.firstIndex { $0.id == row.id } } ?? rows.count - 1
                let next = direction == .increment ? min(current + 1, rows.count - 1) : max(current - 1, 0)
                selectedDate = rows[next].measuredAt
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { averageLegend; readingLegend }
                VStack(alignment: .leading, spacing: 8) { averageLegend; readingLegend }
            }.font(.caption).foregroundStyle(SnoopStyle.secondary)
        }
        .onChange(of: range) { _, _ in selectedDate = nil }
    }
    private var averageLegend: some View {
        HStack(spacing: 6) { Capsule().fill(SnoopStyle.load).frame(width: 16, height: 3); Text("7-day average") }
    }
    private var readingLegend: some View {
        HStack(spacing: 6) { Circle().fill(SnoopStyle.secondary.opacity(0.65)).frame(width: 6, height: 6); Text("Weigh-ins") }
    }
}
