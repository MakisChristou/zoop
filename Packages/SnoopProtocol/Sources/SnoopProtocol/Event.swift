/// Strap events, packet type 48.
public struct Event: Equatable {
    public enum Payload: Equatable {
        case batteryLevel(BatteryLevel)
        case raw([UInt8])
    }

    public struct BatteryLevel: Equatable {
        public let revision: UInt8
        /// State of charge in tenths of a percent.
        public let stateOfChargeTenths: UInt16
        public let millivolts: UInt16
    }

    public static let batteryLevelCode: UInt8 = 3

    public let code: UInt8
    public let unixSeconds: UInt32
    public let subsecond: UInt16
    public let payload: Payload

    static let codeOffset = 10
    static let unixOffset = 12
    static let subsecondOffset = 16
    static let payloadLengthOffset = 18
    static let payloadOffset = 20

    init(frame: Frame) throws {
        code = try frame.u8(at: Self.codeOffset)
        unixSeconds = try frame.u32(at: Self.unixOffset)
        subsecond = try frame.u16(at: Self.subsecondOffset)
        let declared = Int(try frame.u16(at: Self.payloadLengthOffset))
        let available = max(frame.innerEnd - Self.payloadOffset, 0)
        let bytes = Array(try frame.bytes(at: Self.payloadOffset, count: min(declared, available)))
        if code == Self.batteryLevelCode, bytes.count >= 7 {
            payload = .batteryLevel(BatteryLevel(
                revision: bytes[0],
                stateOfChargeTenths: UInt16(bytes[1]) | UInt16(bytes[2]) << 8,
                millivolts: UInt16(bytes[5]) | UInt16(bytes[6]) << 8))
        } else {
            payload = .raw(bytes)
        }
    }
}
