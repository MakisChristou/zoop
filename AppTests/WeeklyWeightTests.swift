import XCTest
import UserNotifications
@testable import Zoop

@MainActor private final class WeeklyResponseSlot { var continuation: CheckedContinuation<ZoopAPI.WeeklyWeightResponse, Never>? }

@MainActor final class WeeklyWeightTests: XCTestCase {
    private var requests: [String: UNNotificationRequest] = [:]
    private var permission = UNAuthorizationStatus.authorized
    private var added = 0
    private var beforeAdd: (() async -> Void)?
    private let response = WeeklyResponseSlot()
    private func scheduler() -> WeeklyWeightReminder {
        WeeklyWeightReminder(center: .init(authorization: { self.permission }, pending: { Array(self.requests.values) }, delivered: { [] }, add: { request in
            await self.beforeAdd?(); self.added += 1; self.requests[request.identifier] = request
        }, removePending: { ids in for id in ids { self.requests.removeValue(forKey: id) } }, removeDelivered: { _ in }))
    }
    private func goal(active: Bool = true, reminder: Bool = true, rate: Double = 0.3) -> ZoopAPI.WeightGoal {
        .init(revision: 1, active: active, startedAt: Date(), paceStartedAt: Date(), timezone: "Europe/Berlin", weeklyLossKg: rate, reminderEnabled: reminder, reminderWeekday: 1, reminderMinute: 1200, updatedAt: Date())
    }
    func testWeeklyScheduleIsScopedRepeatingAndIdempotent() async {
        let scheduler = scheduler(), goal = goal()
        scheduler.update(goal: goal, scope: "account-a"); await scheduler.settled()
        let note = requests.values.first!
        let trigger = note.trigger as! UNCalendarNotificationTrigger
        XCTAssertTrue(trigger.repeats); XCTAssertEqual(trigger.dateComponents.weekday, 1)
        XCTAssertEqual(trigger.dateComponents.hour, 20); XCTAssertEqual(trigger.dateComponents.minute, 0)
        XCTAssertEqual(trigger.dateComponents.timeZone?.identifier, "Europe/Berlin")
        XCTAssertEqual(note.content.userInfo["destination"] as? String, "weeklyWeight")
        scheduler.update(goal: goal, scope: "account-a"); await scheduler.settled(); XCTAssertEqual(added, 1)
        scheduler.update(goal: goal, scope: "account-b"); await scheduler.settled()
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests.values.first?.content.userInfo["scope"] as? String, "account-b")
    }
    func testDeniedDisabledPausedAndLogoutCancelOnlyWeeklyRequests() async {
        let scheduler = scheduler()
        requests["snoop.battery.test"] = .init(identifier: "snoop.battery.test", content: UNMutableNotificationContent(), trigger: nil)
        for (goal, scope) in [(goal(active: false), "a" as String?), (goal(reminder: false), "a"), (goal(), nil)] {
            scheduler.update(goal: self.goal(), scope: "a"); await scheduler.settled()
            scheduler.update(goal: goal, scope: scope); await scheduler.settled()
            XCTAssertEqual(Set(requests.keys), ["snoop.battery.test"])
        }
        permission = .denied; scheduler.update(goal: goal(), scope: "a"); await scheduler.settled()
        XCTAssertEqual(Set(requests.keys), ["snoop.battery.test"])
    }
    func testPauseDuringSuspendedSchedulingLeavesNoOldRequest() async {
        let scheduler = scheduler()
        var resume: CheckedContinuation<Void, Never>?
        beforeAdd = { await withCheckedContinuation { resume = $0 } }
        scheduler.update(goal: goal(), scope: "a")
        while resume == nil { await Task.yield() }
        scheduler.update(goal: goal(active: false), scope: "a")
        beforeAdd = nil; resume?.resume(); await scheduler.settled()
        XCTAssertTrue(requests.isEmpty)
    }
    func testStoreRejectsOldAccountResponseAndSaveFailurePreservesGoal() async {
        let domain = "WeeklyWeightTests.\(UUID())"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let goal = goal()
        let response = response
        let store = WeeklyWeightStore(defaults: defaults, reminder: scheduler(), loader: { _ in
            await withCheckedContinuation { continuation in Task { @MainActor in response.continuation = continuation } }
        }, saver: { _, _ in throw URLError(.notConnectedToInternet) })
        store.activate(device: "first", scope: "a")
        let fetch = Task { await store.reload() }
        while response.continuation == nil { await Task.yield() }
        store.activate(device: "", scope: nil)
        response.continuation?.resume(returning: .init(goal: goal, summary: nil)); await fetch.value
        XCTAssertNil(store.goal); XCTAssertNil(store.summary)
        let ready = WeeklyWeightStore(defaults: defaults, reminder: scheduler(), loader: { _ in .init(goal: goal, summary: nil) }, saver: { _, _ in throw URLError(.notConnectedToInternet) })
        ready.activate(device: "second", scope: "b"); await ready.reload()
        do { try await ready.save(.init(revision: 1, active: true, timezone: "UTC", weeklyLossKg: 0.4, reminderEnabled: true, reminderWeekday: 1, reminderMinute: 1200)); XCTFail("save must fail") } catch { }
        XCTAssertEqual(ready.goal?.weeklyLossKg, 0.3); XCTAssertFalse(ready.saving)
        ready.activate(device: "", scope: nil)
    }
    func testRestartReplacesReminderIdentityAndRoutesToOriginalGoal() async {
        let scheduler = scheduler()
        var first = goal(); first.id = 12
        scheduler.update(goal: first, scope: "a"); await scheduler.settled()
        let original = requests.values.first!
        XCTAssertEqual(original.content.userInfo["id"] as? Int64, 12)
        var second = first; second.id = 13
        scheduler.update(goal: second, scope: "a"); await scheduler.settled()
        XCTAssertEqual(requests.count, 1)
        XCTAssertNotEqual(requests.values.first?.identifier, original.identifier)
        XCTAssertEqual(requests.values.first?.content.userInfo["id"] as? Int64, 13)
    }
    func testFormattingDoesNotShowNegativeZero() {
        XCTAssertEqual(WeeklyWeightPresentation.weight(-0.01, unit: "kg", signed: true), "0.0")
        XCTAssertEqual(WeeklyWeightPresentation.weight(0.3, unit: "kg", signed: true), "+0.3")
    }
}
