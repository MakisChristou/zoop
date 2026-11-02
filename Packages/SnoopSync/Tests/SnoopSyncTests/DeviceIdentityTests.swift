import XCTest
@testable import SnoopSync

final class DeviceIdentityTests: XCTestCase {
    func testBacklogStaysWithOriginalDeviceAcrossReopen() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("queue.sqlite")
        var queue: FrameQueue? = try FrameQueue(path: path)
        try queue!.enqueue([1], channel: 5, sourceID: "peripheral-a")
        try queue!.enqueue([2], channel: 5, sourceID: "peripheral-b")
        try queue!.enqueue([3], channel: 5) // Pre-upgrade identity is unknown.
        try queue!.bind(sourceID: "peripheral-a", deviceID: "serial-a")
        try queue!.bind(sourceID: "peripheral-b", deviceID: "serial-b")
        XCTAssertEqual(try queue!.peek(limit: 10, deviceID: "serial-a").map(\.bytes), [[1]])
        XCTAssertEqual(try queue!.peek(limit: 10, deviceID: "serial-b").map(\.bytes), [[2]])
        XCTAssertThrowsError(try queue!.bind(sourceID: "peripheral-a", deviceID: "serial-b"))
        queue = nil
        let reopened = try FrameQueue(path: path)
        XCTAssertEqual(try reopened.count(), 3)
        XCTAssertEqual(try reopened.unassignedCount(), 1)
        XCTAssertEqual(try reopened.peek(limit: 10, deviceID: "serial-b").map(\.bytes), [[2]])
        let originalIDs = try reopened.peek(limit: 10).map(\.uploadId)
        // Explicit owner-confirmed recovery must only assign previously unscoped rows.
        try reopened.bind(sourceID: "peripheral-a", deviceID: "serial-a", adoptLegacy: true)
        XCTAssertEqual(try reopened.unassignedCount(), 0)
        XCTAssertEqual(try reopened.peek(limit: 10, deviceID: "serial-a").map(\.bytes), [[1],[3]])
        XCTAssertEqual(try reopened.peek(limit: 10, deviceID: "serial-b").map(\.bytes), [[2]])
        XCTAssertEqual(try reopened.peek(limit: 10).map(\.uploadId), originalIDs)
    }
}
