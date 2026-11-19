import Foundation
import ZoopProtocol

/// Receipt times describe the phone's capture window. They do not calibrate sample rate.
public struct ECGRecording: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let device: String
    public let firmware: String?
    public let wrist: ECGWrist
    public let startedAt: Date
    public let duration: TimeInterval
    public let frames: [ECGCapturedFrame]

    public init(id: UUID = UUID(), device: String, firmware: String?, wrist: ECGWrist,
                startedAt: Date, duration: TimeInterval, frames: [ECGCapturedFrame]) {
        self.id = id; self.device = device; self.firmware = firmware; self.wrist = wrist
        self.startedAt = startedAt; self.duration = duration; self.frames = frames
    }

    public var filteredSamples: [Int32] {
        frames.flatMap { item in
            guard let decoded = try? FrameDecoder.decode(Array(item.bytes)),
                  case let .ecg(strip) = decoded, strip.header.layout == .ecgFiltered else { return [Int32]() }
            return strip.samples
        }
    }

    public var summary: ECGRecordingSummary {
        .init(id: id, device: device, startedAt: startedAt, duration: duration, sampleCount: filteredSamples.count)
    }
}
