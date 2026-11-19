import Foundation
import ZoopProtocol

/// Captures only current, validated live ECG; unrelated history never advances time.
public struct ECGBuffer {
    public static let duration: TimeInterval = 30
    public static let maximumGap: TimeInterval = 5
    public static let maximumBytes = 8 * 1024 * 1024
    public private(set) var frames: [ECGCapturedFrame] = []
    public private(set) var filteredSamples: [Int32] = []
    public private(set) var firstSampleUptime: TimeInterval?
    public private(set) var firstSampleDate: Date?
    public private(set) var lastSampleUptime: TimeInterval?
    private var seen: Set<Data> = []
    private var bytes = 0
    private var firstFrameUptime: TimeInterval?
    public init() {}

    @discardableResult
    public mutating func receive(_ data: Data, at: Date, uptime: TimeInterval) throws -> Bool {
        let raw = Array(data)
        let decoded = try FrameDecoder.decode(raw)
        guard raw[8] == PacketType.realtimeRawDataByte, case let .ecg(strip) = decoded,
              !seen.contains(data) else { return false }
        guard bytes + data.count <= Self.maximumBytes else { throw CaptureError.capacity }
        seen.insert(data); bytes += data.count
        if firstFrameUptime == nil { firstFrameUptime = uptime }
        if strip.header.layout == .ecgFiltered, !strip.samples.isEmpty {
            if let lastSampleUptime, uptime - lastSampleUptime > Self.maximumGap { throw CaptureError.gap }
            if firstSampleUptime == nil { firstSampleUptime = uptime; firstSampleDate = at }
            lastSampleUptime = uptime
            filteredSamples.append(contentsOf: strip.samples)
        }
        frames.append(.init(bytes: data, receivedAt: at, elapsed: firstFrameUptime.map { uptime - $0 } ?? 0))
        return true
    }

    public func elapsed(at uptime: TimeInterval) -> TimeInterval {
        firstSampleUptime.map { max(0, uptime - $0) } ?? 0
    }
    public func isStale(at uptime: TimeInterval) -> Bool {
        lastSampleUptime.map { uptime - $0 > Self.maximumGap } ?? false
    }
    public enum CaptureError: Error { case capacity, gap }
}
