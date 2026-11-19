import XCTest
import UserNotifications
@testable import Zoop

@MainActor private final class CompletionState {
    var now = ISO8601DateFormatter().date(from: "2026-11-16T12:00:00Z")!
    var calendar = CutPlan.calendar(timezone: "UTC")
    var permission = UNAuthorizationStatus.authorized
    var requests: [String: UNNotificationRequest] = [:]
    var adds = 0
    var fail = false
    var beforeAdd: (() -> Void)?
    var beforePermission: (() -> Void)?
    var client: ReminderNotificationClient {
        .init(authorization: { self.beforePermission?(); return self.permission }, pending: { Array(self.requests.values) }, delivered: { [] }, add: {
            self.beforeAdd?()
            if self.fail { throw URLError(.unknown) }
            self.requests[$0.identifier] = $0; self.adds += 1
        }, removePending: { ids in ids.forEach { self.requests.removeValue(forKey: $0) } }, removeDelivered: { _ in })
    }
}

@MainActor final class StepGoalCompletionTests: XCTestCase {
    private func goal(_ target: Int = 8000, active: Bool = true) -> ZoopAPI.WeightGoal {
        let start = CutPlan.date("2026-11-16", calendar: CutPlan.calendar(timezone: "UTC"))!
        var g = ZoopAPI.WeightGoal(revision: 1, active: active, startedAt: start, paceStartedAt: start, timezone: "UTC", weeklyLossKg: 0.3, reminderEnabled: false, reminderWeekday: 1, reminderMinute: 1200, updatedAt: start)
        g.dailyStepsGoal = target; g.finishDate = "2026-11-20"; return g
    }
    private func defaults() -> UserDefaults {
        let name = "StepGoalCompletionTests." + UUID().uuidString
        let value = UserDefaults(suiteName: name)!
        addTeardownBlock { value.removePersistentDomain(forName: name) }
        return value
    }
    private func completion(_ state: CompletionState, _ defaults: UserDefaults) -> StepGoalCompletion {
        .init(defaults: defaults, center: state.client, clock: { state.now }, calendar: { state.calendar })
    }
    func testCrossingPostsOnceWithStepsRouteDespiteCorrectionsAndRelaunch() async throws {
        let s = CompletionState(), d = defaults(), c = completion(s, d)
        c.activate(goal: goal(), scope: "person")
        for steps in [7999, 8000, 8100, 7900, 8000] {
            c.receive(.init(day: "2026-11-16", steps: steps)); await c.settled()
        }
        XCTAssertEqual(s.adds, 1)
        let request = try XCTUnwrap(s.requests.values.first)
        XCTAssertNil(request.trigger); XCTAssertEqual(request.content.title, "Steps goal complete")
        XCTAssertEqual(request.content.body, "8,000 steps today. Nice work.")
        XCTAssertEqual(request.content.userInfo["destination"] as? String, "steps")
        XCTAssertEqual(request.content.userInfo["scope"] as? String, "person")
        let reopened = completion(s, d); reopened.activate(goal: goal(), scope: "person")
        reopened.receive(.init(day: "2026-11-16", steps: 9000)); await reopened.settled()
        XCTAssertEqual(s.adds, 1)
    }
    func testOldMissingNegativeAndInactiveSamplesNeverCelebrate() async {
        let s = CompletionState(), c = completion(s, defaults())
        c.activate(goal: goal(), scope: "person")
        for sample in [nil, StepGoalReminder.Snapshot(day: "2026-11-15", steps: 9000), .init(day: "2026-11-16", steps: -1)] {
            c.receive(sample); await c.settled()
        }
        for g in [goal(active: false), nil] {
            c.activate(goal: g, scope: "person"); c.receive(.init(day: "2026-11-16", steps: 9000)); await c.settled()
        }
        s.now = s.now.addingTimeInterval(5 * 86400)
        c.activate(goal: goal(), scope: "person"); c.receive(.init(day: "2026-11-21", steps: 9000)); await c.settled()
        XCTAssertEqual(s.adds, 0)
    }
    func testLoweringTargetIsSilentAndSurvivesRestart() async {
        let s = CompletionState(), d = defaults(), c = completion(s, d)
        c.activate(goal: goal(), scope: "person"); c.receive(.init(day: "2026-11-16", steps: 7000)); await c.settled()
        c.activate(goal: goal(6000), scope: "person"); await c.settled()
        let reopened = completion(s, d); reopened.activate(goal: goal(6000), scope: "person")
        reopened.receive(.init(day: "2026-11-16", steps: 7000)); await reopened.settled()
        reopened.receive(.init(day: "2026-11-16", steps: 9000)); await reopened.settled()
        XCTAssertEqual(s.adds, 0)
    }
    func testLoweredButUnmetTargetCanStillBeEarned() async {
        let s = CompletionState(), c = completion(s, defaults())
        c.activate(goal: goal(), scope: "person"); c.receive(.init(day: "2026-11-16", steps: 2000)); await c.settled()
        c.activate(goal: goal(6000), scope: "person"); c.receive(.init(day: "2026-11-16", steps: 2000)); await c.settled()
        c.receive(.init(day: "2026-11-16", steps: 6000)); await c.settled()
        XCTAssertEqual(s.adds, 1)
    }
    func testDisabledAndDeniedDoNotReplayAfterEnabling() async {
        for denied in [true, false] {
            let s = CompletionState(), c = completion(s, defaults())
            if denied { s.permission = .denied } else { c.enabled = false }
            c.activate(goal: goal(), scope: "person"); c.receive(.init(day: "2026-11-16", steps: 8000)); await c.settled()
            s.permission = .authorized; c.enabled = true
            c.receive(.init(day: "2026-11-16", steps: 9000)); await c.settled()
            XCTAssertEqual(s.adds, 0)
        }
    }
    func testReenablingDoesNotCelebrateAnUnobservedCompletion() async {
        let s = CompletionState(), c = completion(s, defaults())
        c.activate(goal: goal(), scope: "person")
        c.receive(.init(day: "2026-11-16", steps: 7000)); await c.settled()
        c.enabled = false; await c.settled()
        // No updates while off; the user completes their steps in the meantime.
        c.enabled = true
        c.receive(.init(day: "2026-11-16", steps: 9000)); await c.settled()
        XCTAssertEqual(s.adds, 0)
    }
    func testFailedDeliveryRetriesOnceAndLogoutDuringAddRemovesAlert() async {
        let s = CompletionState(), c = completion(s, defaults())
        s.fail = true; c.activate(goal: goal(), scope: "person"); c.receive(.init(day: "2026-11-16", steps: 8000)); await c.settled()
        XCTAssertNotNil(c.error); XCTAssertEqual(s.adds, 0)
        s.fail = false; c.receive(.init(day: "2026-11-16", steps: 8000)); await c.settled()
        XCTAssertNil(c.error); XCTAssertEqual(s.adds, 1)
        c.activate(goal: goal(), scope: "other")
        s.beforeAdd = { c.activate(goal: nil, scope: nil); s.beforeAdd = nil }
        c.receive(.init(day: "2026-11-16", steps: 9000)); await c.settled()
        XCTAssertTrue(s.requests.isEmpty)
    }
    func testNextDayAndTimezoneChangesDoNotReplayPreviousDay() async {
        let s = CompletionState(), c = completion(s, defaults())
        c.activate(goal: goal(), scope: "person"); c.receive(.init(day: "2026-11-16", steps: 8000)); await c.settled()
        s.calendar = CutPlan.calendar(timezone: "Europe/Athens")
        c.activate(goal: goal(), scope: "person"); c.receive(.init(day: "2026-11-16", steps: 9000)); await c.settled()
        XCTAssertEqual(s.adds, 1)
        s.now = s.now.addingTimeInterval(86400)
        c.receive(.init(day: "2026-11-16", steps: 9000)); await c.settled(); XCTAssertEqual(s.adds, 1)
        c.receive(.init(day: "2026-11-17", steps: 8000)); await c.settled(); XCTAssertEqual(s.adds, 2)
    }
    func testMidnightDuringPermissionCheckDoesNotNotifyForYesterday() async {
        let s = CompletionState(), c = completion(s, defaults())
        c.activate(goal: goal(), scope: "person")
        s.beforePermission = { s.now = s.now.addingTimeInterval(86400); s.beforePermission = nil }
        c.receive(.init(day: "2026-11-16", steps: 8000)); await c.settled()
        XCTAssertEqual(s.adds, 0)
    }
    func testCompletionWorksWithEveningReminderOffAndNeverFromCache() async throws {
        let s = CompletionState(), d = defaults()
        d.set(false, forKey: "reminders.stepsEnabled")
        d.set(try JSONEncoder().encode(StepGoalReminder.Snapshot(day: "2026-11-16", steps: 8000)), forKey: "stepsReminder.person")
        let r = StepGoalReminder(defaults: d, center: s.client, clock: { s.now }, calendar: { s.calendar }, loader: { _, _ in throw URLError(.notConnectedToInternet) })
        r.activate(goal: goal(), device: "strap", scope: "person"); await r.settled(); XCTAssertEqual(s.adds, 0)
        r.receive(.init(day: "2026-11-16", hours: [], walkingHours: [], total: 8000, walking: 8000, bouts: []), scope: "wrong")
        await r.settled(); XCTAssertEqual(s.adds, 0)
        r.receive(.init(day: "2026-11-16", hours: [], walkingHours: [], total: 8000, walking: 8000, bouts: []), scope: "person")
        await r.settled(); XCTAssertEqual(s.adds, 1)
        XCTAssertTrue(s.requests.keys.allSatisfy { $0.hasPrefix("snoop.steps-complete.") })
    }
    func testCompletionCancelsEveningReminder() async {
        let s = CompletionState(), d = defaults()
        let r = StepGoalReminder(defaults: d, center: s.client, clock: { s.now }, calendar: { s.calendar }, loader: { _, _ in .init(day: "2026-11-16", steps: 7000) })
        r.activate(goal: goal(), device: "strap", scope: "person"); await r.settled()
        XCTAssertTrue(s.requests.keys.contains { $0.hasPrefix("snoop.steps-goal.") })
        r.receive(.init(day: "2026-11-16", hours: [], walkingHours: [], total: 8000, walking: 8000, bouts: []), scope: "person"); await r.settled()
        XCTAssertEqual(s.requests.count, 1)
        XCTAssertTrue(s.requests.keys.allSatisfy { $0.hasPrefix("snoop.steps-complete.") })
    }
    func testFirstCompletedViewCanCelebrateAfterNotificationButOnlyOnce() async throws {
        let s = CompletionState(), d = defaults(), c = completion(s, d)
        c.activate(goal: goal(), scope: "person")
        c.receive(.init(day: "2026-11-16", steps: 9000)); await c.settled()
        XCTAssertEqual(s.adds, 1)
        let reopened = completion(s, d); reopened.activate(goal: goal(), scope: "person")
        XCTAssertNil(reopened.celebrationKey, "Wait for a fresh count")
        reopened.receive(.init(day: "2026-11-16", steps: 9000)); await reopened.settled()
        let key = try XCTUnwrap(reopened.celebrationKey)
        XCTAssertTrue(reopened.claimCelebration(key))
        XCTAssertFalse(reopened.claimCelebration(key))
        XCTAssertNil(reopened.celebrationKey)
        let third = completion(s, d); third.activate(goal: goal(), scope: "person")
        third.receive(.init(day: "2026-11-16", steps: 9000)); await third.settled()
        XCTAssertNil(third.celebrationKey); XCTAssertEqual(s.adds, 1)
    }
    func testLoweringTargetCannotCreateVisualCelebration() async {
        let s = CompletionState(), c = completion(s, defaults())
        c.activate(goal: goal(), scope: "person")
        c.receive(.init(day: "2026-11-16", steps: 7000)); await c.settled()
        c.activate(goal: goal(6000), scope: "person")
        c.receive(.init(day: "2026-11-16", steps: 7000))
        XCTAssertNil(c.celebrationKey)
        await c.settled(); XCTAssertNil(c.celebrationKey)
    }
    func testVisualCelebrationIsAvailableWithoutNotificationPermission() async throws {
        let s = CompletionState(), c = completion(s, defaults())
        s.permission = .denied
        c.activate(goal: goal(), scope: "person")
        c.receive(.init(day: "2026-11-16", steps: 8000)); await c.settled()
        XCTAssertNotNil(c.celebrationKey); XCTAssertEqual(s.adds, 0)
        c.activate(goal: nil, scope: nil); await c.settled()
        XCTAssertNil(c.celebrationKey)
    }

}
