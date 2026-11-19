import Foundation

public struct WeightReading: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var measuredAt: Date
    public var kg: Double
    public var source: String
    public var displaySourceName: String { source == "snoop" ? "Zoop" : sourceName }
    public var sourceName: String
    public var version: Int64
    public var removed: Bool
    public init(id: String = "snoop:" + UUID().uuidString, measuredAt: Date = Date(), kg: Double, source: String = "snoop", sourceName: String = "Zoop", version: Int64 = 0, removed: Bool = false) {
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
    /// Latest real measurement, with the same Health-first rule as the daily card.
    /// Import order, deleted rows and future dates do not replace the current value.
    public static func latest(_ rows: [Self], now: Date = Date(), calendar: Calendar = .current) -> Self? {
        let valid = rows.filter { !$0.removed && $0.measuredAt <= now && $0.kg.isFinite && (20...400).contains($0.kg) }
        guard let day = valid.map(\.measuredAt).max() else { return nil }
        return preferred(valid, on: day, calendar: calendar)
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
