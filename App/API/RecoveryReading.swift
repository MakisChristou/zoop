import Foundation

/// The backend owns scoring, quality gates and display bands. Clients only present it.
struct RecoveryReading: Decodable, Sendable {
    struct Components: Decodable, Sendable {
        let hrv: Double
        let restingHr: Double
        let lastSleep: Double
        let recentSleep: Double
    }
    let version: Int
    let method: String
    let state: String
    let score: Int?
    let baselineCount: Int
    let recentCount: Int
    let referenceSeconds: Int
    let components: Components?
    let limiting: [String]
    let conflict: Bool
    let band: String?

    var displayedScore: Int? {
        guard version == 1, method == "zoop-recovery-v1", state == "ready",
              let score, (0...100).contains(score),
              ["low", "moderate", "high"].contains(band ?? "") else { return nil }
        return score
    }
    var value: String { displayedScore.map(String.init) ?? "—" }
    var progress: Double? { displayedScore.map { Double($0) / 100 } }
    var isWaitingForSync: Bool { state == "awaiting_sync" }
    var isCalculating: Bool { state == "updating" }
    var isPending: Bool { state == "updating" || state == "awaiting_sync" }
    var status: String {
        if displayedScore != nil {
            switch band { case "high": return "High"; case "moderate": return "Moderate"; case "low": return "Low"; default: return "Recovery" }
        }
        switch state {
        case "learning": return "Learning · \(baselineCount)/14 nights"
        case "updating": return "Updating"
        case "awaiting_sync": return "Waiting for sync"
        case "no_sleep": return "No sleep recorded"
        case "unusual_signals": return "Unusual readings"
        case "insufficient_recent_data": return "More recent nights needed"
        default: return "Not enough data"
        }
    }
    var limitingText: String? {
        guard displayedScore != nil else { return nil }
        let names = limiting.compactMap { key -> String? in
            switch key {
            case "hrv": return "HRV"
            case "resting_hr": return "Resting heart rate"
            case "last_sleep": return "Last night’s sleep"
            case "recent_sleep": return "Recent sleep"
            default: return nil
            }
        }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }
}
