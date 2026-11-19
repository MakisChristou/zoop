import Foundation

/// Counts the same eligible external samples the importer can store.
public struct WeightImportPreview: Sendable {
    public let toImport: Int
    public let alreadySaved: Int
    public let first: Date?
    public let last: Date?
    public var total: Int { toImport + alreadySaved }
    public init(readings: [WeightReading], savedIDs: Set<String>, range: HealthJournal.Range, now: Date = Date()) {
        let rows = Dictionary(grouping: readings.filter {
            $0.source == "health" && !$0.removed && $0.kg.isFinite && (20...400).contains($0.kg)
                && $0.measuredAt <= now && range.contains($0.measuredAt)
        }, by: \.id).compactMap { $0.value.first }
        alreadySaved = rows.filter { savedIDs.contains($0.id) }.count
        toImport = rows.count - alreadySaved
        first = rows.map(\.measuredAt).min()
        last = rows.map(\.measuredAt).max()
    }
}
