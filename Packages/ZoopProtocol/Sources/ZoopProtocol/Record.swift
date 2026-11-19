/// Record layout selector, frame byte 9.
public enum Layout: Equatable {
    case ecgRaw, ecgFiltered, biometric, optical, imu, v9, compactOptical
    case unknown(UInt8)

    public static let ecgRawByte: UInt8 = 16
    public static let ecgFilteredByte: UInt8 = 17
    public static let biometricByte: UInt8 = 18
    public static let opticalByte: UInt8 = 20
    public static let imuByte: UInt8 = 21
    public static let v9Byte: UInt8 = 22
    public static let compactOpticalByte: UInt8 = 26

    public init(byte: UInt8) {
        switch byte {
        case Self.ecgRawByte: self = .ecgRaw
        case Self.ecgFilteredByte: self = .ecgFiltered
        case Self.biometricByte: self = .biometric
        case Self.opticalByte: self = .optical
        case Self.imuByte: self = .imu
        case Self.v9Byte: self = .v9
        case Self.compactOpticalByte: self = .compactOptical
        default: self = .unknown(byte)
        }
    }

    public var byte: UInt8 {
        switch self {
        case .ecgRaw: Self.ecgRawByte
        case .ecgFiltered: Self.ecgFilteredByte
        case .biometric: Self.biometricByte
        case .optical: Self.opticalByte
        case .imu: Self.imuByte
        case .v9: Self.v9Byte
        case .compactOptical: Self.compactOpticalByte
        case let .unknown(byte): byte
        }
    }

    /// Fixed total frame length for layouts with one; a mismatch means the bytes are
    /// not this layout, not a layout with fields missing.
    public var frameLength: Int? {
        switch self {
        case .ecgRaw: 1584
        case .ecgFiltered: 240
        case .biometric: 124
        case .optical: 2140
        case .imu: 1244
        case .compactOptical: 88
        case .v9, .unknown: nil
        }
    }
}

/// Common record header, frame offsets 8..21.
public struct RecordHeader: Equatable {
    public let layout: Layout
    public let marker: UInt8
    /// The strap's own record counter. Not a timestamp.
    public let recordIndex: UInt32
    public let unixSeconds: UInt32
    public let subsecond: UInt16

    public static let layoutOffset = 9

    init(frame: Frame) throws {
        layout = Layout(byte: try frame.u8(at: Self.layoutOffset))
        marker = try frame.u8(at: 10)
        recordIndex = try frame.u32(at: 11)
        unixSeconds = try frame.u32(at: 15)
        subsecond = try frame.u16(at: 19)
    }
}

/// The strap's own motion/rest classification, R18 state bits 4..6.
/// `.sleep` is WHOOP's on-device rest flag, not a sleep stage.
public enum BandState: UInt8, Equatable {
    case wake = 0, still = 1, sleep = 2, up = 3

    static let shift: UInt8 = 4
    static let mask: UInt8 = 0b11

    public init(stateBits: UInt8) {
        self = BandState(rawValue: (stateBits >> Self.shift) & Self.mask) ?? .up
    }

    public var stateBits: UInt8 { rawValue << Self.shift }
}

/// Coarse activity class, R18 byte 63.
public enum ActivityClass: Equatable {
    case still, walk, run
    case other(UInt8)

    public init(byte: UInt8) {
        switch byte {
        case 0: self = .still
        case 1: self = .walk
        case 2: self = .run
        default: self = .other(byte)
        }
    }
}

/// R18 biometric summary, one per second. 124-byte frame.
public struct Biometric: Equatable {
    public let header: RecordHeader
    public let heartRate: UInt8
    /// R-R intervals in milliseconds, zero placeholders removed.
    public let rrMilliseconds: [UInt16]
    public let hrFlags: UInt8
    public let alternateHeartRate: UInt8
    public let dynamicAccelerationG: Float?
    public let gravityG: SIMD3<Float>?
    public let steps: UInt16
    public let cadenceRaw: UInt16
    public let hardwareSteps: UInt16
    public let activity: ActivityClass
    /// Auxiliary temperatures in °C; nil outside 0...60.
    public let auxTemperature1C: Float?
    public let auxTemperature2C: Float?
    /// Skin temperature in °C; nil outside 5...45.
    public let skinTemperatureC: Float?
    public let statusWords: [UInt16]
    public let stateBits: UInt8
    public let bandState: BandState
    /// SpO₂ percentage when byte 82 holds a valid reading (70...100). The strap measures
    /// in 30 s windows every 20 minutes during sleep; otherwise nil.
    public let spo2Percent: UInt8?
    public let spo2Raw: UInt8

    public static let heartRateOffset = 22
    public static let rrCountOffset = 23
    public static let rrOffset = 24
    public static let rrMax = 4
    public static let hrFlagsOffset = 36
    public static let alternateHeartRateOffset = 37
    public static let dynamicAccelerationOffset = 41
    public static let gravityOffset = 45
    public static let stepsOffset = 57
    public static let cadenceOffset = 59
    public static let hardwareStepsOffset = 61
    public static let activityOffset = 63
    public static let auxTemperature1Offset = 69
    public static let auxTemperature2Offset = 71
    public static let skinTemperatureOffset = 73
    public static let statusWordsOffset = 75
    public static let stateBitsOffset = 81
    public static let spo2Offset = 82

