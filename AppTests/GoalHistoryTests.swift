import XCTest

@testable import Zoop

private actor HistoryGate {
    var continuation: CheckedContinuation<ZoopAPI.GoalHistory, Never>?
    func wait() async -> ZoopAPI.GoalHistory { await withCheckedContinuation { continuation = $0 } }
    func waiting() -> Bool { continuation != nil }
    func finish(_ result: ZoopAPI.GoalHistory) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor final class GoalHistoryTests: XCTestCase {
    private func goal(active: Bool = true) -> ZoopAPI.WeightGoal {
        .init(
            id: 42, revision: 2, active: active, startedAt: Date(), paceStartedAt: Date(),
            timezone: "UTC", weeklyLossKg: 0.3, reminderEnabled: false, reminderWeekday: 1,
            reminderMinute: 1200, finishDate: "2099-01-01", updatedAt: Date())
    }
    private func period(id: Int64 = 42, current: Double? = 63.9, target: Double? = 61.9)
        -> ZoopAPI.GoalPeriod
    {
        .init(
            id: id, goal: goal(), endedAt: Date(), endReason: "manual",
            summary: .init(
                algorithmVersion: 1, start: "2026-11-01", end: "2026-11-07", provisional: false,
                state: "starting", reason: "", medianKg: nil, changeKg: nil, weeklyLossKg: 0.3,
                count: 2, weekNumber: 1, weeks: [],
                progress: .init(
                    finishDate: "2099-01-01", weeksRemaining: 0, completed: true,
                    startingWeightKg: 64.6, currentWeightKg: current,
                    totalLostKg: current.map { 64.6 - $0 }, targetWeightKg: target)))
    }
    func testHistoryResponseCannotCrossAccountBoundary() async {
        let gate = HistoryGate()
        let item = period()
        let store = WeeklyWeightStore(
            loader: { _ in .init(goal: nil, summary: nil) },
            historyLoader: { _, _ in await gate.wait() })
        store.activate(device: "a", scope: "a")
        let pending = Task { await store.reloadHistory() }
        while !(await gate.waiting()) { await Task.yield() }
        store.activate(device: "", scope: nil)
        await gate.finish(.init(items: [item], nextCursor: 42))
        await pending.value
        XCTAssertTrue(store.history.isEmpty)
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.historyLoading)
    }
    func testEndingInvalidatesAnOlderHistoryRequest() async throws {
        let gate = HistoryGate()
        let active = goal()
        let ended = goal(active: false)
        let store = WeeklyWeightStore(
            loader: { _ in .init(goal: active, summary: nil) }, saver: { _, _ in ended },
            historyLoader: { _, _ in await gate.wait() })
        store.activate(device: "a", scope: "test-\(UUID())")
        await store.reload()
        let pending = Task { await store.reloadHistory() }
        while !(await gate.waiting()) { await Task.yield() }
        try await store.save(
            .init(
                revision: 2, active: false, timezone: "UTC", weeklyLossKg: 0.3,
                reminderEnabled: false, reminderWeekday: 1, reminderMinute: 1200))
        await gate.finish(.init(items: [], nextCursor: 999))
        await pending.value
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.historyLoaded)
        XCTAssertFalse(store.historyLoading)
        store.activate(device: "", scope: nil)
    }
    func testPagingDeduplicatesAndFailureRetainsHistory() async {
        let item = period()
        let next = period(id: 43)
        let store = WeeklyWeightStore(
            loader: { _ in .init(goal: nil, summary: nil) },
            historyLoader: { _, cursor in
                if cursor == nil { return .init(items: [item], nextCursor: 42) }
                if cursor == 42 { return .init(items: [item, next], nextCursor: 43) }
                throw URLError(.notConnectedToInternet)
            })
        store.activate(device: "a", scope: "test-\(UUID())")
        await store.reloadHistory()
        await store.reloadHistory(more: true)
        XCTAssertEqual(store.history.map(\.id), [42, 43])
        await store.reloadHistory(more: true)
        XCTAssertEqual(store.history.count, 2)
        XCTAssertNotNil(store.historyError)
        XCTAssertEqual(store.nextCursor, 43)
        store.activate(device: "", scope: nil)
    }
    func testOutcomesDoNotInventSuccessFromMissingWeights() {
        XCTAssertEqual(period(current: nil).outcome, "No weigh-ins")
        XCTAssertEqual(period(current: 61.8).outcome, "Target reached")
        XCTAssertEqual(period(current: 63.9).outcome, "Ended early")
        XCTAssertEqual(period(current: 63.9, target: nil).outcome, "Ended early")
    }
}
