import Foundation
import XCTest
import ZoopProtocol
@testable import ZoopECG

final class ECGCaptureTests: XCTestCase {
    private func frame(index: UInt8 = 1, live: Bool = true, raw: Bool = false, samples: [Int16] = [12, -4, 0]) -> Data {
        var body = [UInt8](repeating: 0, count: raw ? 1572 : 228)
        body[0] = live ? 43 : 47; body[1] = raw ? 16 : 17; body[3] = index
        if !raw {
            body[24] = UInt8(samples.count)
            for (i, value) in samples.enumerated() {
                let bits = UInt16(bitPattern: value); body[26 + i * 2] = UInt8(bits & 255); body[27 + i * 2] = UInt8(bits >> 8)
            }
        }
        return Data(Frame.encode(inner: body, destination: 1, source: 0))
    }
    func testHistoryAndEmptySamplesDoNotStartTimerAndExactDuplicatesIgnored() throws {
        var buffer = ECGBuffer(); let at = Date()
        XCTAssertFalse(try buffer.receive(frame(live: false), at: at, uptime: 100))
        try buffer.receive(frame(samples: []), at: at, uptime: 101)
        XCTAssertNil(buffer.firstSampleUptime)
        let bytes = frame(index: 2)
        XCTAssertTrue(try buffer.receive(bytes, at: at, uptime: 102))
        XCTAssertFalse(try buffer.receive(bytes, at: at, uptime: 104))
        XCTAssertEqual(buffer.firstSampleUptime, 102); XCTAssertEqual(buffer.lastSampleUptime, 102)
        XCTAssertEqual(buffer.filteredSamples, [12, -4, 0])
    }
    func testLayoutsMayShareSequenceAndCountedZerosAreRetained() throws {
        var buffer = ECGBuffer(); let at = Date()
        try buffer.receive(frame(raw: true), at: at, uptime: 99)
        try buffer.receive(frame(samples: [0, 0, 0]), at: at, uptime: 100)
        XCTAssertEqual(buffer.frames.count, 2); XCTAssertEqual(buffer.filteredSamples, [0, 0, 0])
        XCTAssertEqual(buffer.elapsed(at: 105), 5)
        XCTAssertTrue(buffer.isStale(at: 106))
        XCTAssertThrowsError(try buffer.receive(frame(index: 2), at: at, uptime: 106))
    }
    func testMalformedFrameCannotAdvanceCapture() throws {
        var buffer = ECGBuffer(); var bytes = frame(); bytes[34] ^= 1
        XCTAssertThrowsError(try buffer.receive(bytes, at: Date(), uptime: 1))
        XCTAssertTrue(buffer.frames.isEmpty); XCTAssertNil(buffer.firstSampleUptime)
    }
    func testJournalRoundTripDeviceIsolationAndCleanupSurvivesRestart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let journal = ECGJournal(directory: dir)
        var cleanup = ECGCleanup(device: "TEST-MG"); cleanup.generation = true; cleanup.rawLive = true; cleanup.filteredLive = true
        try await journal.setPending(cleanup)
        let reopened = ECGJournal(directory: dir)
        let pending = try await reopened.pending()
        XCTAssertEqual(pending.first?.operations, [.generation(false), .filteredLive(false), .rawLive(false)])
        let recording = ECGRecording(device: "TEST-MG", firmware: nil, wrist: .left, startedAt: Date(), duration: 30,
            frames: [.init(bytes: frame(), receivedAt: Date(), elapsed: 0)])
        try await journal.save(recording)
        let loaded = try await reopened.recording(id: recording.id)
        XCTAssertEqual(recording, loaded); XCTAssertEqual(loaded.filteredSamples, [12, -4, 0])
        let ours = try await reopened.summaries(device: "TEST-MG"), other = try await reopened.summaries(device: "OTHER")
        XCTAssertEqual(ours.count, 1); XCTAssertTrue(other.isEmpty)
        for op in cleanup.operations { cleanup.acknowledge(op) }
        try await reopened.setPending(cleanup)
        let cleared = try await journal.pending(); XCTAssertTrue(cleared.isEmpty)
    }
    func testCorruptCleanupDoesNotSilentlyBecomeSafe() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("broken".utf8).write(to: dir.appendingPathComponent("cleanup.json"))
        do { _ = try await ECGJournal(directory: dir).pending(); XCTFail("Must fail closed") } catch { }
    }
}
