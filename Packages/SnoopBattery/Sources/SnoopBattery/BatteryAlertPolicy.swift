import Foundation

/// Persisted per strap. Thresholds rearm only after charging five points above them.
public struct BatteryAlertPolicy: Codable, Equatable {
    public enum Alert: Equatable {
        case low(Int)
        case charged
    }

    public private(set) var warned: Set<Int> = []
    public private(set) var fullAlerted = false
    public private(set) var fullArmed = false
    public private(set) var lastEvaluatedAt: Date?
    public init() {}

    /// Only live, recent readings may notify. Historical replay is display-only.
    public mutating func evaluate(_ state: BatteryState, now: Date, live: Bool) -> Alert? {
        guard live, state.isFresh(at: now), let percent = state.percent, let at = state.levelAt,
              lastEvaluatedAt.map({ at > $0 }) ?? true else { return nil }
        lastEvaluatedAt = at
        if percent < 95 { fullArmed = true; fullAlerted = false }
        if percent < 100, !fullAlerted { fullArmed = true }
        // A higher level also rearms alerts when the charge happened out of range.
        warned = warned.filter { percent < Double($0 + 5) }
        if state.chargingStatus(at: now) == true {
            if percent < 100 { fullArmed = true }
        }
        if percent >= 100, fullArmed, !fullAlerted {
            fullAlerted = true
            fullArmed = false
            return .charged
        }
        guard state.chargingStatus(at: now) != true else { return nil }
        let reached = [5, 10, 20].filter { percent <= Double($0) }
        guard let threshold = reached.first, !warned.contains(threshold) else { return nil }
        warned.formUnion(reached)
        return .low(threshold)
    }
}