    init(frame: Frame, header: RecordHeader) throws {
        self.header = header
        heartRate = try frame.u8(at: Self.heartRateOffset)
        let rrCount = min(Int(try frame.u8(at: Self.rrCountOffset)), Self.rrMax)
        rrMilliseconds = try (0..<rrCount).map { try frame.u16(at: Self.rrOffset + $0 * 2) }.filter { $0 != 0 }
        hrFlags = try frame.u8(at: Self.hrFlagsOffset)
        alternateHeartRate = try frame.u8(at: Self.alternateHeartRateOffset)
        let accel = try frame.f32(at: Self.dynamicAccelerationOffset)
        dynamicAccelerationG = accel.isFinite && (0...8).contains(accel) ? accel : nil
        let g = SIMD3(try frame.f32(at: Self.gravityOffset), try frame.f32(at: Self.gravityOffset + 4), try frame.f32(at: Self.gravityOffset + 8))
        gravityG = g.x.isFinite && g.y.isFinite && g.z.isFinite ? g : nil
        steps = try frame.u16(at: Self.stepsOffset)
        cadenceRaw = try frame.u16(at: Self.cadenceOffset)
        hardwareSteps = try frame.u16(at: Self.hardwareStepsOffset)
        activity = ActivityClass(byte: try frame.u8(at: Self.activityOffset))
        func aux(_ offset: Int) throws -> Float? {
            let c = Float(try frame.i16(at: offset)) / 10
            return (0...60).contains(c) ? c : nil
        }
        auxTemperature1C = try aux(Self.auxTemperature1Offset)
        auxTemperature2C = try aux(Self.auxTemperature2Offset)
        let skin = Float(try frame.u16(at: Self.skinTemperatureOffset)) / 100
        skinTemperatureC = (5...45).contains(skin) ? skin : nil
        statusWords = try (0..<3).map { try frame.u16(at: Self.statusWordsOffset + $0 * 2) }
        stateBits = try frame.u8(at: Self.stateBitsOffset)
        bandState = BandState(stateBits: stateBits)
        spo2Raw = try frame.u8(at: Self.spo2Offset)
        spo2Percent = (70...100).contains(spo2Raw) ? spo2Raw : nil
    }
}

/// MG ECG strip: R16 raw (18-bit samples, up to 500) or R17 filtered (Int16, up to 100).
public struct ECGStrip: Equatable {
    public let header: RecordHeader
    public let quality: UInt8
    public let stateBits: UInt8
    public let classifierResult: UInt8
    public let classifierState: UInt8
    public let progress: UInt8
    public let declaredCount: UInt16
    /// Raw ADC counts; scale to volts is not established.
    public let samples: [Int32]
    /// R16 only: per-sample flag bit 6.
    public let sampleFlags: [Bool]
    /// R16 flag 7 has slower, unresolved contact/lead timing. It is not a quality score.
    public let leadFlags: [Bool]
    public let reservedSampleBits: [UInt8]
    /// Preserve the packed status verbatim; classifier and HR fields are not diagnoses.
    public let packedStatus: [UInt8]
    public let leadDiagnosticI: [UInt16]
    public let leadDiagnosticQ: [UInt16]

    static let sampleCountOffset = 32
    static let sampleOffset = 34

    init(frame: Frame, header: RecordHeader) throws {
        self.header = header
        quality = try frame.u8(at: 21)
        stateBits = try frame.u8(at: 22)
        classifierResult = try frame.u8(at: 23)
        classifierState = try frame.u8(at: 24)
        progress = try frame.u8(at: 25)
        declaredCount = try frame.u16(at: Self.sampleCountOffset)
        packedStatus = Array(try frame.bytes(at: 21, count: 13))
        let (capacity, width) = header.layout == .ecgRaw ? (500, 3) : (100, 2)
        let count = Int(declaredCount)
        guard count <= capacity else {
            throw ProtocolError.recordLength(layout: header.layout.byte, expected: capacity, actual: count)
        }
        var samples: [Int32] = []
        var flags: [Bool] = []
        var leads: [Bool] = []
        var reserved: [UInt8] = []
        samples.reserveCapacity(count)
        for i in 0..<count {
            let offset = Self.sampleOffset + i * width
            if width == 2 {
                samples.append(Int32(try frame.i16(at: offset)))
            } else {
                let b = Array(try frame.bytes(at: offset, count: 3))
                let raw18 = Int32(b[0] & 0x03) << 16 | Int32(b[1]) << 8 | Int32(b[2])
                samples.append(raw18 >= 1 << 17 ? raw18 - (1 << 18) : raw18)
                flags.append((b[0] >> 6) & 1 == 1)
                leads.append(b[0] & 0x80 != 0)
                reserved.append(b[0] & 0x3C)
            }
        }
        self.samples = samples
        sampleFlags = flags
        leadFlags = leads
        reservedSampleBits = reserved
        if header.layout == .ecgRaw {
            let count = Int(try frame.u8(at: 1534))
            guard count <= 11 else {
                throw ProtocolError.recordLength(layout: header.layout.byte, expected: 11, actual: count)
            }
            leadDiagnosticI = try (0..<count).map { try frame.u16(at: 1535 + $0 * 2) }
            leadDiagnosticQ = try (0..<count).map { try frame.u16(at: 1557 + $0 * 2) }
        } else {
            leadDiagnosticI = []
            leadDiagnosticQ = []
        }
    }
}

/// A record whose layout is not decoded yet; the raw frame is still uploaded.
public struct UnknownRecord: Equatable {
    public let header: RecordHeader
    public let frameLength: Int
}
