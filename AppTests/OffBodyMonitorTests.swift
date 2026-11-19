import XCTest
import UserNotifications
@testable import Zoop

@MainActor final class OffBodyMonitorTests: XCTestCase {
    private var requests: [String: UNNotificationRequest] = [:]
    private var beforeAdd: (() async -> Void)?
    private var defaults: UserDefaults!
    private var domain = ""
    private var now = Date()
    private var permission: UNAuthorizationStatus = .authorized
    override func setUp() async throws { domain = "OffBodyTests.\(UUID())"; defaults = UserDefaults(suiteName: domain)! }
    override func tearDown() async throws { defaults.removePersistentDomain(forName: domain) }
    private func make(featureEnabled: Bool = OffBodyMonitor.available) -> OffBodyMonitor {
        let client = ReminderNotificationClient(authorization: { self.permission }, pending: { Array(self.requests.values) }, delivered: { [] }, add: {
            await self.beforeAdd?(); self.requests[$0.identifier] = $0
        }, removePending: { ids in for id in ids { self.requests.removeValue(forKey: id) } }, removeDelivered: { _ in })
        return OffBodyMonitor(defaults: defaults, center: client, featureEnabled: featureEnabled, clock: { self.now })
    }
    func testRemovalWaitsTenMinutesAndReattachmentCancels() async {
        let monitor = make()
        XCTAssertTrue(monitor.enabled)
        monitor.receive(code: 10, at: now, live: true); await monitor.settled()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual((requests.values.first?.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 600)
        now += 10; monitor.receive(code: 10, at: now, live: true); await monitor.settled()
        XCTAssertEqual(requests.count, 1)
        now += 10; monitor.receive(code: 9, at: now, live: true); await monitor.settled()
        XCTAssertTrue(requests.isEmpty)
    }
    func testDisconnectDuringSchedulingCannotCancelNewEpisode() async {
        let monitor = make()
        var resume: CheckedContinuation<Void, Never>?
        beforeAdd = { self.beforeAdd = nil; await withCheckedContinuation { resume = $0 } }
        monitor.receive(code: 10, at: now, live: true)
        while resume == nil { await Task.yield() }
        let old = Task { await monitor.settled() }
        await Task.yield()
        monitor.invalidate()
        now += 30; monitor.receive(code: 10, at: now, live: true); await monitor.settled()
        let newID = requests.keys.first
        resume?.resume(); await old.value
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests.keys.first, newID)
        monitor.enabled = false; XCTAssertTrue(requests.isEmpty)
    }
    func testDeniedPermissionAndHistoricalEventsNeverSchedule() async {
        let monitor = make()
        monitor.receive(code: 10, at: now, live: false); await monitor.settled()
        XCTAssertTrue(requests.isEmpty)
        monitor.receive(code: 10, at: now.addingTimeInterval(-61), live: true); await monitor.settled()
        XCTAssertTrue(requests.isEmpty)
        permission = .denied
        monitor.receive(code: 10, at: now, live: true); await monitor.settled()
        XCTAssertTrue(requests.isEmpty)
    }
    func testUserDisabledPreferenceSurvivesRestart() async {
        let monitor = make(); monitor.enabled = false
        let reopened = make()
        XCTAssertFalse(reopened.enabled)
        reopened.receive(code: 10, at: now, live: true); await reopened.settled()
        XCTAssertTrue(requests.isEmpty)
    }
    func testDisabledFeatureNeverSchedules() async {
        let monitor = make(featureEnabled: false)
        monitor.receive(code: 10, at: now, live: true); await monitor.settled()
        XCTAssertTrue(requests.isEmpty); XCTAssertNil(monitor.removedAt)
    }
}
