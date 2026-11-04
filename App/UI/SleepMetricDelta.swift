import Foundation
import SnoopData

/// Presentation-only comparisons. Never treat missing measurements as zero.
struct SleepMetricDelta {
    let text: String
    let signal: String?
    let accessibility: String
    static let minimumNights = 7
    // Matches snoop-core insights quality: at most two unknown minutes.
    static let maximumUnknownSeconds = 120

    static func comparison(_ metric: MorningInsights.Metric?) -> Self? {
        guard let metric, metric.quality == "good", let text = metric.visibleDelta else { return nil }
        return Self(text: text, signal: metric.comparison?.signal, accessibility: "\(text) compared with your recent average")
    }

    static func efficiency(record: SnoopAPI.SleepSession, history: [SnoopAPI.SleepSession], baseline: MorningInsights.Baseline?, calendar: Calendar) -> Self? {
        guard record.isActive, !record.metricsPending, record.kind == "main", let current = record.sleep?.efficiency, current.isFinite, (0...1).contains(current),
              let window = record.sleep?.window, record.durationS > 0, record.durationS - window.coverageS <= maximumUnknownSeconds,
              let baseline, baseline.count >= minimumNights,
              let from = DayKey.date(baseline.from, timeZone: calendar.timeZone),
              let to = DayKey.date(baseline.to, timeZone: calendar.timeZone) else { return nil }
        // The API baseline end day is inclusive; interval bounds here are exclusive.
        let end = min(calendar.date(byAdding: .day, value: 1, to: to)!, calendar.startOfDay(for: record.endTs))
        let eligible = history.filter { row in
            guard row.id != record.id, row.isActive, !row.metricsPending, row.kind == "main", let sleep = row.sleep,
                  let value = sleep.efficiency, value.isFinite, (0...1).contains(value), row.durationS > 0 else { return false }
            let day = calendar.startOfDay(for: row.endTs)
            return day >= from && day < end && row.durationS - sleep.window.coverageS <= maximumUnknownSeconds
        }
        // A day contributes once, even if older and revised rows coexist briefly.
        let perDay = Dictionary(grouping: eligible) { calendar.startOfDay(for: $0.endTs) }
            .values.compactMap { $0.max { $0.revision < $1.revision }?.sleep?.efficiency }
        guard perDay.count >= minimumNights else { return nil }
        let delta = ((current - perDay.reduce(0, +) / Double(perDay.count)) * 100).rounded()
        guard delta != 0 else { return nil }
        let text = (delta > 0 ? "+" : "−") + abs(delta).formatted(.number.precision(.fractionLength(0))) + " pt"
        let unit = abs(delta) == 1 ? "percentage point" : "percentage points"
        return Self(text: text, signal: delta > 0 ? "favourable" : "unfavourable", accessibility: "\(abs(Int(delta))) \(unit) \(delta > 0 ? "above" : "below") your recent average")
    }
}
