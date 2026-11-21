import SwiftUI

/// A compact selector; the selected metric owns the single chart below.
struct InsightMetricView: View {
    let metric: MorningInsights.Metric
    let selected: Bool
    var reservesComparison = false
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 8) {
                Text(metric.key == "resting_hr" ? "Resting HR" : metric.title)
                    .font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary)
                Text(metric.formatted(metric.value) + (metric.value == nil || metric.unit.isEmpty ? "" : " " + metric.unit))
                    .font(ZoopType.font(size: 20, weight: .medium, relativeTo: .title3))
                    .monospacedDigit().foregroundStyle(ZoopStyle.text)
                    .fixedSize(horizontal: false, vertical: true)
                if reservesComparison {
                    Text(metric.visibleDelta ?? " ").font(ZoopType.caption).monospacedDigit()
                        .foregroundStyle(InsightTone.color(metric.comparison?.signal))
                        .accessibilityHidden(metric.visibleDelta == nil)
                }
                Capsule().fill(selected ? metric.trendMetric.color : .clear)
                    .frame(width: 36, height: 2).padding(.top, 4)
                    .accessibilityHidden(true)
            }.frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(metric.quality == "good" ? "Show trend" : metric.status + ". Show trend")
            .accessibilityIdentifier("insightMetric_\(metric.key)")
    }
}

extension MorningInsights.Metric {
    var trendMetric: TrendMetric { key == "sleep" ? .sleep : key == "hrv" ? .hrv : .restingHr }
    var visibleDelta: String? {
        guard let comparison, comparison.delta.isFinite else { return nil }
        let amount = comparison.unit == "seconds" ? comparison.delta / 60 : comparison.delta
        return amount.rounded() == 0 ? nil : comparison.formatted
    }
}
