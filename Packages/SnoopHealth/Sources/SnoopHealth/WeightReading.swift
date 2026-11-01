import Foundation

public struct WeightReading: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var measuredAt: Date
    public var kg: Double
    public var source: String
    public var sourceName: String
    public var version: Int64
    public var removed: Bool
    public init(id: String = "snoop:" + UUID().uuidString, measuredAt: Date = Date(), kg: Double, source: String = "snoop", sourceName: String = "Snoop", version: Int64 = 0, removed: Bool = false) {
        self.id = id; self.measuredAt = measuredAt; self.kg = kg; self.source = source; self.sourceName = sourceName; self.version = version; self.removed = removed
    }
    public static func preferred(_ rows: [Self], on day: Date, calendar: Calendar = .current) -> Self? {
        rows.filter { !$0.removed && calendar.isDate($0.measuredAt, inSameDayAs: day) }
            .sorted { a, b in
                if a.source != b.source { return a.source == "health" }
                if a.measuredAt == b.measuredAt { return a.id > b.id }
                return a.measuredAt > b.measuredAt
            }.first
    }
    /// One actual observation per date; never invent missing days or average duplicate sources.
    public static func trend(_ rows: [Self], ending day: Date, calendar: Calendar = .current) -> Double? {
        let values = (0..<7).compactMap { offset -> Double? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day) else { return nil }
            return preferred(rows, on: date, calendar: calendar)?.kg
        }
        return values.isEmpty ? nil : values.reduce(0,+) / Double(values.count)
    }
}
