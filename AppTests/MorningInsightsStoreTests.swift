import XCTest
@testable import Snoop

@MainActor final class MorningInsightsStoreTests: XCTestCase {
    private var today: Date { Date(timeIntervalSince1970: 1_793_664_000) }
    private func scope(_ device: String = "TEST", day: Date? = nil, connection: String = "test") -> MorningInsightsStore.Scope {
        .init(device: device, day: day ?? today, connection: connection, timezone: "UTC")
    }
    private func response(_ state: String, day: String = "2026-11-03") throws -> MorningInsights {
        let json = """
        {"version":2,"day":"\(day)","timezone":"UTC","state":"\(state)","sleepId":1,"sleepRevision":1,
         "metrics":[],"observations":[],"timing":{"count":0},
         "outlook":{"state":"\(state == "ready" ? "learning" : state)","baselineCount":10,"baselineRequired":14}}
        """
        return try JSONDecoder().decode(MorningInsights.self, from: Data(json.utf8))
    }

    func testUpdatingAutomaticallyBecomesReadyWithoutReloadingToday() async throws {
        let pending = try response("updating"), ready = try response("ready")
        var calls = 0, delays: [Duration] = []
        let store = MorningInsightsStore(fetch: { _, _ in calls += 1; return calls == 1 ? pending : ready }, sleep: {
            delays.append($0)
            if delays.count == 2 { throw CancellationError() }
        })
        await store.follow(scope())
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(delays, [.seconds(5), .seconds(300)])
        XCTAssertEqual(store.value?.state, "ready"); XCTAssertEqual(store.value?.outlookTitle, "Learning")
    }

    func testErrorReplacesStaleUpdatingAndRetries() async throws {
        let pending = try response("updating"), ready = try response("ready")
        var calls = 0, delays: [Duration] = []
        let store = MorningInsightsStore(fetch: { _, _ in
            calls += 1
            if calls == 2 { throw URLError(.notConnectedToInternet) }
            return calls == 1 ? pending : ready
        }, sleep: {
            delays.append($0)
            if delays.count == 3 { throw CancellationError() }
        })
        await store.follow(scope())
        XCTAssertEqual(delays, [.seconds(5), .seconds(15), .seconds(300)])
        XCTAssertEqual(store.value?.state, "ready"); XCTAssertFalse(store.failed)
    }

    func testFailureCannotLeaveUpdatingLabelVisible() async throws {
        let pending = try response("updating"); var calls = 0
        let store = MorningInsightsStore(fetch: { _, _ in
            calls += 1
            if calls > 1 { throw URLError(.timedOut) }
            return pending
        })
        await store.reload(scope()); await store.reload(scope())
        XCTAssertNil(store.value); XCTAssertTrue(store.failed); XCTAssertFalse(store.loading)
    }

    func testUploadReturningUpdatingInterruptsSettledWait() async throws {
        let ready = try response("ready"), pending = try response("updating")
        let settled = expectation(description: "Waiting at the settled cadence")
        let shortened = expectation(description: "Pending update shortens the wait")
        var calls = 0, delays: [Duration] = []
        let store = MorningInsightsStore(fetch: { _, _ in
            calls += 1; return calls == 1 ? ready : pending
        }, sleep: {
            delays.append($0)
            if delays.count == 1 {
                settled.fulfill()
                try await Task.sleep(for: .seconds(300))
            } else {
                shortened.fulfill(); throw CancellationError()
            }
        })
        let task = Task { await store.follow(self.scope()) }
        await fulfillment(of: [settled], timeout: 1)
        await store.reload(scope())
        await fulfillment(of: [shortened], timeout: 1)
        task.cancel(); await task.value
        XCTAssertEqual(delays, [.seconds(300), .seconds(5)])
        XCTAssertEqual(store.value?.state, "updating")
    }

    func testOldDateOrConnectionCannotReplaceNewResult() async throws {
        let old = try response("updating", day: "2026-11-02"), current = try response("ready")
        let store = MorningInsightsStore(fetch: { device, _ in
            if device == "OLD" { try? await Task.sleep(for: .milliseconds(80)); return old }
            return current
        })
        let task = Task { await store.reload(self.scope("OLD", day: self.today.addingTimeInterval(-86400), connection: "old")) }
        try await Task.sleep(for: .milliseconds(10))
        await store.reload(scope(connection: "new")); await task.value
        XCTAssertEqual(store.value?.day, "2026-11-03"); XCTAssertEqual(store.value?.state, "ready")
        XCTAssertNil(store.value(for: scope(connection: "old")))
        XCTAssertNotNil(store.value(for: scope(connection: "new")))
    }

    func testStopFencesInflightResultAndDoesNotScheduleAnotherPoll() async throws {
        let pending = try response("updating"); var waits = 0
        let store = MorningInsightsStore(fetch: { _, _ in try? await Task.sleep(for: .milliseconds(80)); return pending }, sleep: { _ in waits += 1 })
        let task = Task { await store.follow(self.scope()) }
        try await Task.sleep(for: .milliseconds(10)); store.stop(); await task.value
        XCTAssertNil(store.value); XCTAssertEqual(waits, 0); XCTAssertFalse(store.loading)
    }

    func testForegroundStartsWithImmediateFetch() async throws {
        let pending = try response("updating"), ready = try response("ready"); var calls = 0
        let store = MorningInsightsStore(fetch: { _, _ in calls += 1; return calls == 1 ? pending : ready }, sleep: { _ in throw CancellationError() })
        await store.follow(scope()); store.stop()
        XCTAssertEqual(store.value?.state, "updating")
        await store.follow(scope())
        XCTAssertEqual(calls, 2); XCTAssertEqual(store.value?.state, "ready")
    }

    func testScopeInvalidationAndCancellationCannotPublish() async throws {
        let ready = try response("ready"); var isCurrent = true
        let store = MorningInsightsStore(fetch: { _, _ in try? await Task.sleep(for: .milliseconds(60)); return ready })
        let task = Task { await store.reload(self.scope(), isCurrent: { isCurrent }) }
        try await Task.sleep(for: .milliseconds(10)); isCurrent = false; await task.value
        XCTAssertNil(store.value)
        let cancelled = Task { await store.reload(self.scope()) }
        try await Task.sleep(for: .milliseconds(10)); cancelled.cancel(); await cancelled.value
        XCTAssertNil(store.value)
    }

    func testCancelledSupersedingRequestDoesNotSettleAnEmptyBrief() async throws {
        let ready = try response("ready")
        let firstStarted = expectation(description: "Monitor fetch started")
        let secondStarted = expectation(description: "History refresh superseded it")
        var calls = 0, delays: [Duration] = []
        let store = MorningInsightsStore(fetch: { _, _ in
            calls += 1
            if calls == 1 {
                firstStarted.fulfill()
                try await Task.sleep(for: .milliseconds(100))
            } else {
                secondStarted.fulfill()
                try await Task.sleep(for: .seconds(5))
            }
            return ready
        }, sleep: { delays.append($0); throw CancellationError() })
        let monitor = Task { await store.follow(self.scope()) }
        await fulfillment(of: [firstStarted], timeout: 1)
        let refresh = Task { await store.reload(self.scope()) }
        await fulfillment(of: [secondStarted], timeout: 1)
        refresh.cancel(); await refresh.value; await monitor.value
        XCTAssertNil(store.value)
        XCTAssertEqual(delays, [.seconds(15)])
        XCTAssertFalse(store.loading)
    }
}
