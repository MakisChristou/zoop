import XCTest

/// Run only against the isolated synthetic UI-REVIEW dataset described in README.
/// Launch arguments apply to this process; they never change the phone's settings.
final class WorkoutCorrectionsTests: XCTestCase {
    private func launch(_ screen: String = "activity") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28472", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen]
        app.launch()
        return app
    }

    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHistoricalHeadingAndActivityKeepSelectedDay() {
        let app = launch("today")
        let previous = app.buttons["Previous day"]
        XCTAssertTrue(previous.waitForExistence(timeout: 15))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: previous)
        waitForExpectations(timeout: 15)
        previous.tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 10))
        screenshot(app, "Yesterday dashboard")
        app.buttons["openSteps"].tap()
        XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Yesterday"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["openDayActivity"].tap()
        XCTAssertTrue(app.buttons["Show all"].waitForExistence(timeout: 10))
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 5))
        app.buttons["Back to today"].tap()
        XCTAssertFalse(app.buttons["Back to today"].exists)
    }

    func testEditMergeSplitRemoveAndRestoreFromTheApp() {
        let app = launch()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout-'" )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.buttons["Workout actions"].waitForExistence(timeout: 10))
        app.buttons["Workout actions"].tap()
        app.buttons["Edit workout"].tap()
        XCTAssertTrue(app.navigationBars["Edit workout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Start"].exists)
        XCTAssertTrue(app.staticTexts["End"].exists)
        app.buttons["Cancel"].tap()
        app.buttons["Workout actions"].tap()
        app.buttons["Merge workouts"].tap()
        let neighbour = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Strength training,'")).firstMatch
        XCTAssertTrue(neighbour.waitForExistence(timeout: 10))
        neighbour.tap()
        screenshot(app, "Merge workout editor")
        app.buttons["saveWorkout"].tap()
        XCTAssertTrue(app.buttons["Workout actions"].waitForExistence(timeout: 15))
        app.buttons["Workout actions"].tap()
        app.buttons["Split workout"].tap()
        XCTAssertTrue(app.navigationBars["Split workout"].waitForExistence(timeout: 5))
        screenshot(app, "Split workout editor")
        app.buttons["saveWorkout"].tap()
        XCTAssertTrue(app.buttons["Workout actions"].waitForExistence(timeout: 15))
        app.buttons["Workout actions"].tap()
        app.buttons["Remove workout"].tap()
        app.buttons["Remove workout"].tap()
        let restore = app.buttons["Restore workout"]
        XCTAssertTrue(restore.waitForExistence(timeout: 15))
        restore.tap()
        XCTAssertTrue(app.buttons["Workout actions"].waitForExistence(timeout: 15))
        screenshot(app, "Restored workout")
    }
}
