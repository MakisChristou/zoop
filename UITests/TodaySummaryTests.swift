import XCTest

@MainActor final class TodaySummaryTests: XCTestCase {
    private func launch(device: String = "MORNING-CARD-average", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", device, "-serverURL", "http://127.0.0.1:28476",
            "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "today",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["openMorningInsights"].waitForExistence(timeout: 20))
        return app
    }
    private func expectValue(_ value: String, in element: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name
        image.lifetime = .keepAlways; add(image)
    }
    func testThreeReadingsAndDestinations() {
        let app = launch()
        expectValue("Average", in: app.buttons["openMorningInsights"])
        expectValue("7h 25m, 93% of 8h goal", in: app.buttons["openSleepSummary"])
        expectValue("8.4", in: app.buttons["openDayActivity"])
        shot(app, "Today summary rings")
        app.buttons["openMorningInsights"].tap()
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["openSleepSummary"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 10))
        app.buttons["tab-Today"].tap()
        app.buttons["openDayActivity"].tap()
        XCTAssertTrue(app.buttons["removedWorkouts"].waitForExistence(timeout: 10))
        app.buttons["tab-Today"].tap()
        let steps = app.buttons["openSteps"]
        for _ in 0..<5 where !steps.isHittable { app.swipeUp() }
        XCTAssertTrue(steps.isHittable); steps.tap()
        XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout: 10))
    }
    func testSelectedDayUpdatesAllReadings() {
        let app = launch(device: "INSIGHT-REVIEW")
        expectValue("Good", in: app.buttons["openMorningInsights"])
        expectValue("7h 25m, 93% of 8h goal", in: app.buttons["openSleepSummary"])
        app.buttons["Previous day"].tap()
        expectValue("Learning", in: app.buttons["openMorningInsights"])
        XCTAssertNotEqual(app.buttons["openSleepSummary"].value as? String, "7h 25m, 93% of 8h goal")
        shot(app, "Yesterday summary rings")
        app.buttons["Back to today"].tap()
        expectValue("Good", in: app.buttons["openMorningInsights"])
        expectValue("7h 25m, 93% of 8h goal", in: app.buttons["openSleepSummary"])
    }
    func testMissingReadingsStayMissing() {
        let app = launch(device: "RINGS-EMPTY")
        expectValue("Retry", in: app.buttons["openMorningInsights"])
        expectValue("No reading", in: app.buttons["openSleepSummary"])
        expectValue("No reading", in: app.buttons["openDayActivity"])
        XCTAssertFalse(app.buttons["openSleepSummary"].isEnabled)
        shot(app, "Today rings missing readings")
    }
    func testLargeTextOutlookRemainsReadableAndOpens() {
        let app = launch(large: true)
        let outlook = app.buttons["openMorningInsights"]
        expectValue("Average", in: outlook)
        for _ in 0..<6 {
            let frame = outlook.frame
            if outlook.isHittable && frame.minY > 110 && frame.maxY < app.buttons["tab-Today"].frame.minY { break }
            let delta = min(max((frame.midY - app.frame.height * 0.48) / app.frame.height, -0.3), 0.3)
            app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5 - delta)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        shot(app, "Today rings largest text")
        XCTAssertTrue(outlook.isHittable); outlook.tap()
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 10))
    }
}
