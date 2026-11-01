import Charts
import SwiftUI

struct InsightMetricView: View {
    let metric: MorningInsights.Metric
    @Environment(\.dynamicTypeSize) private var typeSize
    private var color: Color { metric.key == "resting_hr" ? SnoopStyle.heartRate : SnoopStyle.sleep }
    private func chartValue(_ value: Double) -> Double { metric.key == "sleep" ? value / 3600 : value }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(metric.title).font(.headline)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                MetricValue(metric.formatted(metric.value), size: 32)
                Text(metric.unit).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }.accessibilityElement(children: .combine)
            Text(metric.status).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            if let avg = metric.baseline.average {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout())
                layout {
                    Text("Recent average")
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Text("\(metric.formatted(avg)) \(metric.unit)").monospacedDigit()
                }.font(.subheadline)
            }
            if let lower = metric.baseline.lower, let upper = metric.baseline.upper {
                Text("Usual range: \(metric.formatted(lower))–\(metric.formatted(upper)) \(metric.unit)")
                    .font(.caption).foregroundStyle(SnoopStyle.secondary)
            }
            if metric.history.contains(where: { $0.value != nil }) {
                Chart {
                    if let average = metric.baseline.average {
                        RuleMark(y: .value("Recent average", chartValue(average)))
                            .foregroundStyle(SnoopStyle.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    ForEach(metric.history) { point in
                        if let value = point.value {
                            PointMark(x: .value("Date", point.date), y: .value(metric.unit.isEmpty ? "Hours" : metric.unit, chartValue(value)))
                                .foregroundStyle(color).symbolSize(point.day == metric.history.last?.day ? 55 : 24)
                                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                                .accessibilityValue("\(metric.formatted(value)) \(metric.unit)")
                        }
                    }
                }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(height: 110)
                .accessibilityLabel("\(metric.title) history")
            }
            Text(metric.baseline.label).font(.caption).foregroundStyle(SnoopStyle.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
    }
}
