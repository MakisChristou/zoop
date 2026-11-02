import Foundation

/// Every acknowledgement follows a durable external receipt. Never infer removals from absence.
public struct HealthJournal: Codable, Sendable {
    public struct Range: Codable, Hashable, Sendable {
        public let from: Date
        public let to: Date
        public init(from: Date, to: Date) { self.from = from; self.to = to }
        public func contains(_ end: Date) -> Bool { end >= from && end < to }
    }
    public var namespace = ""
    public var connectedAt: Date?
    public var paused = false
    public var exportSteps = false
    public var importWeight = false
    public var exportWeight = false
    public var remindWeight = true
    public var reminderEnabledAt = Date()
    public var cursor: Int64 = 0
    public var watermark: Int64?
    public var pageCursor: Int64 = 0
    public var snapshot = true
    /// Legacy selections consented to both directions. Retained when decoding old journals.
    public var ranges: [Range] = []
    // Optional fields preserve compatibility with journals written before separate flows.
    public var exportRanges: [Range]?
    public var weightImportRanges: [Range]?
    public var pendingWeightImport: Range?
    public var versions: [String: Int64] = [:]
    public var deferred: [String: HealthRecord] = [:]
    public var pendingWeights: [WeightReading] = []
    public var weights: [WeightReading] = []
    /// Optional for journals written before incremental server weight sync.
    public var weightCursor: Int64?
    public var anchor: Data?
    public var importStart: Date?
    public var remindedDays: Set<String> = []
    public var lastSync: Date?
    public init() {}
    public func eligible(_ record: HealthRecord) -> Bool {
        if versions[record.id] != nil { return true }
        return connectedAt.map { record.eligibilityDate >= $0 } == true || allExportRanges.contains { $0.contains(record.eligibilityDate) }
    }
    public mutating func backfill(_ range: Range) {
        var selected = exportRanges ?? []
        if !selected.contains(range) { selected.append(range) }
        exportRanges = selected
        watermark = nil; pageCursor = 0; snapshot = true
    }
    public var allExportRanges: [Range] { ranges + (exportRanges ?? []) }
    public func permitsWeightImport(at date: Date) -> Bool {
        connectedAt.map { date >= $0 } == true || (ranges + (weightImportRanges ?? [])).contains { $0.contains(date) }
    }
    public mutating func approveWeightImport(_ range: Range) {
        var selected = weightImportRanges ?? []
        if !selected.contains(range) { selected.append(range) }
        weightImportRanges = selected
        importStart = min(importStart ?? connectedAt ?? range.from, range.from)
        anchor = nil
        pendingWeightImport = range
    }
    public mutating func clearExportHistory() {
        weightImportRanges = Array(Set(ranges + (weightImportRanges ?? [])))
        ranges = []; exportRanges = []
    }
    public mutating func acknowledge(_ record: HealthRecord) {
        versions[record.id] = record.version; deferred.removeValue(forKey: record.id)
    }
}
