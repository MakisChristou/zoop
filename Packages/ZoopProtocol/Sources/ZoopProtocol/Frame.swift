/// One complete, CRC-valid format-1 frame.
///
/// ```
/// [0]  0xAA        start of frame
/// [1]  0x01        format 1
/// [2]  u16 LE      declared length = frame length - 8
/// [4]  u8          destination (requests 0x00, strap replies 0x01)
/// [5]  u8          source      (requests 0x01, strap replies 0x00)
/// [6]  u16 LE      CRC-16/MODBUS over bytes [0, 6)
/// [8]  ...         inner packet, zero-padded to a multiple of 4
/// [-4] u32 LE      CRC-32 over the inner packet
/// ```
public struct Frame: Equatable {
    public static let startOfFrame: UInt8 = 0xAA
    public static let format1: UInt8 = 0x01
    public static let headerLength = 8
    public static let trailerLength = 4
    public static let minimumLength = headerLength + 4 + trailerLength
    public static let maximumLength = 4096

    public let raw: [UInt8]

    /// Validates structure and both checksums.
    public init(parsing raw: [UInt8]) throws {
        guard raw.count >= Self.minimumLength else {
            throw ProtocolError.tooShort(length: raw.count)
        }
        guard raw[0] == Self.startOfFrame, raw[1] == Self.format1 else {
            throw ProtocolError.notFormat1(start: raw[0], format: raw[1])
        }
        let declared = Int(raw[2]) | Int(raw[3]) << 8
        guard declared + Self.headerLength == raw.count else {
            throw ProtocolError.lengthMismatch(declared: declared + Self.headerLength, actual: raw.count)
        }
        guard (declared - Self.trailerLength) % 4 == 0 else {
            throw ProtocolError.unaligned
        }
        let headerCRC = UInt16(raw[6]) | UInt16(raw[7]) << 8
        guard CRC.crc16Modbus(raw[0..<6]) == headerCRC else {
            throw ProtocolError.headerCRC
        }
        let trailer = raw.count - Self.trailerLength
        let bodyCRC = UInt32(raw[trailer]) | UInt32(raw[trailer + 1]) << 8
            | UInt32(raw[trailer + 2]) << 16 | UInt32(raw[trailer + 3]) << 24
        guard CRC.crc32(raw[Self.headerLength..<trailer]) == bodyCRC else {
            throw ProtocolError.bodyCRC
        }
        self.raw = raw
    }

    public var packetType: PacketType {
        PacketType(byte: raw[Self.headerLength])
    }

    /// The inner packet: the bytes the CRC-32 covers.
    public var inner: ArraySlice<UInt8> {
        raw[Self.headerLength..<(raw.count - Self.trailerLength)]
    }

    var innerEnd: Int { raw.count - Self.trailerLength }

    func bytes(at offset: Int, count: Int) throws -> ArraySlice<UInt8> {
        guard offset >= Self.headerLength, offset + count <= innerEnd else {
            throw ProtocolError.outOfBounds(offset: offset)
        }
        return raw[offset..<(offset + count)]
    }

    func u8(at offset: Int) throws -> UInt8 {
        try bytes(at: offset, count: 1).first!
    }

    func u16(at offset: Int) throws -> UInt16 {
        let b = Array(try bytes(at: offset, count: 2))
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    func i16(at offset: Int) throws -> Int16 {
        Int16(bitPattern: try u16(at: offset))
    }

    func u32(at offset: Int) throws -> UInt32 {
        let b = Array(try bytes(at: offset, count: 4))
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    func f32(at offset: Int) throws -> Float {
        Float(bitPattern: try u32(at: offset))
    }

    /// Wraps an inner packet in a format-1 envelope.
    public static func encode(inner: [UInt8], destination: UInt8, source: UInt8) -> [UInt8] {
        var body = inner
        while body.count % 4 != 0 { body.append(0) }
        let declared = UInt16(body.count + trailerLength)
        var frame: [UInt8] = [startOfFrame, format1, UInt8(declared & 0xFF), UInt8(declared >> 8), destination, source]
        let headerCRC = CRC.crc16Modbus(frame)
        frame += [UInt8(headerCRC & 0xFF), UInt8(headerCRC >> 8)]
        frame += body
        let bodyCRC = CRC.crc32(body)
        frame += [UInt8(bodyCRC & 0xFF), UInt8((bodyCRC >> 8) & 0xFF), UInt8((bodyCRC >> 16) & 0xFF), UInt8(bodyCRC >> 24)]
        return frame
    }
}
