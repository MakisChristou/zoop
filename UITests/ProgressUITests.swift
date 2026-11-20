import XCTest

@MainActor final class ProgressUITests: XCTestCase {
    private func open(large: Bool = false, sparse: Bool = false, recent: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", recent ? "PROGRESS-RECENT" : sparse ? "PROGRESS-SPARSE" : "UI-REVIEW", "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "trends"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["openProgress"].waitForExistence(timeout: 20)); app.buttons["openProgress"].tap()
        XCTAssertTrue(app.buttons["progressCard-sleep"].waitForExistence(timeout: 20))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testCompactRecentHistoryMatchesMock() {
        let app = open(recent: true)
        XCTAssertTrue(app.navigationBars["Progress"].exists)
        for label in ["Average per night", "Steps per day", "Previous 4 weeks", "Last 4 weeks", "26 recorded nights"] {
            XCTAssertFalse(app.staticTexts[label].exists)
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Compared with")).firstMatch.exists)
        XCTAssertTrue(app.buttons["progressCard-sleep"].label.contains("7h 52m"))
        shot(app, "Progress compact approved layout")
        app.buttons["About your progress"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Comparison,")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["How comparisons work"].exists)
        shot(app, "Progress information on demand")
        app.buttons["Done"].tap()
        app.buttons["progressCard-sleep"].tap()
        XCTAssertTrue(app.staticTexts["Wake-time variation"].waitForExistence(timeout: 5))
    }
    func testCardsDetailsAndReturn() {
        let app = open()
        shot(app, "Progress standard overview")
        app.buttons["progressCard-sleep"].tap()
        XCTAssertTrue(app.staticTexts["Wake-time variation"].waitForExistence(timeout: 5))
        shot(app, "Progress sleep details")
        app.buttons["About sleep progress"].tap()
        XCTAssertTrue(app.staticTexts["Comparisons need 21 nights in each period."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
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
        let sparse = open(sparse: true)
        sparse.buttons["progressCard-sleep"].tap()
        XCTAssertTrue(sparse.staticTexts["Wake-time variation"].waitForExistence(timeout: 5))
        shot(sparse, "Progress clean sleep with partial history")
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
