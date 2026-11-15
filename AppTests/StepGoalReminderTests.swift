import XCTest
import UserNotifications
@testable import Snoop

@MainActor private final class StepsReminderState {
    var now = ISO8601DateFormatter().date(from: "2026-11-16T21:00:00Z")!
    var permission = UNAuthorizationStatus.authorized
    var requests: [String: UNNotificationRequest] = [:]
    var sample: StepGoalReminder.Snapshot? = .init(day: "2026-11-16", steps: 5600)
    var fail = false
    var failAdd = false
    var added = 0
    var beforeAdd: (() async -> Void)?
    var held: CheckedContinuation<StepGoalReminder.Snapshot?, Never>?
    func read() throws -> StepGoalReminder.Snapshot? { if fail { throw URLError(.notConnectedToInternet) }; return sample }
    var client: ReminderNotificationClient {
        .init(authorization: { self.permission }, pending: { Array(self.requests.values) }, delivered: { [] }, add: { request in if self.failAdd { throw URLError(.unknown) }; await self.beforeAdd?(); self.requests[request.identifier] = request; self.added += 1 }, removePending: { ids in ids.forEach { self.requests.removeValue(forKey: $0) } }, removeDelivered: { _ in })
    }
}

@MainActor final class StepGoalReminderTests: XCTestCase {
    private let calendar = CutPlan.calendar(timezone: "UTC")
    private func goal(active: Bool = true, timezone: String = "UTC") -> SnoopAPI.WeightGoal {
        let start = CutPlan.date("2026-11-16", calendar: calendar)!
        var g = SnoopAPI.WeightGoal(revision: 1, active: active, startedAt: start, paceStartedAt: start, timezone: timezone, weeklyLossKg: 0.3, reminderEnabled: false, reminderWeekday: 1, reminderMinute: 1200, updatedAt: start)
        g.dailyStepsGoal = 8000; g.finishDate = "2026-11-20"; return g
    }
    private func defaults() -> (UserDefaults, String) { let key="StepGoalReminderTests."+UUID().uuidString; return (UserDefaults(suiteName: key)!,key) }
    private func reminder(_ s: StepsReminderState, _ defaults: UserDefaults) -> StepGoalReminder {
        StepGoalReminder(defaults: defaults, center: s.client, clock: { s.now }, calendar: { CutPlan.calendar(timezone: "UTC") }, loader: { _, _ in try await s.read() })
    }
    private func data(_ steps: Int) -> SnoopAPI.StepsDay { .init(day: "2026-11-16", hours: [], walkingHours: [], total: steps, walking: steps, bouts: []) }
    func testSchedulesAtTenUpdatesRemainderAndCancelsWhenReached() async throws {
        let s=StepsReminderState(), (defaults,key)=defaults(); defer { defaults.removePersistentDomain(forName: key) }
        let r=reminder(s,defaults); r.activate(goal: goal(),device: "one",scope: "one"); await r.settled()
        let first=try XCTUnwrap(s.requests.values.first), trigger=try XCTUnwrap(first.trigger as? UNCalendarNotificationTrigger)
        XCTAssertEqual(trigger.dateComponents.hour,22); XCTAssertEqual(trigger.dateComponents.day,16); XCTAssertFalse(trigger.repeats)
        r.minute = 21 * 60 + 30; await r.settled()
        XCTAssertEqual((s.requests.values.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.minute,30)
        r.minute = 22 * 60; await r.settled()
        XCTAssertEqual((s.requests.values.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour,22)
        XCTAssertEqual(first.content.body,"2,400 steps left at your last sync."); XCTAssertEqual(first.content.userInfo["destination"] as? String,"steps")
        r.receive(data(6500),scope: "one"); await r.settled(); XCTAssertEqual(s.requests.values.first?.content.body,"1,500 steps left at your last sync.")
        let before=s.added; r.receive(data(6500),scope: "one"); await r.settled(); XCTAssertEqual(s.added,before)
        r.receive(data(8000),scope: "one"); await r.settled(); XCTAssertTrue(s.requests.isEmpty)
    }
    func testMissingOldDayDeniedPausedEndedAndLogoutStayQuiet() async {
        let s=StepsReminderState(), (defaults,key)=defaults(); defer { defaults.removePersistentDomain(forName: key) }
        s.requests["snoop.battery.test"] = .init(identifier: "snoop.battery.test", content: UNMutableNotificationContent(), trigger: nil)
        let r=reminder(s,defaults)
        for sample in [nil, StepGoalReminder.Snapshot(day:"2026-11-15",steps:500), .init(day:"2026-11-16",steps:-1)] {
            s.sample=sample; r.activate(goal:goal(),device:"one",scope:"one"); r.refresh(force:true); await r.settled(); XCTAssertEqual(Set(s.requests.keys),["snoop.battery.test"])
        }
        s.sample = .init(day:"2026-11-16",steps:5600); r.refresh(force:true); await r.settled(); XCTAssertEqual(s.requests.count,2)
        s.permission = .denied; r.activate(goal:goal(),device:"one",scope:"one"); await r.settled(); XCTAssertEqual(s.requests.count,1)
        s.permission = .authorized
        for g in [goal(active:false), nil] {
            r.activate(goal:g,device:"one",scope: g == nil ? nil : "one"); await r.settled(); XCTAssertEqual(s.requests.count,1)
        }
        s.now=CutPlan.date("2026-11-21",calendar:calendar)!; r.activate(goal:goal(),device:"one",scope:"one"); await r.settled(); XCTAssertEqual(s.requests.count,1)
    }
    func testNoCatchupOrSecondReminderAfterScheduledTimeEvenAfterRelaunch() async {
        let s=StepsReminderState(), (defaults,key)=defaults(); defer { defaults.removePersistentDomain(forName:key) }
        let r=reminder(s,defaults); r.activate(goal:goal(),device:"one",scope:"one"); await r.settled()
        s.requests.removeAll(); s.now=s.now.addingTimeInterval(3700)
        r.minute=23*60; await r.settled(); XCTAssertTrue(s.requests.isEmpty)
        let reopened=reminder(s,defaults); reopened.activate(goal:goal(),device:"one",scope:"one"); await reopened.settled(); XCTAssertTrue(s.requests.isEmpty)
        s.now=CutPlan.date("2026-11-17",calendar:calendar)!.addingTimeInterval(21*3600); s.sample = .init(day:"2026-11-17",steps:5000)
        reopened.refresh(force:true); await reopened.settled(); XCTAssertEqual(s.requests.count,1)
    }
    func testFailedFetchKeepsLabelledSameDaySnapshotAndFailedAddCanRetry() async {
        let s=StepsReminderState(), (defaults,key)=defaults(); defer { defaults.removePersistentDomain(forName:key) }
        let r=reminder(s,defaults); r.activate(goal:goal(),device:"one",scope:"one"); await r.settled()
        s.fail=true; r.refresh(force:true); await r.settled(); XCTAssertEqual(s.requests.values.first?.content.body,"2,400 steps left at your last sync.")
        r.enabled=false; await r.settled(); XCTAssertTrue(s.requests.isEmpty)
        s.failAdd=true; r.enabled=true; await r.settled(); XCTAssertNotNil(r.error); XCTAssertTrue(s.requests.isEmpty)
        s.failAdd=false; r.activate(goal:goal(),device:"one",scope:"one"); await r.settled(); XCTAssertNil(r.error); XCTAssertEqual(s.requests.count,1)
    }
    func testPausingDuringSchedulingRemovesTheOldRequest() async {
        let s=StepsReminderState(), (defaults,key)=defaults(); defer { defaults.removePersistentDomain(forName:key) }
        let r=reminder(s,defaults)
        s.beforeAdd = { r.activate(goal:self.goal(active:false),device:"one",scope:"one"); s.beforeAdd=nil }
        r.activate(goal:goal(),device:"one",scope:"one"); await r.settled(); XCTAssertTrue(s.requests.isEmpty)
    }
    func testReminderDoesNotOutliveCutInAnotherTimezone() async {
        let s=StepsReminderState(), (defaults,key)=defaults(); defer { defaults.removePersistentDomain(forName:key) }
        // At 21:00 UTC the cut still runs in UTC+2; its 22:00 reminder would be after midnight.
        var g=goal(timezone:"Europe/Athens"); g.finishDate="2026-11-16"
        let r=reminder(s,defaults); r.activate(goal:g,device:"one",scope:"one"); await r.settled()
        XCTAssertTrue(s.requests.isEmpty)
    }
    func testOldAccountFetchCannotScheduleForNewAccount() async {
        let s=StepsReminderState(), (defaults,key)=defaults(); defer { defaults.removePersistentDomain(forName:key) }
        let r=StepGoalReminder(defaults:defaults,center:s.client,clock:{ s.now },calendar:{ CutPlan.calendar(timezone:"UTC") },loader:{ device,_ in
            if device=="old" { return await withCheckedContinuation { c in Task { @MainActor in s.held=c } } }
            return .init(day:"2026-11-16",steps:1000)
        })
        r.activate(goal:goal(),device:"old",scope:"old")
        while s.held == nil { await Task.yield() }
        r.activate(goal:goal(),device:"new",scope:"new"); await r.settled()
        s.held?.resume(returning:.init(day:"2026-11-16",steps:7900)); await Task.yield(); await r.settled()
        XCTAssertEqual(s.requests.count,1); XCTAssertEqual(s.requests.values.first?.content.userInfo["scope"] as? String,"new")
        XCTAssertEqual(s.requests.values.first?.content.body,"7,000 steps left at your last sync.")
    }
}
