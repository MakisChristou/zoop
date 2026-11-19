import XCTest
@testable import ZoopProtocol

final class ECGTests: XCTestCase {
    func testRevisionOneCommandsAndNonBooleanWristAndGeneration() throws {
        let cases: [(ECGOperation, UInt8, UInt8)] = [
            (.wrist(.right), 123, 1), (.wrist(.left), 123, 2),
            (.generation(true), 124, 2), (.generation(false), 124, 1),
            (.rawLive(true), 126, 1), (.rawLive(false), 126, 0),
            (.filteredLive(true), 139, 1), (.filteredLive(false), 139, 0),
            (.saveRaw(true), 125, 1), (.saveRaw(false), 125, 0),
            (.saveFiltered(true), 127, 1), (.saveFiltered(false), 127, 0)
        ]
        for (operation, code, value) in cases {
            let raw = operation.frame(sequence: 42)
            _ = try Frame(parsing: raw)
            XCTAssertEqual(Array(raw[8..<13]), [35, 42, code, 1, value])
        }
    }

    func testFilteredSlotsSignedValuesAndAlignmentExcluded() throws {
        var body = [UInt8](repeating: 0, count: 228)
        body[0] = 43; body[1] = 17; body[24] = 100
        body[26] = 0; body[27] = 128 // -32768
        body[28] = 255; body[29] = 127 // +32767
        body[226] = 99; body[227] = 99 // alignment is never sample 101
        let frame = Synthetic.envelope(body)
        guard case let .ecg(strip) = try FrameDecoder.decode(frame) else { return XCTFail() }
        XCTAssertEqual(strip.samples.count, 100)
        XCTAssertEqual(Array(strip.samples.prefix(3)), [-32768, 32767, 0])
        body[24] = 101
        XCTAssertThrowsError(try FrameDecoder.decode(Synthetic.envelope(body)))
    }

    func testRawSignFlagsStatusAndFixedLeadArrays() throws {
        var body = [UInt8](repeating: 0, count: 1572)
        body[0] = 43; body[1] = 16; body[24] = 2
        body[13] = 219; body[14] = 8; body[15] = 221
        body[26] = 0xFE; body[27] = 0; body[28] = 0 // -131072; both flags + reserved
        body[29] = 1; body[30] = 255; body[31] = 255 // +131071
        body[1526] = 1; body[1527] = 0xCD; body[1528] = 0xAB
        body[1549] = 0x34; body[1550] = 0x12
        guard case let .ecg(strip) = try FrameDecoder.decode(Synthetic.envelope(body)) else { return XCTFail() }
        XCTAssertEqual(strip.samples, [-131072, 131071])
        XCTAssertEqual(strip.sampleFlags, [true, false]); XCTAssertEqual(strip.leadFlags, [true, false])
        XCTAssertEqual(strip.reservedSampleBits, [0x3C, 0])
        XCTAssertEqual(strip.quality, 219); XCTAssertEqual(strip.classifierResult, 221)
        XCTAssertEqual(strip.packedStatus.count, 13)
        XCTAssertEqual(strip.leadDiagnosticI, [0xABCD]); XCTAssertEqual(strip.leadDiagnosticQ, [0x1234])
        body[1526] = 12
        XCTAssertThrowsError(try FrameDecoder.decode(Synthetic.envelope(body)))
    }

    func testCorruptOrWrongSizedECGRejected() {
        var body = [UInt8](repeating: 0, count: 228); body[0] = 43; body[1] = 17
        var frame = Synthetic.envelope(body); frame[34] ^= 1
        XCTAssertThrowsError(try FrameDecoder.decode(frame))
        XCTAssertThrowsError(try FrameDecoder.decode(Synthetic.envelope(Array(body.dropLast(4)))))
    }
}
