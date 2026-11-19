import Foundation

/// Calendar-day coordinates for the chart viewport, not measurement aggregation.
/// Every local date occupies one unit, including 23- and 25-hour DST dates.
public struct WeightChartWindow: Sendable {
    public let calendar: Calendar
    public let firstDay: Date
    public let todayEnd: Int
    public let historyEnd: Int

    public init(first: Date, last: Date, now: Date = Date(), calendar: Calendar = .current) {
        self.calendar = calendar
        firstDay = calendar.startOfDay(for: min(first, now))
        todayEnd = (calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: now)).day ?? 0) + 1
        historyEnd = (calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: max(firstDay, min(last, now)))).day ?? 0) + 1
    }
    public func coordinate(_ date: Date) -> Double {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day)!
        let index = calendar.dateComponents([.day], from: firstDay, to: day).day ?? 0
        return Double(index) + date.timeIntervalSince(day) / next.timeIntervalSince(day)
    }
    public func date(at day: Int) -> Date { calendar.date(byAdding: .day, value: day, to: firstDay)! }
    public func latestStart(days: Int) -> Double { Double(todayEnd - max(1, days)) }
    public func clamp(_ position: Double, days: Int) -> Double {
        let latest = latestStart(days: days)
        return min(latest, max(min(0, latest), position.isFinite ? position : latest))
    }
    public func domain(days: Int?) -> ClosedRange<Double> {
        guard let days else { return 0...Double(historyEnd) }
        return min(0, latestStart(days: days))...Double(todayEnd)
    }
    public func range(position: Double, days: Int?) -> DateInterval {
        guard let days else { return DateInterval(start: firstDay, end: date(at: historyEnd)) }
        let count = max(1, days)
        let start = Int(clamp(position, days: count).rounded())
        return DateInterval(start: date(at: start), end: date(at: start + count))
    }
    /// Keep the visible end date when changing window size or receiving new data.
    public func position(endingAt end: Date, days: Int) -> Double {
        clamp(Double(calendar.dateComponents([.day], from: firstDay, to: calendar.startOfDay(for: end)).day ?? todayEnd) - Double(days), days: days)
    }
}
