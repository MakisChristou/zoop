import XCTest

@MainActor final class SleepDetailLayoutTests: XCTestCase {
    private func open(large: Bool = false, device: String = "DESIGN-SLEEP-DETAIL") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", device, "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "sleep", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["sleepTimelineDetails"].waitForExistence(timeout: 20))
        app.buttons["sleepTimelineDetails"].tap()
        XCTAssertTrue(app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", "Night of")).firstMatch.waitForExistence(timeout: 10))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSignalsNavigationAndSelection() {
        let app = open()
        let heart = app.otherElements.matching(identifier: "sleepSignal-Heart rate").firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Sleep detail"].exists)
        shot(app, "Sleep detail overview")
        let readout = app.staticTexts["sleepDetailSelection"]
        let original = readout.label
        let from = heart.coordinate(withNormalizedOffset: .init(dx: 0.3, dy: 0.5))
        let to = heart.coordinate(withNormalizedOffset: .init(dx: 0.6, dy: 0.5))
        from.tap()
        XCTAssertNotEqual(readout.label, original, "Tapping selects a time across the night")
        shot(app, "Sleep detail selected reading")
        from.press(forDuration: 0.1, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(readout.label, original, "Releasing the chart restores the night window")
        let beforeScroll = heart.frame.minY
        heart.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: heart.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: -0.5)), withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertLessThan(heart.frame.minY, beforeScroll - 20, "Vertical drags on the plot scroll the page")
        XCTAssertTrue(app.staticTexts["HRV"].isHittable)
        shot(app, "Sleep detail signals")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Motion"].waitForExistence(timeout: 5))
        shot(app, "Sleep detail motion")
        app.buttons["Sleep options"].tap()
        XCTAssertTrue(app.buttons["Edit sleep"].waitForExistence(timeout: 5))
    }
    func testLargeTextAndMissingSignals() {
        let app = open(large: true, device: "SLEEP-LAYOUT")
        XCTAssertTrue(app.staticTexts["No readings"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "Sleep detail large text")
        for _ in 0..<8 {
            if app.staticTexts["HRV"].isHittable { break }
            app.swipeUp()
        }
        shot(app, "Sleep detail large text signals")
        XCTAssertTrue(app.staticTexts["HRV"].isHittable)
    }
    func testFailureCanRetry() {
        let app = open(device: "DESIGN-SLEEP-ERROR-\(UUID().uuidString)")
        XCTAssertTrue(app.staticTexts["Couldn’t load signals"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Try again"].isHittable)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.otherElements.matching(identifier: "sleepSignal-Heart rate").firstMatch.waitForExistence(timeout: 10))
    }
}
