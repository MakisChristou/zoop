import XCTest
import SQLite3
@testable import ZoopSync

private final class Transport: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ReliabilityTests: XCTestCase {
    private var directory: URL!
    private var path: URL { directory.appendingPathComponent("queue.sqlite") }
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Transport.self]
        return URLSession(configuration: config)
    }
    private func flush(_ uploader: Uploader) async -> Uploader.Stats {
        await uploader.flush(deviceId: "TEST", model: "MG", firmware: nil,
                             baseURL: URL(string: "https://example.test")!, token: "test")
    }
    private func response(_ rows: [FrameQueue.Row], statuses: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["results": zip(rows, statuses).map { row, status -> [String: Any] in
            ["client_seq": row.clientSeq, "upload_id": row.uploadId as Any? ?? NSNull(), "status": status]
        }])
    }
    func testLegacyMigrationAndReopenPreserveIdentityAndBytes() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(path.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, """
            CREATE TABLE frames(id INTEGER PRIMARY KEY AUTOINCREMENT,client_seq INTEGER UNIQUE NOT NULL,channel INTEGER NOT NULL,received_at REAL NOT NULL,bytes BLOB NOT NULL);
            CREATE TABLE counters(name TEXT PRIMARY KEY,value INTEGER NOT NULL);
            INSERT INTO counters VALUES('client_seq',42);
            INSERT INTO frames(client_seq,channel,received_at,bytes) VALUES(42,5,123,X'00FF10');
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        var queue: FrameQueue? = try FrameQueue(path: path)
        XCTAssertEqual(try queue!.enqueue([7, 8], channel: 4), 43)
        let before = try queue!.peek(limit: 10)
        XCTAssertNil(before[0].uploadId)
        XCTAssertEqual(before[0].bytes, [0, 255, 16])
        XCTAssertNotNil(UUID(uuidString: before[1].uploadId!))
        queue = nil
        let reopened = try FrameQueue(path: path)
        let after = try reopened.peek(limit: 10)
        XCTAssertEqual(after.map(\.uploadId), before.map(\.uploadId))
        XCTAssertEqual(after.map(\.bytes), before.map(\.bytes))
        let fresh = try FrameQueue(path: directory.appendingPathComponent("fresh.sqlite"))
        try fresh.enqueue([7, 8], channel: 4)
        XCTAssertNotEqual(try fresh.peek(limit: 1)[0].uploadId, before[1].uploadId)
    }
    func testMixedReceiptsRetainRejectedFramesWithoutBlockingLaterData() async throws {
        let queue = try FrameQueue(path: path)
        for i in 0..<4 { try queue.enqueue([UInt8(i)], channel: 5) }
        try queue.bind(sourceID: "TEST-SOURCE", deviceID: "TEST", adoptLegacy: true)
        let rows = try queue.peek(limit: 10)
        Transport.handler = { request in
            XCTAssertEqual(request.url!.path, "/v2/ingest")
            return (200, try self.response(rows, statuses: ["stored", "duplicate", "rejected", "conflict"]))
        }
        let uploader = Uploader(queue: queue, session: session())
        let stats = await flush(uploader)
        XCTAssertEqual(stats.accepted, 1); XCTAssertEqual(stats.duplicates, 1); XCTAssertEqual(stats.rejected, 2)
        XCTAssertEqual(try queue.count(), 2); XCTAssertEqual(try queue.heldCount(), 2)
        XCTAssertTrue(try queue.peek(limit: 10).isEmpty)
        try queue.enqueue([99], channel: 4)
        XCTAssertEqual(try queue.peek(limit: 10).map(\.bytes), [[99]])
        try queue.retryHeld()
        XCTAssertEqual(try queue.peek(limit: 10).prefix(2).map(\.uploadId), rows.suffix(2).map(\.uploadId))
    }
    func testLostResponseRetriesSameIdentityAndDuplicateReceiptRemovesIt() async throws {
        let queue = try FrameQueue(path: path); try queue.enqueue([1, 2, 3], channel: 5)
        try queue.bind(sourceID: "TEST-SOURCE", deviceID: "TEST", adoptLegacy: true)
        let rows = try queue.peek(limit: 10)
        let uploader = Uploader(queue: queue, session: session())
        Transport.handler = { _ in throw URLError(.networkConnectionLost) }
        let failed = await flush(uploader); XCTAssertNotNil(failed.lastError)
        XCTAssertEqual(try queue.peek(limit: 1)[0].uploadId, rows[0].uploadId)
        Transport.handler = { _ in (200, try self.response(rows, statuses: ["duplicate"])) }
        let retried = await flush(uploader); XCTAssertEqual(retried.duplicates, 1)
        XCTAssertEqual(try queue.count(), 0)
    }
    func testPartialDuplicateUnknownAndWrongIdentityReceiptsNeverDeleteBatch() async throws {
        let queue = try FrameQueue(path: path)
        try queue.enqueue([1], channel: 5); try queue.enqueue([2], channel: 5)
        try queue.bind(sourceID: "TEST-SOURCE", deviceID: "TEST", adoptLegacy: true)
        let rows = try queue.peek(limit: 10)
        let uploader = Uploader(queue: queue, session: session())
        let cases: [Data] = [
            try response([rows[0]], statuses: ["stored"]),
            try response([rows[0], rows[0]], statuses: ["stored", "stored"]),
            try response(rows, statuses: ["stored", "mystery"]),
            Data("{\"accepted\":2,\"duplicates\":0,\"rejected\":0}".utf8),
            try JSONSerialization.data(withJSONObject: ["results": rows.map { ["client_seq": $0.clientSeq, "upload_id": "wrong", "status": "stored"] as [String: Any] }])
        ]
        for data in cases {
            Transport.handler = { _ in (200, data) }
            let stats = await flush(uploader)
            XCTAssertNotNil(stats.lastError)
            XCTAssertEqual(try queue.count(), 2)
            XCTAssertEqual(try queue.heldCount(), 0)
        }
    }
    func testRedirectResponsesPreserveQueuedFramesForRetry() async throws {
        let queue = try FrameQueue(path: path)
        try queue.enqueue([1, 2, 3], channel: 5)
        try queue.bind(sourceID: "TEST-SOURCE", deviceID: "TEST", adoptLegacy: true)
        let identity = try queue.peek(limit: 1)[0].uploadId
        for code in [301, 302, 303, 307, 308] {
            Transport.handler = { _ in (code, Data()) }
            let stats = await flush(Uploader(queue: queue, session: session()))
            XCTAssertEqual(stats.lastError, "HTTP \(code)")
            XCTAssertEqual(try queue.count(), 1)
            XCTAssertEqual(try queue.peek(limit: 1)[0].uploadId, identity)
            XCTAssertEqual(try queue.peek(limit: 1)[0].bytes, [1, 2, 3])
        }
    }
    func testUnavailableV2DoesNotFallBackOrDiscard() async throws {
        let queue = try FrameQueue(path: path); try queue.enqueue([1], channel: 5)
        try queue.bind(sourceID: "TEST-SOURCE", deviceID: "TEST", adoptLegacy: true)
        Transport.handler = { _ in (404, Data()) }
        let stats = await flush(Uploader(queue: queue, session: session()))
        XCTAssertEqual(stats.lastError, "HTTP 404"); XCTAssertEqual(try queue.count(), 1)
    }
    @MainActor func testDeletionStopRefusesFailedWritesAndRetryPreservesTheFrame() async throws {
        let state = WriterState()
        let saved = expectation(description: "pending recording saved after retry")
        let writer = FrameWriter(save: { bytes, _, _, _ in try state.save(bytes[0]) },
            onFailure: { _ in }, onRecovery: {})
        writer.enqueue([42], channel: 5) { saved.fulfill() }
        do { try await writer.stop(); XCTFail("Deletion must stop if a recording cannot be saved") }
        catch { XCTAssertTrue(state.saved.isEmpty) }
        state.allowWrites()
        writer.retry()
        await fulfillment(of: [saved], timeout: 3)
        try await writer.stop()
        XCTAssertEqual(state.saved, [42])
    }

    @MainActor func testDiskFailureWithholdsHistoryEndUntilAllEarlierFramesAreSaved() async throws {
        let failed = expectation(description: "disk failure")
        let recovered = expectation(description: "recovered")
        let saved = expectation(description: "saved callbacks"); saved.expectedFulfillmentCount = 3
        let state = WriterState()
        let writer = FrameWriter(save: { bytes, _, _, _ in try state.save(bytes[0]) }, onFailure: { _ in failed.fulfill() }, onRecovery: { recovered.fulfill() })
        var acknowledgements: [UInt8] = []
        for value: UInt8 in [1, 2, 3] {
            writer.enqueue([value], channel: 5) { acknowledgements.append(value); saved.fulfill() }
        }
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertTrue(acknowledgements.isEmpty, "A history-end callback must not pass a failed earlier write")
        state.allowWrites()
        writer.retry()
        await fulfillment(of: [saved, recovered], timeout: 3)
        XCTAssertEqual(acknowledgements, [1, 2, 3]); XCTAssertEqual(state.saved, [1, 2, 3])
    }
}
private final class WriterState: @unchecked Sendable {
    private let lock = NSLock(); private var failing = true
    private(set) var saved: [UInt8] = []
    func allowWrites() { lock.lock(); failing = false; lock.unlock() }
    func save(_ value: UInt8) throws {
        lock.lock(); defer { lock.unlock() }
        if failing { throw QueueError.sql("disk full") }; saved.append(value)
    }
}
