/// First byte of the inner packet.
public enum PacketType: Equatable {
    case command
    case commandResponse
    case realtimeData
    case realtimeRawData
    case historicalData
    case event
    case metadata
    case consoleLogs
    case realtimeIMUStream
    case historicalIMUStream
    case unknown(UInt8)

    public static let commandByte: UInt8 = 35
    public static let commandResponseByte: UInt8 = 36
    public static let realtimeDataByte: UInt8 = 40
    public static let realtimeRawDataByte: UInt8 = 43
    public static let historicalDataByte: UInt8 = 47
    public static let eventByte: UInt8 = 48
    public static let metadataByte: UInt8 = 49
    public static let consoleLogsByte: UInt8 = 50
    public static let realtimeIMUStreamByte: UInt8 = 51
    public static let historicalIMUStreamByte: UInt8 = 52

    public init(byte: UInt8) {
        switch byte {
        case Self.commandByte: self = .command
        case Self.commandResponseByte: self = .commandResponse
        case Self.realtimeDataByte: self = .realtimeData
        case Self.realtimeRawDataByte: self = .realtimeRawData
        case Self.historicalDataByte: self = .historicalData
        case Self.eventByte: self = .event
        case Self.metadataByte: self = .metadata
        case Self.consoleLogsByte: self = .consoleLogs
        case Self.realtimeIMUStreamByte: self = .realtimeIMUStream
        case Self.historicalIMUStreamByte: self = .historicalIMUStream
        default: self = .unknown(byte)
        }
    }

    /// Live (43) and stored (47) records share the record header.
    public var carriesRecord: Bool {
        self == .realtimeRawData || self == .historicalData
    }
}
