import XCTest
@testable import ZoopProtocol

/// Frames captured from our own WHOOP MG (firmware 50.x, October 2026). These pin the
/// decoder to real hardware rather than to our synthetic encoder.
final class CaptureTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    func testRealR18DaytimeRecord() throws {
        let frame = bytes("aa01740001003fb12f128082d5a6026fa9db6ae11a004c00000000000000000080e05d01044c0000cf0081d43bb8feb83d3383e33e4851663fdc17a40000000000000000002e013901ad0c0002010c060c0000000000000000000000000000000000000000000000010055332b2700000048e483c00000003001f978")
        guard case let .biometric(b) = try FrameDecoder.decode(frame) else { return XCTFail() }
        XCTAssertEqual(b.header.layout, .biometric)
        XCTAssertEqual(b.header.unixSeconds, 1_792_780_655) // 2026-10-23 18:37:35 UTC
        XCTAssertEqual(b.heartRate, 76)
        XCTAssertEqual(b.rrMilliseconds, [], "no R-R while moving")
        XCTAssertEqual(b.bandState, .wake)
        XCTAssertEqual(b.activity, .still)
        XCTAssertEqual(b.steps, 6108)
        XCTAssertEqual(b.skinTemperatureC!, 32.45, accuracy: 0.01)
        XCTAssertNil(b.spo2Percent)
        XCTAssertNotNil(b.gravityG)
    }

    func testRealCompactOpticalIsPreservedAsUnknown() throws {
        let frame = bytes("aa015000010035412f1a8084d5a60271a9db6ae11a42004c8c010011003400280033004b005700380029fef1fcbffd98fef1fe1aff6aff8effa5ffbefff1ff2c0052005900780076007700007da33b00020001007e6bc759")
        guard case let .unknownRecord(u) = try FrameDecoder.decode(frame) else { return XCTFail() }
        XCTAssertEqual(u.header.layout, .compactOptical)
        XCTAssertEqual(u.frameLength, 88)
    }

    func testRealHelloResponse() throws {
        let frame = bytes("aa01740001003fb124479101020100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f1004b6f")
        guard case let .commandResponse(r) = try FrameDecoder.decode(frame) else { return XCTFail() }
        XCTAssertEqual(r.command, Command.getHello.code)
        XCTAssertEqual(r.result, .pending, "the first of two hello replies is PENDING")
        XCTAssertEqual(r.originSequence, 1)
    }

    func testRealEventMetadataAndConsole() throws {
        guard case let .event(e) = try FrameDecoder.decode(bytes("aa01100001002081301022004caadb6a002000002f797d84")) else { return XCTFail() }
        XCTAssertEqual(e.code, 34)
        XCTAssertEqual(e.unixSeconds, 1_792_780_876)

        guard case let .metadata(m) = try FrameDecoder.decode(bytes("aa012c0001002cd1310a01e4abdb6ae11a0d0000000000000000000000320000002b00000001000000000000000c000461074385")) else { return XCTFail() }
        XCTAssertEqual(m.kind, .historyStart)
        XCTAssertNil(m.historyEndToken)

        guard case let .other(type, length) = try FrameDecoder.decode(bytes("aa014400010030b1327b02007da9db6ab81e3400017261776272696467650a2033312c203231343433353130303a20424c455f434d443a2053656e642070657273697374656e7400242a7e05")) else { return XCTFail() }
        XCTAssertEqual(type, PacketType.consoleLogsByte)
        XCTAssertEqual(length, 76)
    }
}
