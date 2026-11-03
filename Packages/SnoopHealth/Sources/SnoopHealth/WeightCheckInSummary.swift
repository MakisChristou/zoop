import Foundation

/// Completion rewards recording, independent of the direction of weight change.
public struct WeightCheckInSummary: Sendable {
    public struct Day: Identifiable, Sendable {
        public let date: Date
        public let recorded: Bool
        public let isToday: Bool
        public var id: Date { date }
    }
    public let today: WeightReading?
    public let latest: WeightReading?
    public let days: [Day]
    public var count: Int { days.filter(\.recorded).count }
    public init(_ readings: [WeightReading], now: Date = Date(), calendar: Calendar = .current) {
        let valid = readings.filter { !$0.removed && $0.measuredAt <= now && $0.kg.isFinite && (20...400).contains($0.kg) }
        let grouped = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.measuredAt) }
        today = WeightReading.preferred(grouped[calendar.startOfDay(for: now)] ?? [], on: now, calendar: calendar)
        latest = grouped.keys.max().flatMap { WeightReading.preferred(grouped[$0] ?? [], on: $0, calendar: calendar) }
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        days = (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: week.start)!
            return Day(date: date, recorded: grouped[date]?.isEmpty == false, isToday: calendar.isDate(date, inSameDayAs: now))
        }
    }
}
