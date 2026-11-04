import XCTest
import UserNotifications
@testable import Snoop

@MainActor final class DailyReminderSchedulerTests: XCTestCase {
    private var requests: [String: UNNotificationRequest] = [:]
    private var allowed = true
    private var fail = false
    private var defaults: UserDefaults!
    private var domain = ""
    private var beforeAdd: (() async -> Void)?
    private var now = ISO8601DateFormatter().date(from: "2030-11-05T06:00:00Z")!
    override func setUp() async throws { domain = "ReminderTests.\(UUID())"; defaults = UserDefaults(suiteName: domain)! }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: domain) }
    private var client: ReminderNotificationClient {
        .init(authorization: { self.allowed ? .authorized : .denied }, pending: { Array(self.requests.values) }, delivered: { [] }, add: { request in
            await self.beforeAdd?()
            if self.fail { throw URLError(.cannotCreateFile) }; self.requests[request.identifier] = request
        }, removePending: { ids in for id in ids { self.requests.removeValue(forKey: id) } }, removeDelivered: { _ in })
    }
    private func make() -> DailyReminderScheduler {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        return DailyReminderScheduler(center: client, defaults: defaults, clock: { self.now }, calendar: { c })
    }
    func testCompletionCancelsOnlyTodayAndTimeChangeReplacesFutureRequests() async {
        let scheduler = make(); scheduler.ecgEnabled = true
        scheduler.update(.init(scope: "test", weightEnabled: true, weightDays: [], ecgDays: [])); await scheduler.settled()
        XCTAssertEqual(requests.count, 56)
        scheduler.update(.init(scope: "test", weightEnabled: true, weightDays: ["2030-11-05"], ecgDays: ["2030-11-05"])); await scheduler.settled()
        XCTAssertEqual(requests.count, 54); XCTAssertFalse(requests.keys.contains { $0.hasSuffix("2030-11-05") })
        scheduler.weightMinute = 600; await scheduler.settled()
        let weight = requests.values.first { $0.content.userInfo["destination"] as? String == "weight" }!
        XCTAssertEqual((weight.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 10)
        XCTAssertEqual(requests.count, 54)
    }
    func testScopeChangeDisableAndDeniedPermissionRemoveStaleRequests() async {
        let scheduler = make()
        scheduler.update(.init(scope: "old", weightEnabled: true, weightDays: [], ecgDays: [])); await scheduler.settled()
        let unrelated = UNNotificationRequest(identifier: "snoop.battery.test.low", content: UNMutableNotificationContent(), trigger: nil)
        requests[unrelated.identifier] = unrelated
        scheduler.update(.init(scope: "new", weightEnabled: true, weightDays: [], ecgDays: [])); await scheduler.settled()
        XCTAssertFalse(requests.keys.contains { $0.contains(".old.") }); XCTAssertEqual(requests.count, 29)
        allowed = false; scheduler.refresh(); await scheduler.settled()
        XCTAssertEqual(Array(requests.keys), [unrelated.identifier])
        allowed = true; scheduler.update(nil); await scheduler.settled()
        XCTAssertEqual(requests.count, 1)
    }
    func testSchedulingFailureIsRetryableAndLegacyWakeRequestsAreRemoved() async {
        let old = UNNotificationRequest(identifier: "snoop.weight.old.2030-11-05", content: UNMutableNotificationContent(), trigger: nil)
        requests[old.identifier] = old; fail = true
        let scheduler = make(); scheduler.update(.init(scope: "test", weightEnabled: true, weightDays: [], ecgDays: [])); await scheduler.settled()
        XCTAssertNotNil(scheduler.error); XCTAssertTrue(requests.isEmpty)
        fail = false; scheduler.refresh(); await scheduler.settled()
        XCTAssertNil(scheduler.error); XCTAssertEqual(requests.count, 28)
    }
    func testCompletionWhileAddIsInFlightLeavesNoStaleRequest() async {
        let scheduler = make()
        var resume: CheckedContinuation<Void, Never>?
        beforeAdd = {
            self.beforeAdd = nil
            await withCheckedContinuation { resume = $0 }
        }
        scheduler.update(.init(scope: "test", weightEnabled: true, weightDays: [], ecgDays: []))
        while resume == nil { await Task.yield() }
        scheduler.update(.init(scope: "test", weightEnabled: true, weightDays: ["2030-11-05"], ecgDays: []))
        resume?.resume(); await scheduler.settled()
        XCTAssertEqual(requests.count, 27)
        XCTAssertFalse(requests.keys.contains { $0.hasSuffix("2030-11-05") })
    }
    func testPersistedReceiptPreventsSecondAttemptAfterRelaunchAndTimeChange() async {
        var scheduler = make()
        scheduler.update(.init(scope: "test", weightEnabled: true, weightDays: [], ecgDays: [])); await scheduler.settled()
        now = now.addingTimeInterval(4 * 3600)
        requests = requests.filter { !$0.key.hasSuffix("2030-11-05") }
        scheduler = make(); scheduler.weightMinute = 12 * 60
        scheduler.update(.init(scope: "test", weightEnabled: true, weightDays: [], ecgDays: [])); await scheduler.settled()
        XCTAssertEqual(requests.count, 27)
        XCTAssertFalse(requests.keys.contains { $0.hasSuffix("2030-11-05") })
    }

}
