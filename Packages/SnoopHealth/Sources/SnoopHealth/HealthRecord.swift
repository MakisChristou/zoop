import Foundation

public struct HealthRecord: Codable, Equatable, Identifiable, Sendable {
    public struct Interval: Codable, Equatable, Sendable { public let start: Date; public let end: Date }
    public struct Payload: Codable, Equatable, Sendable {
        public let kind: String?
        public let intervals: [Interval]?
        public let count: Int?
        public let kg: Double?
    }
    public let id: String
    public let domain: String
    public let version: Int64
    public let sequence: Int64
    public let startTs: Date
    public let endTs: Date
    public let payload: Payload
    public let removed: Bool
    /// Steps belong to their measured minute, including the final minute before midnight.
    public var eligibilityDate: Date { domain == "steps" ? startTs : endTs }
}
