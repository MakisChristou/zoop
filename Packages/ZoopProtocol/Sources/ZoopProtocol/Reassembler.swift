/// Joins BLE notification fragments into complete frames.
///
/// Records up to 2,140 bytes arrive across many notifications; only the first fragment
/// starts with the frame marker. Bytes that cannot start a valid frame are skipped one
/// at a time, so a corrupt fragment costs at most one frame.
public struct Reassembler {
    private var buffer: [UInt8] = []
    public private(set) var droppedBytes = 0

    public init() {}

    public var pendingBytes: Int { buffer.count }

    /// Feeds one notification; returns every complete frame now available.
    public mutating func feed(_ fragment: [UInt8]) -> [[UInt8]] {
        buffer += fragment
        var frames: [[UInt8]] = []
        while true {
            guard let start = findStart() else {
                let keep = buffer.last == Frame.startOfFrame ? 1 : 0
                droppedBytes += buffer.count - keep
                buffer.removeFirst(buffer.count - keep)
                break
            }
            if start > 0 {
                droppedBytes += start
                buffer.removeFirst(start)
            }
            guard buffer.count >= 4 else { break }
            let total = (Int(buffer[2]) | Int(buffer[3]) << 8) + Frame.headerLength
            guard (Frame.minimumLength...Frame.maximumLength).contains(total) else {
                skipOne()
                continue
            }
            guard buffer.count >= total else { break }
            let candidate = Array(buffer[0..<total])
            guard (try? Frame(parsing: candidate)) != nil else {
                skipOne()
                continue
            }
            frames.append(candidate)
            buffer.removeFirst(total)
        }
        return frames
    }

    private func findStart() -> Int? {
        guard buffer.count >= 2 else { return nil }
        for i in 0..<(buffer.count - 1) where buffer[i] == Frame.startOfFrame && buffer[i + 1] == Frame.format1 {
            return i
        }
        return nil
    }

    private mutating func skipOne() {
        buffer.removeFirst()
        droppedBytes += 1
    }
}
