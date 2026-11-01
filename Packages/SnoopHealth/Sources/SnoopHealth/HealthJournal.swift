import Foundation

/// Every acknowledgement follows a durable external receipt. Never infer removals from absence.
public struct HealthJournal: Codable, Sendable {
    public struct Range: Codable, Equatable, Sendable {
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
    public var ranges: [Range] = []
    public var versions: [String: Int64] = [:]
    public var deferred: [String: HealthRecord] = [:]
    public var pendingWeights: [WeightReading] = []
    public var weights: [WeightReading] = []
    public var anchor: Data?
    public var importStart: Date?
    public var remindedDays: Set<String> = []
    public var lastSync: Date?
    public init() {}
    public func eligible(_ record: HealthRecord) -> Bool {
        if versions[record.id] != nil { return true }
        return connectedAt.map { record.eligibilityDate >= $0 } == true || ranges.contains { $0.contains(record.eligibilityDate) }
    }
    public mutating func backfill(_ range: Range) {
        if !ranges.contains(range) { ranges.append(range) }
        watermark = nil; pageCursor = 0; snapshot = true
    }
    public mutating func acknowledge(_ record: HealthRecord) {
        versions[record.id] = record.version; deferred.removeValue(forKey: record.id)
    }
}
