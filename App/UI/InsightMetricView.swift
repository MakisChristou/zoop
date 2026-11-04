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
                    .font(.caption.weight(.medium)).foregroundStyle(SnoopStyle.secondary)
                Text(metric.formatted(metric.value) + (metric.unit.isEmpty ? "" : " " + metric.unit))
                    .font(.headline).monospacedDigit().foregroundStyle(SnoopStyle.text)
                if metric.quality != "good" { Text(metric.status).font(.caption).foregroundStyle(SnoopStyle.secondary) }
                Text(metric.visibleDelta ?? " ")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(InsightTone.color(metric.comparison?.signal))
                    .accessibilityHidden(metric.visibleDelta == nil)
            }.frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                .padding(12).background(SnoopStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).stroke(selected ? SnoopStyle.sleep : .clear, lineWidth: 1.5) }
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
