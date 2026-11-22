import XCTest
import ZoopProtocol
@testable import Zoop

final class LiveHeartRateTests: XCTestCase {
    @MainActor
    func testHistoryIsStoredWithoutReplacingLiveReading() {
        let strap = StrapManager()
        var stored: [[UInt8]] = []
        strap.onFrame = { bytes, _, saved in stored.append(bytes); saved() }
        let live = biometric(type: PacketType.realtimeRawDataByte, bpm: 65)
        let history = biometric(type: PacketType.historicalDataByte, bpm: 61)
        strap.handle(frame: live, channel: 5)
        let receivedAt = strap.liveUpdatedAt
        XCTAssertEqual(strap.smoothedHeartRate, 65)
        strap.handle(frame: history, channel: 5)
        XCTAssertEqual(stored, [live, history])
        XCTAssertEqual(strap.liveHeartRate, 65)
        XCTAssertEqual(strap.smoothedHeartRate, 65)
        XCTAssertEqual(strap.liveUpdatedAt, receivedAt)
        XCTAssertEqual(strap.lastBiometric?.heartRate, 65)
    }

    @MainActor
    func testReadingWaitsForDurableReceipt() {
        let strap = StrapManager()
        var receipt: (() -> Void)?
        strap.onFrame = { _, _, saved in receipt = saved }
        strap.handle(frame: biometric(type: PacketType.realtimeRawDataByte, bpm: 65), channel: 5)
        XCTAssertNil(strap.liveHeartRate)
        receipt?()
        XCTAssertEqual(strap.liveHeartRate, 65)
    }

    @MainActor
    func testHistoryAloneDoesNotCreateLiveValue() {
        let strap = StrapManager()
        strap.onFrame = { _, _, saved in saved() }
        strap.handle(frame: biometric(type: PacketType.historicalDataByte, bpm: 61), channel: 5)
        XCTAssertNil(strap.liveHeartRate)
        XCTAssertNil(strap.liveUpdatedAt)
        XCTAssertNil(strap.lastBiometric)
    }

    private func biometric(type: UInt8, bpm: UInt8) -> [UInt8] {
        var inner = [UInt8](repeating: 0, count: 112)
        inner[0] = type
        inner[1] = Layout.biometricByte
        inner[Biometric.heartRateOffset - Frame.headerLength] = bpm
        return Frame.encode(inner: inner, destination: 1, source: 0)
    }
}
