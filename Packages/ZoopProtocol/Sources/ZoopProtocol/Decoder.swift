/// One complete, CRC-valid frame, decoded as far as the protocol is understood.
public enum Decoded: Equatable {
    case biometric(Biometric)
    case ecg(ECGStrip)
    case unknownRecord(UnknownRecord)
    case realtimeHeartRate(RealtimeHeartRate)
    case event(Event)
    case metadata(Metadata)
    case commandResponse(CommandResponse)
    /// Console logs, IMU streams and anything else: classified, kept raw.
    case other(packetType: UInt8, length: Int)
}

public enum FrameDecoder {
    /// Validates the envelope and decodes one frame.
    public static func decode(_ raw: [UInt8]) throws -> Decoded {
        let frame = try Frame(parsing: raw)
        switch frame.packetType {
        case .realtimeRawData, .historicalData:
            return try decodeRecord(frame)
        case .realtimeData:
            return .realtimeHeartRate(try RealtimeHeartRate(frame: frame))
        case .event:
            return .event(try Event(frame: frame))
        case .metadata:
            return .metadata(try Metadata(frame: frame))
        case .commandResponse:
            return .commandResponse(try CommandResponse(frame: frame))
        default:
            return .other(packetType: raw[Frame.headerLength], length: raw.count)
        }
    }

    private static func decodeRecord(_ frame: Frame) throws -> Decoded {
        let header = try RecordHeader(frame: frame)
        if let expected = header.layout.frameLength, expected != frame.raw.count {
            throw ProtocolError.recordLength(layout: header.layout.byte, expected: expected, actual: frame.raw.count)
        }
        switch header.layout {
        case .biometric:
            return .biometric(try Biometric(frame: frame, header: header))
        case .ecgRaw, .ecgFiltered:
            return .ecg(try ECGStrip(frame: frame, header: header))
        default:
            return .unknownRecord(UnknownRecord(header: header, frameLength: frame.raw.count))
        }
    }
}
