import XCTest

@MainActor final class SleepGoalUITests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "MORNING-CARD-average", "-serverURL", "http://127.0.0.1:28476",
            "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "today",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["openSleepSummary"].waitForExistence(timeout: 20))
        return app
    }
    private func goal(_ value: String, app: XCUIApplication) {
        app.buttons["tab-Sleep"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 15))
        app.buttons["Sleep options"].tap()
        app.buttons["editSleepGoal"].tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: value)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Sleep goal " + value
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["Done"].tap()
        app.buttons["tab-Today"].tap()
    }
    private func expect(_ value: String, app: XCUIApplication) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: app.buttons["openSleepSummary"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Sleep ring " + value
        shot.lifetime = .keepAlways; add(shot)
    }
    func testGoalPickerAtLargeText() {
        let app = launch(large: true)
        goal("8h", app: app)
        expect("7h 25m, 93% of 8h goal", app: app)
    }
    func testGoalChangesRingImmediatelyAndPersistsAcrossLaunch() {
        var app = launch()
        goal("8h", app: app)
        expect("7h 25m, 93% of 8h goal", app: app)
        goal("7h", app: app)
        expect("7h 25m, 100% of 7h goal", app: app)
        goal("9h", app: app)
        expect("7h 25m, 82% of 9h goal", app: app)
        app.terminate()
        app = launch()
        expect("7h 25m, 82% of 9h goal", app: app)
        goal("8h", app: app)
        expect("7h 25m, 93% of 8h goal", app: app)
    }
}
