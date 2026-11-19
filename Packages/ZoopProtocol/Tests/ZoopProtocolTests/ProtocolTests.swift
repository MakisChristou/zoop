import XCTest
@testable import ZoopProtocol

final class CRCTests: XCTestCase {
    func testCheckValues() {
        XCTAssertEqual(CRC.crc16Modbus(Array("123456789".utf8)), 0x4B37)
        XCTAssertEqual(CRC.crc32(Array("123456789".utf8)), 0xCBF4_3926)
        XCTAssertEqual(CRC.crc32([]), 0)
    }
}

final class FrameTests: XCTestCase {
    func testEncodeThenParseRoundtrips() throws {
        let frame = Command.build(.getHello, sequence: 7, args: [0x01])
        let parsed = try Frame(parsing: frame)
        XCTAssertEqual(parsed.packetType, .command)
        XCTAssertEqual(Array(parsed.inner), [35, 7, 0x91, 0x01])
    }

    func testPadsInnerToFourBytes() throws {
        let frame = Command.build(.getDataRange, sequence: 0, args: [])
        XCTAssertEqual(frame.count, Frame.headerLength + 4 + Frame.trailerLength)
        XCTAssertEqual(Array(try Frame(parsing: frame).inner), [35, 0, 34, 0])
    }

    func testCorruptChecksumsAreRejected() {
        var frame = Command.clientHello
        frame[7] ^= 0xFF
        XCTAssertThrowsError(try Frame(parsing: frame)) { XCTAssertEqual($0 as? ProtocolError, .headerCRC) }
        frame = Command.clientHello
        frame[9] ^= 0x01
        XCTAssertThrowsError(try Frame(parsing: frame)) { XCTAssertEqual($0 as? ProtocolError, .bodyCRC) }
    }

    func testClientHelloMatchesCapturedConstant() {
        XCTAssertEqual(Command.build(.getHello, sequence: 1, args: [0x01]), Command.clientHello)
    }

    func testRealtimeToggleArgumentByte() throws {
        let on = try Frame(parsing: Command.toggleRealtimeHeartRate(true, sequence: 4))
        XCTAssertEqual(Array(on.inner), [35, 4, 3, 1])
        let off = try Frame(parsing: Command.toggleRealtimeHeartRate(false, sequence: 5))
        XCTAssertEqual(Array(off.inner), [35, 5, 3, 0])
    }

    func testReassemblerJoinsFragmentsAndSkipsNoise() {
        let a = Synthetic.envelope([PacketType.eventByte, 1, 3, 0, 1, 2, 3, 4, 5, 6, 7, 8])
        let b = Synthetic.envelope([PacketType.commandResponseByte, 2, 0x91, 1, 1, 0, 0, 0])
        let stream = [0x00, 0xAA, 0x55] + a + b
        var reassembler = Reassembler()
        var frames: [[UInt8]] = []
        for start in stride(from: 0, to: stream.count, by: 5) {
            frames += reassembler.feed(Array(stream[start..<min(start + 5, stream.count)]))
        }
        XCTAssertEqual(frames, [a, b])
        XCTAssertEqual(reassembler.pendingBytes, 0)
        XCTAssertEqual(reassembler.droppedBytes, 3)
    }

    func testReassemblerRecoversRecordSplitAcrossNotifications() {
        let frame = Synthetic.r18()
        var reassembler = Reassembler()
        var out: [[UInt8]] = []
        for start in stride(from: 0, to: frame.count, by: 20) {
            out += reassembler.feed(Array(frame[start..<min(start + 20, frame.count)]))
        }
        XCTAssertEqual(out, [frame])
    }
}

final class RecordTests: XCTestCase {
    func testR18RoundtripDecodesEveryFieldWeRelyOn() throws {
        guard case let .biometric(b) = try FrameDecoder.decode(Synthetic.r18()) else {
            return XCTFail("expected a biometric record")
        }
        XCTAssertEqual(b.header.layout, .biometric)
        XCTAssertEqual(b.header.recordIndex, 4242)
        XCTAssertEqual(b.header.unixSeconds, 1_790_000_000)
        XCTAssertEqual(b.heartRate, 52)
        XCTAssertEqual(b.rrMilliseconds, [1150, 1160])
        XCTAssertEqual(b.steps, 1234)
        XCTAssertEqual(b.activity, .still)
        XCTAssertEqual(b.skinTemperatureC!, 34.12, accuracy: 0.005)
        XCTAssertEqual(b.auxTemperature1C!, 33.1, accuracy: 0.05)
        XCTAssertEqual(b.bandState, .sleep)
        XCTAssertEqual(b.spo2Percent, 97)
        XCTAssertEqual(b.gravityG, [0.1, -0.2, 0.97])
    }

    func testBandStatesAndSpo2StatusCodes() throws {
        for (state, bits): (BandState, UInt8) in [(.wake, 0x00), (.still, 0x10), (.sleep, 0x20), (.up, 0x30)] {
            XCTAssertEqual(BandState(stateBits: bits), state)
            XCTAssertEqual(BandState(stateBits: bits | 0x0F), state)
        }
        var r = Synthetic.R18()
        r.rr = []
        r.bandState = .wake
        r.spo2 = 160
        guard case let .biometric(b) = try FrameDecoder.decode(Synthetic.r18(r)) else { return XCTFail() }
        XCTAssertNil(b.spo2Percent)
        XCTAssertEqual(b.spo2Raw, 160)
        XCTAssertTrue(b.rrMilliseconds.isEmpty)
    }

