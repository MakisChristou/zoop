import Foundation

/// Exact validated bytes are kept, including unknown status and diagnostic fields.
public struct ECGCapturedFrame: Codable, Equatable, Sendable {
    public let bytes: Data
    public let receivedAt: Date
    /// Monotonic seconds since the first live frame in this attempt, including setup.
    public let elapsed: TimeInterval
    public init(bytes: Data, receivedAt: Date, elapsed: TimeInterval) {
        self.bytes = bytes; self.receivedAt = receivedAt; self.elapsed = elapsed
    }
}
