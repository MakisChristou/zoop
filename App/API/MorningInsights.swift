import Foundation
import ZoopData

/// One server-calculated brief and the measurements behind it.
struct MorningInsights: Decodable, Sendable {
    struct Point: Decodable, Identifiable, Sendable {
        let day: String
        let value: Double?
        var id: String { day }
        var date: Date { DayKey.date(day) ?? .distantPast }
    }
    struct Baseline: Decodable, Sendable {
        let state: String
        let count: Int
        let from: String
        let to: String
        let average: Double?
        let lower: Double?
        let upper: Double?
        var label: String {
            switch state {
            case "early": "Early baseline · \(count) nights"
            case "established": "Based on \(count) nights"
            default: "Learning your baseline · \(count)/7 nights"
            }
        }
    }
    struct Week: Decodable, Sendable {
        let count: Int
        let average: Double?
        let previousAverage: Double?
    }
    struct Outlook: Decodable, Sendable {
        let state: String
        let level: Int?
        let baselineCount: Int
        let baselineRequired: Int
    }
    struct Comparison: Decodable, Sendable {
        let delta: Double
        let unit: String
        let signal: String?
        var formatted: String {
            let value = (unit == "seconds" ? delta / 60 : delta).rounded()
            guard value.isFinite else { return "—" }
            let prefix = value > 0 ? "+" : value < 0 ? "−" : ""
            let magnitude = abs(value)
            let number = magnitude.formatted(.number.precision(.fractionLength(0)))
            switch unit {
            case "seconds":
                if magnitude >= 60 {
                    let hours = floor(magnitude / 60).formatted(.number.precision(.fractionLength(0)))
                    let minutes = magnitude.truncatingRemainder(dividingBy: 60).formatted(.number.precision(.fractionLength(0)))
                    return "\(prefix)\(hours)h \(minutes)m"
                }
                return "\(prefix)\(number) min"
            case "percent": return "\(prefix)\(number)%"
            case "bpm": return "\(prefix)\(number) bpm"
            default: return "—"
            }
        }
    }
    struct Metric: Decodable, Identifiable, Sendable {
        let key: String
        let value: Double?
        let quality: String
        let baseline: Baseline
        let relation: String?
        let comparison: Comparison?
        var deltaText: String { comparison?.formatted ?? "—" }
        let history: [Point]
        let week: Week
        var id: String { key }
        var title: String {
            switch key { case "sleep": "Sleep"; case "hrv": "HRV"; default: "Resting heart rate" }
        }
        var unit: String { key == "sleep" ? "" : key == "hrv" ? "ms" : "bpm" }
        func formatted(_ value: Double?) -> String {
            guard let value else { return "—" }
            if key == "sleep" {
                let minutes = Int((value / 60).rounded())
                return "\(minutes / 60)h \(minutes % 60)m"
            }
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        var status: String {
            switch quality {
            case "limited": "Limited recording"
            case "missing": "No reading"
            case "updating": "Updating"
            case "awaiting_sync": "Waiting for a finished recording"
            case "no_sleep": "No sleep recorded"
            default:
                switch relation {
                case "higher": "Above your usual range"
                case "lower": "Below your usual range"
                case "similar": "Within your usual range"
                default: baseline.state == "early" ? "Early comparison" : "Learning your baseline"
                }
            }
        }
    }
    struct Timing: Decodable, Sendable {
        let count: Int
        let asleepSdMin: Double?
        let wakeSdMin: Double?
    }
    let outlook: Outlook?
    let recovery: RecoveryReading?
    let version: Int
    let day: String
    let timezone: String
    let state: String
    let sleepId: Int64?
    let sleepRevision: Int64?
    let metrics: [Metric]
    let observations: [String]
    let timing: Timing
    // Older servers remain readable, without inventing an assessment on the phone.
    private var outlookState: String { outlook?.state ?? (state == "ready" ? "learning" : state) }
    var isLearning: Bool { outlookState == "learning" }
    var outlookTitle: String {
        switch outlookState {
        case "good": "Good"
        case "average": "Average"
        case "low": "Low"
        case "mixed": "Mixed"
        case "learning": "Learning"
        case "limited": "Limited data"
        case "updating": "Updating"
        case "awaiting_sync": "Syncing"
        case "no_sleep": "No sleep"
        default: "Your morning"
        }
    }
    var outlookSubtitle: String {
        switch outlookState {
        case "good": outlook?.level == 5 ? "Clearly above your usual" : "Slightly above your usual"
        case "low": outlook?.level == 1 ? "Clearly below your usual" : "Slightly below your usual"
        case "average": "Close to your usual"
        case "mixed": "Readings point in different directions"
        case "learning":
            if let outlook {
                "\(outlook.baselineCount) of \(outlook.baselineRequired) nights · \(outlook.baselineCount >= 7 ? "Early baseline" : "Building your baseline")"
            } else { "Building your personal comparison" }
        case "limited": "Some readings need a fuller recording"
        case "updating": "Updating after your latest data"
        case "awaiting_sync": "Waiting for a finished sleep recording"
        case "no_sleep": "No main sleep recorded for this day"
        default: "Your personal comparisons"
        }
    }
    var outlookSymbol: String {
        switch outlookState {
        case "good": "arrow.up.right"
        case "low": "arrow.down.right"
        case "average": "minus"
        case "mixed": "arrow.up.arrow.down"
        case "learning": "circle.dashed"
        case "updating", "awaiting_sync": "arrow.triangle.2.circlepath"
        default: "minus"
        }
    }
    var comparisonCaption: String {
        guard state == "ready" else { return "View measurements" }
        return outlookState == "learning" ? "Early comparisons" : "Compared with your usual"
    }
    var status: String {
        switch state {
        case "updating": "Updating your morning"
        case "awaiting_sync": "Waiting for a finished sleep recording"
        case "no_sleep": "No main sleep recorded for this day"
        default: "Morning insights"
        }
    }
    var learningLabel: String? {
        guard state == "ready" else { return nil }
        if metrics.contains(where: { $0.quality == "good" && $0.baseline.state == "early" }) { return "Early baseline" }
        if metrics.allSatisfy({ $0.baseline.state == "learning" }) { return "Learning your baseline" }
        return nil
    }
}

extension ZoopAPI {
    static func morningInsights(deviceId: String, day: Date) async throws -> MorningInsights {
        let date = SleepSession.day(day, timezone: TimeZone.current.identifier)
        return try await get("v1/devices/\(deviceId)/days/\(date)/insights", query: ["tz": TimeZone.current.identifier])
    }
}
