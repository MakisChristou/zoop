import Foundation

/// One comparison snapshot for the displayed night, independent of insight requests.
struct SleepMetricDelta {
    let text: String
    let signal: String?
    let accessibility: String
    static let minimumNights = 7
    static let lookbackDays = 28
    static let maximumUnknownSeconds = 120

    enum Metric: CaseIterable, Hashable {
        case asleep, efficiency, awake, restingHR, hrv, breathing, oxygen, temperature, disturbances
        case rem, deep, light

        func value(_ sleep: ZoopAPI.SleepSession.Payload) -> Double? {
            let value: Double?
            switch self {
            case .asleep: value = Double(sleep.window.asleepS)
            case .efficiency: value = sleep.efficiency
            case .awake: value = Double(sleep.window.wasoS)
            case .restingHR: value = sleep.physiology.restingHr
            case .hrv: value = sleep.physiology.hrvWindows > 0 ? sleep.physiology.hrvRmssdMs : nil
            case .breathing: value = sleep.physiology.respiratoryRate
            case .oxygen: value = sleep.physiology.spo2Windows > 0 ? sleep.physiology.spo2Pct : nil
            case .temperature: value = sleep.physiology.skinTempC
            case .disturbances: value = Double(sleep.window.disturbances)
            case .rem: value = sleep.stages.map { Double($0.remS) }
            case .deep: value = sleep.stages.map { Double($0.deepS) }
            case .light: value = sleep.stages.map { Double($0.lightS) }
            }
            guard let value, value.isFinite else { return nil }
            switch self {
            case .efficiency: return (0...1).contains(value) ? value : nil
            case .oxygen: return value > 0 && value <= 100 ? value : nil
            case .restingHR, .hrv, .breathing: return value > 0 ? value : nil
            case .temperature: return value
            default: return value >= 0 ? value : nil
            }
        }

        func signal(for delta: Double) -> String? {
            guard delta != 0 else { return nil }
            switch self {
            case .efficiency, .hrv: return delta > 0 ? "favourable" : "unfavourable"
            case .awake, .restingHR, .disturbances: return delta < 0 ? "favourable" : "unfavourable"
            // More sleep, or a higher vital/stage value, is not always better.
            default: return nil
            }
        }
    }

    static func nightly(_ metric: Metric, record: ZoopAPI.SleepSession, history: [ZoopAPI.SleepSession], calendar: Calendar) -> Self? {
        all(record: record, history: history, calendar: calendar)[metric]
    }

    /// Dedupe and quality-filter history once, then calculate all badges together.
    static func all(record: ZoopAPI.SleepSession, history: [ZoopAPI.SleepSession], calendar: Calendar) -> [Metric: Self] {
        guard eligible(record), let sleep = record.sleep else { return [:] }
        let end = calendar.startOfDay(for: record.endTs)
        guard let from = calendar.date(byAdding: .day, value: -lookbackDays, to: end) else { return [:] }
        let prior = history.filter { row in
            let day = calendar.startOfDay(for: row.endTs)
            return row.id != record.id && row.kind == "main" && day >= from && day < end
        }
        // Select revisions before checking quality; never revive stale valid data.
        let nights = Dictionary(grouping: prior) { calendar.startOfDay(for: $0.endTs) }.values.compactMap { rows -> ZoopAPI.SleepSession.Payload? in
            guard let latest = rows.max(by: { $0.revision == $1.revision ? $0.id < $1.id : $0.revision < $1.revision }),
                  eligible(latest) else { return nil }
            return latest.sleep
        }
        var result: [Metric: Self] = [:]
        for metric in Metric.allCases {
            guard let current = metric.value(sleep) else { continue }
            let values = nights.compactMap { metric.value($0) }
            guard values.count >= minimumNights else { continue }
            let average = values.reduce(0, +) / Double(values.count)
            let raw: Double
            let suffix: String
            switch metric {
            case .temperature: raw = current - average; suffix = " °C"
            case .restingHR: raw = current - average; suffix = " bpm"
            default:
                // Equal zero baselines are comparable; positive-over-zero is not a percentage.
                if average == 0 && current == 0 { raw = 0 }
                else if average > 0 { raw = (current - average) / average * 100 }
                else { continue }
                suffix = "%"
            }
            guard raw.isFinite else { continue }
            let delta = (raw * 10).rounded() / 10
            let text = (delta > 0 ? "+" : delta < 0 ? "−" : "") + abs(delta).formatted(.number.precision(.fractionLength(0...1))) + suffix
            result[metric] = Self(text: text, signal: metric.signal(for: delta), accessibility: "\(text) compared with your average of \(values.count) previous nights")
        }
        return result
    }

    private static func eligible(_ record: ZoopAPI.SleepSession) -> Bool {
        guard record.isActive, !record.metricsPending, record.kind == "main", record.durationS > 0,
              let sleep = record.sleep, sleep.window.coverageS > 0 else { return false }
        return max(record.durationS - sleep.window.coverageS, sleep.unknownS ?? 0) <= maximumUnknownSeconds
    }
}
