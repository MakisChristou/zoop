import Foundation

/// Display-only averages of actual daily measurements. Missing days are never filled.
public struct WeightTrend: Sendable {
    public struct Point: Identifiable, Equatable, Sendable {
        public let reading: WeightReading
        public let day: Date
        public let average: Double
        public let segment: Int
        public var id: String { reading.id }
        public var date: Date { reading.measuredAt }
        public var kg: Double { reading.kg }
    }
    public static let windowDays = 7
    public let points: [Point]
    public init(_ rows: [WeightReading], through now: Date = Date(), calendar: Calendar = .current) {
        let valid = rows.filter { !$0.removed && $0.measuredAt <= now && $0.kg.isFinite && (20...400).contains($0.kg) }
        let groups = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.measuredAt) }
        let daily = groups.keys.sorted().compactMap { day in
            WeightReading.preferred(groups[day] ?? [], on: day, calendar: calendar)
        }
        var result: [Point] = []
        var first = 0, sum = 0.0, segment = 0
        for (index, reading) in daily.enumerated() {
            let day = calendar.startOfDay(for: reading.measuredAt)
            let cutoff = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: day) ?? day
            sum += reading.kg
            while first < index && daily[first].measuredAt < cutoff { sum -= daily[first].kg; first += 1 }
            if let previous = result.last, (calendar.dateComponents([.day], from: previous.day, to: day).day ?? 0) >= Self.windowDays { segment += 1 }
            result.append(Point(reading: reading, day: day, average: sum / Double(index - first + 1), segment: segment))
        }
        points = result
    }
    public func average(ending date: Date, calendar: Calendar = .current) -> Double? {
        let day = calendar.startOfDay(for: date)
        let start = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: day) ?? day
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? date
        let values = points.filter { $0.date >= start && $0.date < end }.map(\.kg)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
