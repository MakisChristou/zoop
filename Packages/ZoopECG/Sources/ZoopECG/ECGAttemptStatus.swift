import Foundation

/// Narrow on-device diagnostics for a manual attempt; contains no waveform or identity.
public struct ECGAttemptStatus: Codable, Sendable {
    public let updatedAt: Date
    public let phase: String
    public let events: [String]
    public let frameCount: Int
    public let filteredSampleCount: Int
    public let cleanupPending: Bool
    public init(phase: String, events: [String], frameCount: Int, filteredSampleCount: Int, cleanupPending: Bool) {
        updatedAt = Date(); self.phase = phase; self.events = events
        self.frameCount = frameCount; self.filteredSampleCount = filteredSampleCount; self.cleanupPending = cleanupPending
    }
}
