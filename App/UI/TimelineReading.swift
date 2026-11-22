import Foundation

/// A freshness change changes the label, never the source of an existing reading.
struct TimelineReading: Equatable {
    private static let liveFreshness: TimeInterval = 5
    let value: Double?
    let date: Date?
    let isLive: Bool

    static func resolve(value: Double?, date: Date?, wantsLive: Bool,
                        sensorValue: UInt8?, sensorDate: Date?, streaming: Bool,
                        now: Date = .now, calendar: Calendar = .current) -> Self {
        if wantsLive, let sensorValue, let sensorDate,
           sensorDate <= now, calendar.isDate(sensorDate, inSameDayAs: now) {
            let fresh = streaming && now.timeIntervalSince(sensorDate) < liveFreshness
            if !fresh, let date, date > sensorDate {
                return .init(value: value, date: date, isLive: false)
            }
            return .init(value: Double(sensorValue), date: sensorDate,
                         isLive: fresh)
        }
        return .init(value: value, date: date, isLive: false)
    }
}
