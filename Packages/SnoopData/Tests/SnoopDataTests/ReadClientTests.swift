import XCTest
@testable import SnoopData

private actor Transport {
    var calls = 0
    func load(_ request: URLRequest) async throws -> ReadClient.Response {
        calls += 1
        let count = calls
        try await Task.sleep(for: .milliseconds(40))
        return .init(data: Data(String(count).utf8), response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
final class ReadClientTests: XCTestCase {
    private func request(_ token: String = "one", path: String = "days") -> URLRequest {
        var r = URLRequest(url: URL(string: "https://example.test/" + path)!)
        r.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); return r
    }
    func testCoalescesAndCachesThenInvalidates() async throws {
        let transport = Transport(), req = request()
        let client = ReadClient(transport: { try await transport.load($0) })
        async let a = client.data(for: req, maxAge: 60)
        async let b = client.data(for: req, maxAge: 60)
        let (first, second) = try await (a,b)
        XCTAssertEqual(first.data, second.data)
        let cached = try await client.data(for: req, maxAge: 60)
        XCTAssertEqual(first.data, cached.data)
        let count = await transport.calls; XCTAssertEqual(count, 1)
        await client.invalidate()
        let next = try await client.data(for: req, maxAge: 60)
        XCTAssertNotEqual(next.data, first.data)
    }
    func testOneCancelledSubscriberDoesNotCancelAnother() async throws {
        let transport = Transport(), req = request()
        let client = ReadClient(transport: { try await transport.load($0) })
        let a = Task { try await client.data(for: req, maxAge: 60) }
        let b = Task { try await client.data(for: req, maxAge: 60) }
        try await Task.sleep(for: .milliseconds(10)); a.cancel()
        do { _ = try await a.value; XCTFail("Cancelled caller must not receive data") } catch { }
        _ = try await b.value
        let count = await transport.calls; XCTAssertEqual(count, 1)
    }
    func testInvalidatedRequestCannotRepopulateCache() async throws {
        let transport = Transport(), req = request()
        let client = ReadClient(transport: { try await transport.load($0) })
        let task = Task { try await client.data(for: req, maxAge: 60) }
        try await Task.sleep(for: .milliseconds(10)); await client.invalidate()
        do { _ = try await task.value; XCTFail("Old generation must be discarded") } catch { }
        _ = try await client.data(for: req, maxAge: 60)
        let count = await transport.calls; XCTAssertEqual(count, 2)
    }
    func testScopesByCredentialsAndBoundsCache() async throws {
        let transport = Transport()
        let client = ReadClient(capacity: 1, transport: { try await transport.load($0) })
        let first = try await client.data(for: request(), maxAge: 60)
        let other = try await client.data(for: request("two"), maxAge: 60)
        XCTAssertNotEqual(first.data, other.data)
        _ = try await client.data(for: request(), maxAge: 60)
        let count = await transport.calls; XCTAssertEqual(count, 3)
    }
}
