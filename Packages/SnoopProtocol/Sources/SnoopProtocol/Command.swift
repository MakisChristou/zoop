/// Commands the phone writes to the command characteristic.
///
/// Inner packet: `[35][seq][command][args…]`. The first argument byte differs per
/// command; the strap silently ignores a HELLO sent with the wrong one.
public enum Command: Equatable {
    case toggleRealtimeHeartRate
    case abortHistoricalTransmits
    case sendHistoricalData
    case historicalDataResult
    case getBatteryLevel
    case getBatteryPackInfo
    case getDataRange
    case getAdvertisingName
    case getHello
    case getClock
    case ecgWrist, ecgGeneration, ecgSaveRaw, ecgRawLive, ecgSaveFiltered, ecgFilteredLive

    public var code: UInt8 {
        switch self {
        case .toggleRealtimeHeartRate: 3
        case .abortHistoricalTransmits: 20
        case .sendHistoricalData: 22
        case .historicalDataResult: 23
        case .getBatteryLevel: 26
        case .getBatteryPackInfo: 151
        case .getDataRange: 34
        case .getAdvertisingName: 141
        case .getHello: 145
        case .getClock: 147
        case .ecgWrist: 123
        case .ecgGeneration: 124
        case .ecgSaveRaw: 125
        case .ecgRawLive: 126
        case .ecgSaveFiltered: 127
        case .ecgFilteredLive: 139
        }
    }

    static let requestDestination: UInt8 = 0x00
    static let requestSource: UInt8 = 0x01

    /// The fixed CLIENT_HELLO the official app sends after subscribing. Byte-exact to
    /// hardware captures.
    public static let clientHello: [UInt8] = [
        0xAA, 0x01, 0x08, 0x00, 0x00, 0x01, 0xE6, 0x71, 0x23, 0x01, 0x91, 0x01, 0x36, 0x3E, 0x5C, 0x8D,
    ]

    /// Builds a COMMAND frame. `args` includes the per-command first byte.
    public static func build(_ command: Command, sequence: UInt8, args: [UInt8]) -> [UInt8] {
        Frame.encode(inner: [PacketType.commandByte, sequence, command.code] + args,
                     destination: requestDestination, source: requestSource)
    }

    /// Switches the beat-by-beat live stream (packet type 40) on or off. Toggles on this
    /// strap take a single 1/0 argument byte.
    public static func toggleRealtimeHeartRate(_ on: Bool, sequence: UInt8) -> [UInt8] {
        build(.toggleRealtimeHeartRate, sequence: sequence, args: [on ? 0x01 : 0x00])
    }

    public static func getAdvertisingName(sequence: UInt8) -> [UInt8] {
        build(.getAdvertisingName, sequence: sequence, args: [0x01])
    }

    public static func getDataRange(sequence: UInt8) -> [UInt8] {
        build(.getDataRange, sequence: sequence, args: [0x00])
    }

    public static func getBatteryLevel(sequence: UInt8) -> [UInt8] {
        build(.getBatteryLevel, sequence: sequence, args: [])
    }

    public static func getBatteryPackInfo(sequence: UInt8) -> [UInt8] {
        build(.getBatteryPackInfo, sequence: sequence, args: [1])
    }

    public static func sendHistoricalData(sequence: UInt8) -> [UInt8] {
        build(.sendHistoricalData, sequence: sequence, args: [0x00])
    }

    public static func abortHistoricalTransmits(sequence: UInt8) -> [UInt8] {
        build(.abortHistoricalTransmits, sequence: sequence, args: [])
    }

    /// Acknowledges one committed chunk by echoing its HISTORY_END token verbatim after a
    /// 0x01 argument byte.
    public static func historyAck(sequence: UInt8, token: [UInt8]) throws -> [UInt8] {
        guard token.count == Metadata.tokenLength else {
            throw ProtocolError.badToken(length: token.count)
        }
        return build(.historicalDataResult, sequence: sequence, args: [0x01] + token)
    }
}
