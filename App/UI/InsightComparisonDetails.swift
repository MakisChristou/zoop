import SwiftUI

/// Existing baseline and weekly evidence, kept behind the chart's one disclosure.
struct InsightComparisonDetails: View {
    let insights: MorningInsights
    let metric: TrendMetric
    var body: some View {
        if let reading = insights.metrics.first(where: { $0.trendMetric == metric }) {
            VStack(alignment: .leading, spacing: 8) {
                if let average = reading.baseline.average { Text("Recent average: \(reading.formatted(average)) \(reading.unit)") }
                if let lower = reading.baseline.lower, let upper = reading.baseline.upper {
                    Text("Usual range: \(reading.formatted(lower))–\(reading.formatted(upper)) \(reading.unit)")
                }
                Text(reading.baseline.label)
                if let average = reading.week.average {
                    Text("Past 7 days: \(reading.formatted(average)) \(reading.unit) · \(reading.week.count) nights")
                    if let previous = reading.week.previousAverage { Text("Previous week: \(reading.formatted(previous)) \(reading.unit)") }
                }
                if metric == .sleep, let asleep = insights.timing.asleepSdMin, let wake = insights.timing.wakeSdMin {
                    Text("Sleep timing").fontWeight(.semibold)
                    Text("Falling asleep varied by about \(Int(asleep.rounded())) min; waking up by \(Int(wake.rounded())) min.")
                }
            }.font(.caption).foregroundStyle(SnoopStyle.secondary).monospacedDigit()
        }
    }
}
