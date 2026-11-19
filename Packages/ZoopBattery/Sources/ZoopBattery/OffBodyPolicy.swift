import Foundation

/// Event-driven wear episodes. No inference from heart rate, rest/motion, or link loss.
public struct OffBodyPolicy: Equatable {
    public static let delay: TimeInterval = 10 * 60
    public static let freshness: TimeInterval = 60
    public private(set) var removedAt: Date?
    public private(set) var latestEvent: Date?
    public init() {}
    public var deadline: Date? { removedAt?.addingTimeInterval(Self.delay) }
    @discardableResult public mutating func receive(worn: Bool, at date: Date, now: Date, live: Bool) -> Bool {
        guard live, date <= now.addingTimeInterval(5), now.timeIntervalSince(date) <= Self.freshness,
              latestEvent.map({ date > $0 }) ?? true else { return false }
        latestEvent = date
        if worn { removedAt = nil }
        else if removedAt == nil { removedAt = now }
        return true
    }
    /// A restart/disconnect loses continuity. A fresh removal event must start again.
    public mutating func invalidate() { removedAt = nil; latestEvent = nil }
}
