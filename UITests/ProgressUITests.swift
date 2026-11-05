import XCTest

@MainActor final class ProgressUITests: XCTestCase {
    private func open(large: Bool = false, sparse: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", sparse ? "PROGRESS-SPARSE" : "UI-REVIEW", "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "trends"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["openProgress"].waitForExistence(timeout: 20)); app.buttons["openProgress"].tap()
        XCTAssertTrue(app.buttons["progressCard-sleep"].waitForExistence(timeout: 20))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCardsDetailsAndReturn() {
        let app = open()
        shot(app, "Progress standard overview")
        app.buttons["progressCard-sleep"].tap()
        XCTAssertTrue(app.staticTexts["Wake-time consistency"].waitForExistence(timeout: 5))
        shot(app, "Progress sleep details")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let activity = app.buttons["progressCard-steps"]
        for _ in 0..<4 where !activity.isHittable { app.swipeUp() }
        activity.tap()
        XCTAssertTrue(app.staticTexts["Walking per week"].waitForExistence(timeout: 5))
        shot(app, "Progress activity details")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Strength days per week"].isHittable)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["openProgress"].waitForExistence(timeout: 5))
    }
    func testLargeTextAndMissingHistory() {
        let app = open(large: true, sparse: true)
        shot(app, "Progress large text sparse sleep")
        let activity = app.buttons["progressCard-steps"]
        for _ in 0..<8 where !activity.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(activity.isHittable)
        shot(app, "Progress large text sparse activity")
        activity.tap()
        for _ in 0..<8 where !app.staticTexts["Strength days per week"].isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(app.staticTexts["Strength days per week"].isHittable)
        shot(app, "Progress large text detail")
    }
}
