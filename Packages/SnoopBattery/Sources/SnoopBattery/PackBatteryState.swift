import Foundation

/// Accessory charge is independent of the strap. Cached replies and historical
/// events can fill the last-known gauge, but only fresh live events may notify.
public struct PackBatteryState: Codable, Equatable {
    public enum Flow: String, Codable { case charging, discharging }
    public private(set) var battery = BatteryState()
    public private(set) var identifier: [UInt8] = []
    public private(set) var present: Bool?
    public private(set) var presenceAt: Date?
    public private(set) var liveLevelAt: Date?
    public private(set) var flow: Flow?
    private var cachedPercent: Double?
    private var cacheReceivedAt: Date?
    private var lastEventAt: Date?
    private var risingSteps = 0
    private var risingPoints = 0.0
    public var percent: Double? { battery.percent ?? cachedPercent }
    public var levelAt: Date? { battery.levelAt ?? cacheReceivedAt }
    public init() {}

    public func isLive(at now: Date) -> Bool {
        present == true && liveLevelAt != nil && liveLevelAt == battery.levelAt && battery.isFresh(at: now)
    }

    public mutating func disconnect(at now: Date) {
        present = nil
        presenceAt = max(presenceAt ?? .distantPast, now)
        liveLevelAt = nil
        flow = nil
        risingSteps = 0
        risingPoints = 0
        battery.invalidateCharging(at: now)
    }

    @discardableResult
    public mutating func receivePresence(_ present: Bool, at date: Date, now: Date, live: Bool) -> Bool {
        guard live, date <= now.addingTimeInterval(60), now.timeIntervalSince(date) <= BatteryState.freshness,
              presenceAt.map({ date > $0 }) ?? true else { return false }
        self.present = present
        presenceAt = date
        // A new attachment must earn a new live reading, even if it is the same pack.
        liveLevelAt = nil
        flow = nil
        risingSteps = 0
        risingPoints = 0
        battery.invalidateCharging(at: date)
        return true
    }

    @discardableResult
    public mutating func receive(percent: Double, identifier: [UInt8], at date: Date,
                                 now: Date, live: Bool, cached: Bool = false) -> Bool {
        guard percent.isFinite, (0...100).contains(percent), date <= now.addingTimeInterval(60) else { return false }
        if cached {
            // No measurement timestamp exists. Never overwrite an event with a cache.
            guard battery.percent == nil else { return false }
            self.identifier = identifier
            cachedPercent = percent
            cacheReceivedAt = date
            return true
        }
        guard lastEventAt.map({ date > $0 }) ?? true else { return false }
        let fresh = live && now.timeIntervalSince(date) <= BatteryState.freshness
            && (presenceAt.map({ present == true ? date >= $0 : date > $0 }) ?? true)
        // A historical record from a different pack must not replace the live pack.
        if self.identifier != identifier {
            guard fresh || liveLevelAt == nil else { return false }
            battery = BatteryState()
            cachedPercent = nil
            cacheReceivedAt = nil
            liveLevelAt = nil
            flow = nil
            risingSteps = 0
            risingPoints = 0
            self.identifier = identifier
        }
        let previous = isLive(at: date) ? battery.percent : nil
        guard battery.receive(percent: percent, at: date, now: now) else { return false }
        lastEventAt = date
        if fresh {
            present = true
            presenceAt = date
            liveLevelAt = date
            if let previous {
                let change = percent - previous
                if change <= -0.5 {
                    flow = .discharging
                    risingSteps = 0
                    risingPoints = 0
                } else if change >= 0.2 {
                    risingSteps += 1
                    risingPoints += change
                    // A depleted cell can rebound briefly when its load stops.
                    // Require two rising updates before showing pack charging.
                    if risingSteps >= 2, risingPoints >= 2 { flow = .charging }
                }
            } else {
                flow = nil
                risingSteps = 0
                risingPoints = 0
            }
            battery.receive(charging: flow == .charging, at: date, now: now)
        }
        return true
    }
}
