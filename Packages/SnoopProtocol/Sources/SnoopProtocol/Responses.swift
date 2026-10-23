/// Replies from the strap: command responses (36), live heart rate (40) and the
/// history-offload metadata markers (49).
public enum ResultCode: Equatable {
    case failure, success, pending, unsupported
    case unknown(UInt8)

    public init(byte: UInt8) {
        switch byte {
        case 0: self = .failure
        case 1: self = .success
        case 2: self = .pending
        case 3: self = .unsupported
        default: self = .unknown(byte)
        }
    }
}

/// GET_DATA_RANGE reply body: where the strap's history ring buffer stands.
public struct DataRange: Equatable {
    public static let bodyLength = 65

    public let revision: UInt8
    public let ringBoundary: UInt32
    public let readPage: UInt32
    public let writePage: UInt32
    public let trimPage: UInt32
    public let writeWrap: UInt32
    public let totalPages: UInt32
    public let recordEstimate: UInt32
    public let newestClockSeconds: UInt32?

    init?(body: ArraySlice<UInt8>) {
        guard body.count >= Self.bodyLength else { return nil }
        let b = Array(body)
        func u32(_ o: Int) -> UInt32 { UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24 }
        revision = b[0]
        ringBoundary = u32(1)
        readPage = u32(5)
        writePage = u32(9)
        trimPage = u32(13)
        writeWrap = u32(17)
        totalPages = u32(21)
        recordEstimate = u32(25)
        let newest = u32(57)
        newestClockSeconds = (newest == 0 || newest == .max) ? nil : newest
    }

    /// Pages written but not yet offloaded, accounting for ring wrap-around.
    public var pagesBehind: UInt32? {
        guard totalPages > 0, writePage < totalPages, trimPage < totalPages else { return nil }
        return writePage >= trimPage ? writePage - trimPage : (totalPages - trimPage) + writePage
    }
}

/// Packet type 36: `[36][seq][command][origin seq][result][body…]`.
public struct CommandResponse: Equatable {
    public static let bodyOffset = 13

    public let sequence: UInt8
    public let command: UInt8
    public let originSequence: UInt8
    public let result: ResultCode
    public let body: [UInt8]
    /// Decoded when the command was GET_DATA_RANGE and succeeded.
    public let dataRange: DataRange?

    init(frame: Frame) throws {
        sequence = try frame.u8(at: 9)
        command = try frame.u8(at: 10)
        originSequence = try frame.u8(at: 11)
        result = ResultCode(byte: try frame.u8(at: 12))
        let slice = try frame.bytes(at: Self.bodyOffset, count: max(frame.innerEnd - Self.bodyOffset, 0))
        body = Array(slice)
        dataRange = (command == Command.getDataRange.code && result == .success) ? DataRange(body: slice) : nil
    }
}

/// Packet type 40: live heart rate with the strap's own clock.
public struct RealtimeHeartRate: Equatable {
    public let unixSeconds: UInt32
    public let auxTime: UInt16
    public let heartRate: UInt8
    /// R-R intervals in milliseconds, zero placeholders removed.
    public let rrMilliseconds: [UInt16]

    static let rrOffset = 18
    static let rrMax = 64

    init(frame: Frame) throws {
        unixSeconds = try frame.u32(at: 10)
        auxTime = try frame.u16(at: 14)
        heartRate = try frame.u8(at: 16)
        let count = min(Int(try frame.u8(at: 17)), Self.rrMax)
        var rr: [UInt16] = []
        for i in 0..<count {
            guard let value = try? frame.u16(at: Self.rrOffset + i * 2) else { break }
            if value != 0 { rr.append(value) }
        }
        rrMilliseconds = rr
    }
}

public enum MetadataKind: Equatable {
    case historyStart, historyEnd, historyComplete
    case unknown(UInt8)

    public init(byte: UInt8) {
        switch byte {
        case 1: self = .historyStart
        case 2: self = .historyEnd
        case 3: self = .historyComplete
        default: self = .unknown(byte)
        }
    }
}

/// Packet type 49: history offload markers. A HISTORY_END carries the 8-byte token the
/// phone must echo back, or the offload stalls after this chunk.
public struct Metadata: Equatable {
    public static let tokenOffset = 21
    public static let tokenLength = 8

    public let kind: MetadataKind
    public let unixSeconds: UInt32
    public let subsecond: UInt16
    public let historyEndToken: [UInt8]?

    init(frame: Frame) throws {
        kind = MetadataKind(byte: try frame.u8(at: 10))
        unixSeconds = try frame.u32(at: 11)
        subsecond = try frame.u16(at: 15)
        historyEndToken = kind == .historyEnd
            ? (try? frame.bytes(at: Self.tokenOffset, count: Self.tokenLength)).map(Array.init)
            : nil
    }
}
