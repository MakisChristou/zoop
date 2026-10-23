@testable import SnoopProtocol

/// Frames built the way the strap builds them, for tests.
enum Synthetic {
    static func envelope(_ inner: [UInt8]) -> [UInt8] {
        Frame.encode(inner: inner, destination: 0x01, source: 0x00)
    }

    static func put(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt16) {
        buffer[offset] = UInt8(value & 0xFF)
        buffer[offset + 1] = UInt8(value >> 8)
    }

    static func put(_ buffer: inout [UInt8], _ offset: Int, _ value: UInt32) {
        for i in 0..<4 { buffer[offset + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
    }

    static func put(_ buffer: inout [UInt8], _ offset: Int, _ value: Float) {
        put(&buffer, offset, value.bitPattern)
    }

    struct R18 {
        var unixSeconds: UInt32 = 1_790_000_000
        var heartRate: UInt8 = 52
        var rr: [UInt16] = [1150, 1160]
        var skinTemperatureC: Float = 34.12
        var steps: UInt16 = 1234
        var bandState: BandState = .sleep
        var spo2: UInt8 = 97
        var gravity: SIMD3<Float> = [0.1, -0.2, 0.97]
    }

    /// Builds a 124-byte R18 frame with frame-absolute offsets.
    static func r18(_ r: R18 = R18()) -> [UInt8] {
        var f = [UInt8](repeating: 0, count: 124)
        f[8] = PacketType.historicalDataByte
        f[9] = Layout.biometricByte
        f[10] = 0x80
        put(&f, 11, UInt32(4242))
        put(&f, 15, r.unixSeconds)
        f[Biometric.heartRateOffset] = r.heartRate
        f[Biometric.rrCountOffset] = UInt8(r.rr.count)
        for (i, rr) in r.rr.enumerated() { put(&f, Biometric.rrOffset + i * 2, rr) }
        put(&f, Biometric.dynamicAccelerationOffset, Float(0.02))
        put(&f, Biometric.gravityOffset, r.gravity.x)
        put(&f, Biometric.gravityOffset + 4, r.gravity.y)
        put(&f, Biometric.gravityOffset + 8, r.gravity.z)
        put(&f, Biometric.stepsOffset, r.steps)
        put(&f, Biometric.auxTemperature1Offset, UInt16(331))
        put(&f, Biometric.skinTemperatureOffset, UInt16((r.skinTemperatureC * 100).rounded()))
        f[Biometric.stateBitsOffset] = r.bandState.stateBits
        f[Biometric.spo2Offset] = r.spo2
        let frame = envelope(Array(f[8..<120]))
        precondition(frame.count == 124)
        return frame
    }
}
