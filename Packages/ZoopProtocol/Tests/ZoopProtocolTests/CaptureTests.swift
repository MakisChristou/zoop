import XCTest
@testable import ZoopProtocol

/// Synthetic wire-format fixtures built from documented offsets.
/// Hardware interoperability is checked separately on a paired device.
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

    func testSyntheticR18DaytimeRecord() throws {
        let frame = bytes("aa01740001003fb12f12802a00000000f153650000003c0000000000000000000000000000000000000000000000000000000000000000803fd2040000000000000000000000000000e40c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007c504349")
        guard case let .biometric(b) = try FrameDecoder.decode(frame) else { return XCTFail() }
        XCTAssertEqual(b.header.layout, .biometric)
        XCTAssertEqual(b.header.unixSeconds, 1_700_000_000) // Fixed synthetic timestamp
        XCTAssertEqual(b.heartRate, 60)
        XCTAssertEqual(b.rrMilliseconds, [], "no R-R while moving")
        XCTAssertEqual(b.bandState, .wake)
        XCTAssertEqual(b.activity, .still)
        XCTAssertEqual(b.steps, 1234)
        XCTAssertEqual(b.skinTemperatureC!, 33.0, accuracy: 0.01)
        XCTAssertNil(b.spo2Percent)
        XCTAssertNotNil(b.gravityG)
    }

    func testSyntheticCompactOpticalIsPreservedAsUnknown() throws {
        let frame = bytes("aa015000010035412f1a802b00000001f153650000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000fec5c9c9")
        guard case let .unknownRecord(u) = try FrameDecoder.decode(frame) else { return XCTFail() }
        XCTAssertEqual(u.header.layout, .compactOptical)
        XCTAssertEqual(u.frameLength, 88)
    }

    func testSyntheticHelloResponse() throws {
        let frame = bytes("aa01740001003fb1240191010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009f6e5028")
        guard case let .commandResponse(r) = try FrameDecoder.decode(frame) else { return XCTFail() }
        XCTAssertEqual(r.command, Command.getHello.code)
        XCTAssertEqual(r.result, .pending, "the first of two hello replies is PENDING")
        XCTAssertEqual(r.originSequence, 1)
    }

    func testSyntheticEventMetadataAndConsole() throws {
        guard case let .event(e) = try FrameDecoder.decode(bytes("aa011000010020813000220002f1536500000000f297b07f")) else { return XCTFail() }
        XCTAssertEqual(e.code, 34)
        XCTAssertEqual(e.unixSeconds, 1_700_000_002)

        guard case let .metadata(m) = try FrameDecoder.decode(bytes("aa012c0001002cd1310001000000000000000000000000000000000000000000000000000000000000000000000000005750780d")) else { return XCTFail() }
        XCTAssertEqual(m.kind, .historyStart)
        XCTAssertNil(m.historyEndToken)

        guard case let .other(type, length) = try FrameDecoder.decode(bytes("aa014400010030b13273796e74686574696320636f6e736f6c65207061636b65740000000000000000000000000000000000000000000000000000000000000000000000000000000d21fb53")) else { return XCTFail() }
        XCTAssertEqual(type, PacketType.consoleLogsByte)
        XCTAssertEqual(length, 76)
    }
}
