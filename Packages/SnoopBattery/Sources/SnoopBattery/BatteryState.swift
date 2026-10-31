import Foundation

/// Timestamped observations, with explicitly identified inference from a rising trend.
public struct BatteryState: Codable, Equatable {
    public enum ChargingEvidence: String, Codable { case event, risingLevel }
    public private(set) var percent: Double?
    public private(set) var levelAt: Date?
    public private(set) var charging: Bool?
    public private(set) var chargingAt: Date?
    public private(set) var chargingEvidence: ChargingEvidence?
    private var trend: ChargingTrend?
    public static let freshness: TimeInterval = 15 * 60

    public init() {}

    /// A charger could have been removed while disconnected. Wait for a new event.
    public mutating func invalidateCharging(at date: Date) {
        charging = nil
        chargingEvidence = nil
        chargingAt = max(chargingAt ?? .distantPast, date)
    }

    public func chargingStatus(at now: Date) -> Bool? {
        guard chargingEvidence == .risingLevel else { return charging }
        guard let chargingAt, now.timeIntervalSince(chargingAt) <= ChargingTrend.window else { return nil }
        return charging
    }

    public func isFresh(at now: Date) -> Bool {
        guard let levelAt else { return false }
        return now.timeIntervalSince(levelAt) >= -60 && now.timeIntervalSince(levelAt) <= Self.freshness
    }

    /// Equal timestamps are replays. Reject invalid device clocks and impossible values.
    @discardableResult
    public mutating func receive(percent: Double, at date: Date, now: Date,
                                 live: Bool = false, source: BatteryReadingSource = .event) -> Bool {
        guard percent.isFinite, (0...100).contains(percent), date <= now.addingTimeInterval(60),
              levelAt.map({ date > $0 }) ?? true else { return false }
        self.percent = percent
        levelAt = date
        if live, isFresh(at: now) {
            var updated = trend ?? ChargingTrend()
            let rising = updated.receive(percent: percent, at: date, source: source)
            trend = updated
            if let rising, chargingEvidence != .event || (rising && charging == false) {
                charging = rising
                chargingAt = date
                chargingEvidence = .risingLevel
            }
        }
        return true
    }

    @discardableResult
    public mutating func receive(charging: Bool, at date: Date, now: Date) -> Bool {
        guard date <= now.addingTimeInterval(60), chargingAt.map({ date > $0 }) ?? true else { return false }
        self.charging = charging
        chargingAt = date
        chargingEvidence = .event
        trend = nil
        return true
    }
}