    func testWrongLengthIsRejectedNotMisread() {
        var inner = [UInt8](repeating: 0, count: 100)
        inner[0] = PacketType.historicalDataByte
        inner[1] = Layout.biometricByte
        XCTAssertThrowsError(try FrameDecoder.decode(Synthetic.envelope(inner)))
    }

    func testUnknownLayoutIsPreserved() throws {
        var inner = [UInt8](repeating: 0, count: 40)
        inner[0] = PacketType.historicalDataByte
        inner[1] = Layout.v9Byte
        guard case let .unknownRecord(u) = try FrameDecoder.decode(Synthetic.envelope(inner)) else { return XCTFail() }
        XCTAssertEqual(u.header.layout, .v9)
        XCTAssertEqual(u.frameLength, 52)
    }
}

final class ResponseTests: XCTestCase {
    func testHistoryEndTokenIsExtractedAndEchoed() throws {
        var inner = [UInt8](repeating: 0, count: 24)
        inner[0] = PacketType.metadataByte
        inner[2] = 2
        Synthetic.put(&inner, 3, UInt32(1_790_000_100))
        inner.replaceSubrange(13..<21, with: [9, 8, 7, 6, 5, 4, 3, 2])
        guard case let .metadata(m) = try FrameDecoder.decode(Synthetic.envelope(inner)) else { return XCTFail() }
        XCTAssertEqual(m.kind, .historyEnd)
        XCTAssertEqual(m.unixSeconds, 1_790_000_100)
        XCTAssertEqual(m.historyEndToken, [9, 8, 7, 6, 5, 4, 3, 2])
        let ack = try Command.historyAck(sequence: 3, token: m.historyEndToken!)
        XCTAssertEqual(Array(ack[8..<20]), [35, 3, 23, 1, 9, 8, 7, 6, 5, 4, 3, 2])
        XCTAssertThrowsError(try Command.historyAck(sequence: 0, token: [1, 2, 3]))
    }

    func testBatteryEvent() throws {
        var inner = [UInt8](repeating: 0, count: 20)
        inner[0] = PacketType.eventByte
        inner[2] = Event.batteryLevelCode
        Synthetic.put(&inner, 4, UInt32(1_790_000_200))
        Synthetic.put(&inner, 10, UInt16(7))
        inner[12] = 1
        Synthetic.put(&inner, 13, UInt16(873))
        Synthetic.put(&inner, 17, UInt16(4120))
        guard case let .event(e) = try FrameDecoder.decode(Synthetic.envelope(inner)),
              case let .batteryLevel(b) = e.payload else { return XCTFail() }
        XCTAssertEqual(e.unixSeconds, 1_790_000_200)
        XCTAssertEqual(b.stateOfChargeTenths, 873)
        XCTAssertEqual(b.millivolts, 4120)
    }

    func testRealtimeHeartRate() throws {
        var inner = [UInt8](repeating: 0, count: 16)
        inner[0] = PacketType.realtimeDataByte
        Synthetic.put(&inner, 2, UInt32(1_790_000_300))
        inner[8] = 61
        inner[9] = 2
        Synthetic.put(&inner, 10, UInt16(980))
        Synthetic.put(&inner, 12, UInt16(990))
        guard case let .realtimeHeartRate(hr) = try FrameDecoder.decode(Synthetic.envelope(inner)) else { return XCTFail() }
        XCTAssertEqual(hr.heartRate, 61)
        XCTAssertEqual(hr.rrMilliseconds, [980, 990])
    }

    func testChargingEventsHaveNoPayload() throws {
        for (code, charging) in [(Event.chargingOnCode, true), (Event.chargingOffCode, false)] {
            var inner = [UInt8](repeating: 0, count: 12)
            inner[0] = PacketType.eventByte
            inner[2] = code
            Synthetic.put(&inner, 4, UInt32(1_790_000_200))
            guard case let .event(event) = try FrameDecoder.decode(Synthetic.envelope(inner)) else { return XCTFail() }
            XCTAssertEqual(event.payload, .charging(charging))
        }
    }

    func testBatteryCommandRequiresSuccessAndPlausibleWholePercent() throws {
        for (result, body, expected) in [(UInt8(1), [UInt8(42), 0, 0, 0], Optional(42.0)), (0, [42, 0, 0, 0], nil), (2, [0, 0, 0, 0], nil), (1, [101, 0, 0, 0], nil), (1, [0, 1, 0, 0], nil), (1, [42], nil)] {
            let inner: [UInt8] = [36, 1, 26, 1, result] + body
            guard case let .commandResponse(response) = try FrameDecoder.decode(Synthetic.envelope(inner)) else { return XCTFail() }
            XCTAssertEqual(response.batteryPercent, expected)
        }
    }

    func testDataRangeResponse() throws {
        var inner = [UInt8](repeating: 0, count: 5 + 65)
        inner[0] = PacketType.commandResponseByte
        inner[1] = 7
        inner[2] = Command.getDataRange.code
        inner[3] = 7
        inner[4] = 1
        inner[5] = 1
        Synthetic.put(&inner, 5 + 9, UInt32(120))
        Synthetic.put(&inner, 5 + 13, UInt32(100))
        Synthetic.put(&inner, 5 + 21, UInt32(1000))
        Synthetic.put(&inner, 5 + 57, UInt32(1_790_000_400))
        guard case let .commandResponse(r) = try FrameDecoder.decode(Synthetic.envelope(inner)) else { return XCTFail() }
        XCTAssertEqual(r.result, .success)
        XCTAssertEqual(r.dataRange?.pagesBehind, 20)
        XCTAssertEqual(r.dataRange?.newestClockSeconds, 1_790_000_400)
    }
}
