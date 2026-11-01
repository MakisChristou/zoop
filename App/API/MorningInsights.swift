import Foundation

/// One server-calculated brief and the measurements behind it.
struct MorningInsights: Decodable {
    struct Point: Decodable, Identifiable {
        let day: String
        let value: Double?
        var id: String { day }
        var date: Date { StepsView.day(day) ?? .distantPast }
    }
    struct Baseline: Decodable {
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
    struct Week: Decodable {
        let count: Int
        let average: Double?
        let previousAverage: Double?
    }
    struct Metric: Decodable, Identifiable {
        let key: String
        let value: Double?
        let quality: String
        let baseline: Baseline
        let relation: String?
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
    struct Timing: Decodable {
        let count: Int
        let asleepSdMin: Double?
        let wakeSdMin: Double?
    }
    let version: Int
    let day: String
    let timezone: String
    let state: String
    let sleepId: Int64?
    let sleepRevision: Int64?
    let metrics: [Metric]
    let observations: [String]
    let timing: Timing
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

extension SnoopAPI {
    static func morningInsights(deviceId: String, day: Date) async throws -> MorningInsights {
        let date = SleepSession.day(day, timezone: TimeZone.current.identifier)
        return try await get("v1/devices/\(deviceId)/days/\(date)/insights", query: ["tz": TimeZone.current.identifier])
    }
}
