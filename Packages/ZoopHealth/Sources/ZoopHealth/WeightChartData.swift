import Foundation

/// Actual, in-range observations only. No averages or estimated measurements.
public struct WeightChartData: Sendable {
    public enum Period: String, CaseIterable, Identifiable, Sendable {
        case week = "7D", month = "30D", quarter = "90D", all = "All"
        public var id: Self { self }
        public var days: Int? { switch self { case .week: 7; case .month: 30; case .quarter: 90; case .all: nil } }
        public func range(now: Date, first: Date? = nil, last: Date? = nil, calendar: Calendar = .current) -> DateInterval {
            let today = calendar.startOfDay(for: now)
            let start = days.flatMap { calendar.date(byAdding: .day, value: 1 - $0, to: today) }
                ?? calendar.startOfDay(for: min(first ?? now, now))
            let finalDay = self == .all ? calendar.startOfDay(for: min(last ?? now, now)) : today
            let end = calendar.date(byAdding: .day, value: 1, to: max(start, finalDay)) ?? now
            return DateInterval(start: start, end: end)
        }
    }
    public struct Point: Identifiable, Sendable {
        public let reading: WeightReading
        public let segment: Int
        public var id: String { reading.id }
        public var date: Date { reading.measuredAt }
        public var kg: Double { reading.kg }
    }
    public let range: DateInterval
    public let points: [Point]
    public init(_ rows: [WeightReading], range: DateInterval, now: Date = Date(), calendar: Calendar = .current) {
        self.range = range
        var unique: [String: WeightReading] = [:]
        for row in rows {
            if let old = unique[row.id], old.version > row.version { continue }
            unique[row.id] = row
        }
        let valid = unique.values.filter {
            !$0.removed && $0.kg.isFinite && (20...400).contains($0.kg) && $0.measuredAt <= now
                && $0.measuredAt >= range.start && $0.measuredAt < range.end
        }
        // Keep all visible Health readings. Zoop is the fallback on dates without
        // external measurements, matching the existing Health-first daily policy.
        let days = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.measuredAt) }
        var readings: [WeightReading] = []
        for group in days.values {
            let external = group.filter { $0.source == "health" }
            readings.append(contentsOf: external.isEmpty ? group : external)
        }
        readings.sort {
            if $0.measuredAt == $1.measuredAt { return $0.id < $1.id }
            return $0.measuredAt < $1.measuredAt
        }
        var segment = 0, result: [Point] = []
        for row in readings {
            if let previous = result.last,
               (calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.date), to: calendar.startOfDay(for: row.measuredAt)).day ?? 0) >= WeightTrend.windowDays {
                segment += 1
            }
            result.append(Point(reading: row, segment: segment))
        }
        points = result
    }
}
