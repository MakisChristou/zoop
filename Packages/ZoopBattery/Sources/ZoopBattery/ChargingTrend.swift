import Foundation

public enum BatteryReadingSource: String, Codable {
    case event, query
}

/// Compare each wire source separately: queries round down, events keep tenths.
struct ChargingTrend: Codable, Equatable {
    struct Reading: Codable, Equatable {
        let percent: Double
        let at: Date
    }
    private var events: [Reading] = []
    private var queries: [Reading] = []
    static let window: TimeInterval = 180

    mutating func receive(percent: Double, at: Date, source: BatteryReadingSource) -> Bool? {
        var readings = source == .event ? events : queries
        readings = readings.filter { at.timeIntervalSince($0.at) <= Self.window }
        var result: Bool?
        if let last = readings.last, percent < last.percent - 0.15 {
            // A falling level ends an inferred charge, but never overrides a charger event.
            result = false
            readings = []
        }
        readings.append(Reading(percent: percent, at: at))
        if let first = readings.first, readings.count >= 3,
           at.timeIntervalSince(first.at) >= 30, percent - first.percent >= 1 {
            let increases = zip(readings, readings.dropFirst()).filter { $1.percent > $0.percent + 0.05 }.count
            if increases >= 2 { result = true }
        }
        if source == .event { events = readings } else { queries = readings }
        return result
    }
}
