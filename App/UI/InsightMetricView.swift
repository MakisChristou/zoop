import Charts
import SwiftUI

struct InsightMetricView: View {
    let metric: MorningInsights.Metric
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showComparison = false
    private var color: Color { metric.key == "resting_hr" ? SnoopStyle.heartRate : SnoopStyle.sleep }
    private func chartValue(_ value: Double) -> Double { metric.key == "sleep" ? value / 3600 : value }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let titleLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            titleLayout {
                Text(metric.title).font(.headline)
                if metric.comparison != nil {
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Text(metric.deltaText).font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(InsightTone.color(metric.comparison?.signal))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                MetricValue(metric.formatted(metric.value), size: 32)
                Text(metric.unit).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }.accessibilityElement(children: .combine)
            if metric.quality != "good" || metric.relation != nil {
                Text(metric.status).font(.subheadline).foregroundStyle(SnoopStyle.secondary)
            }
            if metric.history.contains(where: { $0.value != nil }) {
                Chart {
                    if showComparison, let average = metric.baseline.average {
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
            DisclosureGroup(isExpanded: $showComparison) {
                VStack(alignment: .leading, spacing: 8) {
                    if let avg = metric.baseline.average {
                        Text("Recent average: \(metric.formatted(avg)) \(metric.unit)").monospacedDigit()
                    }
                    if let lower = metric.baseline.lower, let upper = metric.baseline.upper {
                        Text("Usual range: \(metric.formatted(lower))–\(metric.formatted(upper)) \(metric.unit)")
                    }
                    Text(metric.baseline.label)
                }.font(.caption).foregroundStyle(SnoopStyle.secondary).padding(.top, 4)
            } label: {
                Text("Comparison details").font(.subheadline).frame(minHeight: 44)
            }.tint(SnoopStyle.secondary).accessibilityIdentifier("insightComparison_\(metric.key)")
        }.frame(maxWidth: .infinity, alignment: .leading).snoopCard()
    }
}
