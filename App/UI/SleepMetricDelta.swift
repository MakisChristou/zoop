import Foundation
import SnoopData

/// Presentation-only comparisons. Never treat missing measurements as zero.
struct SleepMetricDelta {
    let text: String
    let signal: String?
    let accessibility: String
    static let minimumNights = 7
    static let lookbackDays = 28
    // Matches snoop-core insights quality: at most two unknown minutes.
    static let maximumUnknownSeconds = 120

    enum Metric: CaseIterable {
        case efficiency, awake, breathing, oxygen, temperature

        func value(_ sleep: SnoopAPI.SleepSession.Payload) -> Double? {
            let value: Double?
            switch self {
            case .efficiency: value = sleep.efficiency
            case .awake: value = Double(sleep.window.wasoS)
            case .breathing: value = sleep.physiology.respiratoryRate
            case .oxygen: value = sleep.physiology.spo2Windows > 0 ? sleep.physiology.spo2Pct : nil
            case .temperature: value = sleep.physiology.skinTempC
            }
            guard let value, value.isFinite else { return nil }
            switch self {
            case .efficiency: return (0...1).contains(value) ? value : nil
            case .awake: return value >= 0 ? value : nil
            case .oxygen: return value > 0 && value <= 100 ? value : nil
            case .breathing: return value > 0 ? value : nil
            case .temperature: return value
            }
        }

        func signal(for delta: Double) -> String? {
            guard delta != 0 else { return nil }
            switch self {
            case .efficiency: return delta > 0 ? "favourable" : "unfavourable"
            case .awake: return delta < 0 ? "favourable" : "unfavourable"
            // Direction alone does not establish whether these vitals are better.
            case .breathing, .oxygen, .temperature: return nil
            }
        }
    }

    static func comparison(_ metric: MorningInsights.Metric?) -> Self? {
        guard let metric, metric.quality == "good", let comparison = metric.comparison,
              comparison.delta.isFinite, let text = metric.visibleDelta else { return nil }
        // Badge colour describes the signed change, not the outlook's wider range.
        let delta = comparison.delta.rounded()
        let signal: String?
        if delta == 0 { signal = nil }
        else if metric.key == "resting_hr" { signal = delta > 0 ? "unfavourable" : "favourable" }
        else if metric.key == "hrv" { signal = delta > 0 ? "favourable" : "unfavourable" }
        else { signal = comparison.signal }
        return Self(text: text, signal: signal, accessibility: "\(text) compared with your recent average")
    }

    static func efficiency(record: SnoopAPI.SleepSession, history: [SnoopAPI.SleepSession], baseline: MorningInsights.Baseline?, calendar: Calendar) -> Self? {
        nightly(.efficiency, record: record, history: history, baseline: baseline, calendar: calendar)
    }

    static func nightly(_ metric: Metric, record: SnoopAPI.SleepSession, history: [SnoopAPI.SleepSession], baseline: MorningInsights.Baseline?, calendar: Calendar) -> Self? {
        guard eligible(record), let sleep = record.sleep, let current = metric.value(sleep) else { return nil }
        let selectedDay = calendar.startOfDay(for: record.endTs)
        let from: Date
        let end: Date
        if let baseline {
            guard let start = DayKey.date(baseline.from, timeZone: calendar.timeZone),
                  let last = DayKey.date(baseline.to, timeZone: calendar.timeZone),
                  let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: last) else { return nil }
            from = start
            end = min(exclusiveEnd, selectedDay)
        } else {
            guard let start = calendar.date(byAdding: .day, value: -lookbackDays, to: selectedDay) else { return nil }
            from = start
            end = selectedDay
        }
        let prior = history.filter { row in
            let day = calendar.startOfDay(for: row.endTs)
            return row.id != record.id && row.kind == "main" && day >= from && day < end
        }
        // Select revisions before checking quality, so stale valid data cannot win.
        let values = Dictionary(grouping: prior) { calendar.startOfDay(for: $0.endTs) }.values.compactMap { rows -> Double? in
            guard let latest = rows.max(by: { $0.revision == $1.revision ? $0.id < $1.id : $0.revision < $1.revision }),
                  eligible(latest), let payload = latest.sleep else { return nil }
            return metric.value(payload)
        }
        guard values.count >= minimumNights else { return nil }
        let average = values.reduce(0, +) / Double(values.count)
        let raw: Double
        if metric == .temperature { raw = current - average }
        else {
            guard average > 0 else { return nil }
            raw = (current - average) / average * 100
        }
        guard raw.isFinite else { return nil }
        let delta = (raw * 10).rounded() / 10
        let suffix = metric == .temperature ? " °C" : "%"
        let text = (delta > 0 ? "+" : delta < 0 ? "−" : "") + abs(delta).formatted(.number.precision(.fractionLength(0...1))) + suffix
        return Self(text: text, signal: metric.signal(for: delta), accessibility: "\(text) compared with your average of \(values.count) previous nights")
    }

    private static func eligible(_ record: SnoopAPI.SleepSession) -> Bool {
        guard record.isActive, !record.metricsPending, record.kind == "main", record.durationS > 0,
              let sleep = record.sleep, sleep.window.coverageS > 0 else { return false }
        return max(record.durationS - sleep.window.coverageS, sleep.unknownS ?? 0) <= maximumUnknownSeconds
    }
}
