/// Strap events, packet type 48.
public struct Event: Equatable {
    public enum Payload: Equatable {
        case batteryLevel(BatteryLevel)
        case charging(Bool)
        case packPresence(Bool)
        case batteryPack(BatteryPackInfo)
        case raw([UInt8])
    }

    public struct BatteryLevel: Equatable {
        public let revision: UInt8
        /// State of charge in tenths of a percent.
        public let stateOfChargeTenths: UInt16
        public let millivolts: UInt16
    }

    public static let batteryLevelCode: UInt8 = 3
    public static let chargingOnCode: UInt8 = 7
    public static let chargingOffCode: UInt8 = 8
    public static let packAttachedCode: UInt8 = 21
    public static let packRemovedCode: UInt8 = 22
    public static let batteryPackCode: UInt8 = 109

    public let code: UInt8
    public let unixSeconds: UInt32
    public let subsecond: UInt16
    /// WHOOP 5 clock fractions use 1/32768 second ticks. Preserve them when
    /// ordering battery updates that arrive in the same whole second.
    public var timestamp: Double { Double(unixSeconds) + Double(subsecond) / 32768 }
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
        } else if code == Self.chargingOnCode || code == Self.chargingOffCode {
            payload = .charging(code == Self.chargingOnCode)
        } else if code == Self.packAttachedCode || code == Self.packRemovedCode {
            payload = .packPresence(code == Self.packAttachedCode)
        } else if code == Self.batteryPackCode, declared == 28, bytes.count == declared,
                  let info = BatteryPackInfo(record: bytes) {
            payload = .batteryPack(info)
        } else {
            payload = .raw(bytes)
        }
    }
}
