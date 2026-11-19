import SwiftUI

/// A compact selector; the selected metric owns the single chart below.
struct InsightMetricView: View {
    let metric: MorningInsights.Metric
    let selected: Bool
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                Text(metric.key == "resting_hr" ? "Resting HR" : metric.title)
                    .font(ZoopType.font(size: 12, weight: .medium, relativeTo: .caption)).foregroundStyle(ZoopStyle.secondary)
                Text(metric.formatted(metric.value) + (metric.unit.isEmpty ? "" : " " + metric.unit))
                    .font(ZoopType.headline).monospacedDigit().foregroundStyle(ZoopStyle.text)
                if metric.quality != "good" { Text(metric.status).font(ZoopType.caption).foregroundStyle(ZoopStyle.secondary) }
                Text(metric.visibleDelta ?? " ")
                    .font(ZoopType.font(size: 12, weight: .semibold, relativeTo: .caption)).monospacedDigit()
                    .foregroundStyle(InsightTone.color(metric.comparison?.signal))
                    .accessibilityHidden(metric.visibleDelta == nil)
            }.frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .padding(.vertical, 12)
                .overlay(alignment: .bottom) { Rectangle().fill(selected ? ZoopStyle.text : ZoopStyle.separator).frame(height: selected ? 2 : 0.5) }
        }.buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
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
