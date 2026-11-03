import Foundation

public struct ECGRecordingSummary: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let device: String
    public let startedAt: Date
    public let duration: TimeInterval
    public let sampleCount: Int
}
