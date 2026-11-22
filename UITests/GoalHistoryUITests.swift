import XCTest

@MainActor final class GoalHistoryUITests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoSerial", "GOALS-" + UUID().uuidString, "-serverURL", "http://127.0.0.1:28483",
            "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "weekly-weight",
            "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
        ]
        app.launch()
        XCTAssertTrue(app.otherElements["goalWeightChart"].waitForExistence(timeout: 20))
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
    func testEndKeepsHistoryAndStartsNewCut() {
        let app = launch()
        shot(app, "Goals current")
        app.buttons["cutOptions"].tap()
        app.buttons["End goal"].tap()
        XCTAssertTrue(app.buttons["End goal"].waitForExistence(timeout: 5))
        shot(app, "End cut confirmation")
        app.buttons["End goal"].tap()
        XCTAssertTrue(app.staticTexts["Maintenance"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Maintenance"].exists)
        for _ in 0..<5 where !app.staticTexts["Ended early"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["Ended early"].exists)
        shot(app, "Goals maintenance and history")
        for _ in 0..<8 where !app.buttons["cutOptions"].isHittable { app.swipeDown() }
        app.buttons["cutOptions"].tap()
        app.buttons["editWeightGoal"].tap()
        app.buttons["Cut"].tap()
        XCTAssertTrue(app.buttons["saveWeightGoal"].waitForExistence(timeout: 5))
        app.buttons["saveWeightGoal"].tap()
        XCTAssertTrue(app.buttons["cutOptions"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Cut"].exists)
    }
    func testWeeklyPaceAndLargeTextRemainAccessible() {
        let app = launch(large: true)
        shot(app, "Goals accessibility text")
        app.buttons["cutOptions"].tap()
        app.buttons["Weekly pace"].tap()
        XCTAssertTrue(app.otherElements["cutWeeklyChart"].waitForExistence(timeout: 10))
        shot(app, "Goals weekly pace accessibility")
    }
}
