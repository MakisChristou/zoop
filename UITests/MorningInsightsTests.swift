import XCTest

/// Synthetic INSIGHT-REVIEW only; no physical phone or personal recordings.
@MainActor final class MorningInsightsTests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "INSIGHT-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28473", "-ingestToken", "ui-test-token", "-onboarded", "YES"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func open(_ app: XCUIApplication) {
        let brief = app.buttons["openMorningInsights"]
        XCTAssertTrue(brief.waitForExistence(timeout: 25))
        for _ in 0..<5 { if brief.isHittable { break }; app.swipeUp() }
        brief.tap()
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 10))
    }
    func testBriefDetailsMethodsAndPreviousDay() {
        let app = launch()
        XCTAssertTrue(app.buttons["openMorningInsights"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.buttons["openMorningInsights"].label.contains("Good"))
        XCTAssertLessThan(app.buttons["openMorningInsights"].frame.minY, app.buttons["openDayActivity"].frame.minY)
        shot(app, "Today neutral headline")
        open(app)
        XCTAssertTrue(app.staticTexts["Based on 14 nights"].firstMatch.waitForExistence(timeout: 15))
        shot(app, "Morning comparisons")
        app.buttons["About morning insights"].tap()
        XCTAssertTrue(app.navigationBars["About insights"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 5))
        open(app)
        XCTAssertTrue(app.staticTexts["Early baseline · 13 nights"].firstMatch.waitForExistence(timeout: 15))
        shot(app, "Yesterday early baseline")
    }
    func testLargeTextDetailsRemainReadable() {
        let app = launch(large: true)
        XCTAssertTrue(app.buttons["openMorningInsights"].waitForExistence(timeout: 25))
        shot(app, "Today headline accessibility text")
        open(app)
        XCTAssertTrue(app.staticTexts["morningOutlookStatus"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "Morning insights large text")
        for _ in 0..<8 { if app.staticTexts["Sleep timing"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Sleep timing"].exists)
        shot(app, "Weekly insights large text")
    }
}
