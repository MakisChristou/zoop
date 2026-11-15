import XCTest

@MainActor final class NotificationSettingsTests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "profile"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        addUIInterruptionMonitor(withDescription: "Notification consent") { alert in
            if alert.buttons["Allow"].exists { alert.buttons["Allow"].tap(); return true }
            return false
        }
        app.launch()
        let notifications = app.buttons["openNotifications"]
        XCTAssertTrue(app.navigationBars["Profile & settings"].waitForExistence(timeout: 15))
        for _ in 0..<8 where !notifications.isHittable { app.swipeUp() }
        notifications.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func testTimesAppearOnlyForEnabledCheckInsAndPersist() {
        let app = launch()
        let ecg = app.switches["ecgReminderEnabled"].firstMatch
        XCTAssertTrue(ecg.waitForExistence(timeout: 5))
        if ecg.value as? String == "1" { ecg.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertFalse(app.descendants(matching: .any)["ecgReminderTime"].firstMatch.exists)
        ecg.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); app.navigationBars["Notifications"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["ecgReminderTime"].firstMatch.waitForExistence(timeout: 5))
        shot(app, "Daily reminder times")
        app.terminate()
        let relaunched = launch()
        XCTAssertEqual(relaunched.switches["ecgReminderEnabled"].firstMatch.value as? String, "1")
        XCTAssertTrue(relaunched.descendants(matching: .any)["ecgReminderTime"].firstMatch.exists)
        relaunched.switches["ecgReminderEnabled"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertFalse(relaunched.descendants(matching: .any)["ecgReminderTime"].firstMatch.exists)
        XCTAssertTrue(relaunched.switches["offBodyReminderEnabled"].exists)
        shot(relaunched, "Optional ECG reminder off")
    }
    func testLargeTextKeepsSettingsReachable() {
        let app = launch(large: true)
        XCTAssertTrue(app.switches["weightReminderEnabled"].firstMatch.exists)
        shot(app, "Notifications at accessibility text size")
        let offBody = app.switches["offBodyReminderEnabled"]
        for _ in 0..<8 where !offBody.isHittable { app.swipeUp() }
        XCTAssertTrue(offBody.isHittable)
        shot(app, "Off-body reminder at accessibility text size")
        let settings = app.buttons["iPhone notification settings"]
        let allow = app.buttons["Allow notifications"]
        for _ in 0..<6 where !settings.isHittable && !allow.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.isHittable || allow.isHittable)
        shot(app, "Notification permission control at large text")
    }
}
