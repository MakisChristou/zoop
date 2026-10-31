import XCTest
@testable import SnoopProtocol

final class BatteryPackTests: XCTestCase {
    private func record(present: UInt8 = 1, charge: UInt16 = 642) -> [UInt8] {
        var record = [UInt8](repeating: 0, count: 28)
        record[0] = present
        record.replaceSubrange(1..<7, with: [1, 2, 3, 4, 5, 6])
        Synthetic.put(&record, 23, charge)
        return record
    }

    func testPackQueryAndReply() throws {
        XCTAssertEqual(Array(try Frame(parsing: Command.getBatteryPackInfo(sequence: 9)).inner), [35, 9, 151, 1])
        let body = [UInt8(1)] + record().prefix(27)
        for result: UInt8 in [0, 1, 2, 3] {
            let frame = Synthetic.envelope([36, 8, 151, 9, result] + body)
            guard case let .commandResponse(reply) = try FrameDecoder.decode(frame) else { return XCTFail() }
            XCTAssertEqual(reply.batteryPack?.percent, result == 1 ? 64.2 : nil)
            XCTAssertEqual(reply.originSequence, 9)
        }
    }

    func testPackEventUsesDifferentRecordOffsetAndLength() throws {
        var inner = [UInt8](repeating: 0, count: 12)
        inner[0] = 48
        inner[2] = 109
        Synthetic.put(&inner, 4, UInt32(1_790_000_000))
        Synthetic.put(&inner, 8, UInt16(16384))
        Synthetic.put(&inner, 10, UInt16(28))
        guard case let .event(event) = try FrameDecoder.decode(Synthetic.envelope(inner + record())),
              case let .batteryPack(pack) = event.payload else { return XCTFail() }
        XCTAssertEqual(pack.percent, 64.2)
        XCTAssertEqual(event.timestamp, 1_790_000_000.5)
        XCTAssertEqual(pack.identifier, [1, 2, 3, 4, 5, 6])
        // Never recover a truncated record by reading padding or CRC bytes.
        guard case let .event(short) = try FrameDecoder.decode(Synthetic.envelope(inner + record().prefix(24))) else { return XCTFail() }
        if case .batteryPack = short.payload { XCTFail("accepted truncated record") }
        Synthetic.put(&inner, 10, UInt16(27))
        guard case let .event(wrongLength) = try FrameDecoder.decode(Synthetic.envelope(inner + record())) else { return XCTFail() }
        if case .batteryPack = wrongLength.payload { XCTFail("accepted wrong payload version") }
    }

    func testInvalidPresenceScaleAndRevisionAreNotPercentages() throws {
        XCTAssertNil(BatteryPackInfo(record: record(present: 2)))
        XCTAssertNil(BatteryPackInfo(record: record(charge: 1001))?.percent)
        XCTAssertNil(BatteryPackInfo(record: record(present: 0))?.percent)
        XCTAssertEqual(BatteryPackInfo(record: record(charge: 0))?.percent, 0)
        XCTAssertEqual(BatteryPackInfo(record: record(charge: 1000))?.percent, 100)
        let body = [UInt8(2)] + record().prefix(27)
        guard case let .commandResponse(reply) = try FrameDecoder.decode(Synthetic.envelope([36, 1, 151, 9, 1] + body)) else { return XCTFail() }
        XCTAssertNil(reply.batteryPack)
    }

    func testAttachmentDoesNotMeanCharging() throws {
        for (code, present) in [(UInt8(21), true), (22, false)] {
            var inner = [UInt8](repeating: 0, count: 12)
            inner[0] = 48
            inner[2] = code
            guard case let .event(event) = try FrameDecoder.decode(Synthetic.envelope(inner)) else { return XCTFail() }
            XCTAssertEqual(event.payload, .packPresence(present))
        }
    }
}
