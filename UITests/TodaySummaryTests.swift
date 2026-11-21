import XCTest

@MainActor final class TodaySummaryTests: XCTestCase {
    private func launch(device: String = "MORNING-CARD-average", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", device, "-serverURL", ProcessInfo.processInfo.environment["ZOOP_UI_TEST_SERVER"] ?? "http://127.0.0.1:28476",
            "-ingestToken", "ui-test-token", "-sleepGoalMinutes", "480", "-reminders.stepsCompletionEnabled", "YES", "-onboarded", "YES", "-demoScreen", "today",
            "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["openMorningInsights"].waitForExistence(timeout: 20))
        return app
    }
    private func expectValue(_ value: String, in element: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed, "Actual value: \(String(describing: element.value))")
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
        expectValue("75", in: app.buttons["openRecoverySummary"])
        shot(app, "Today summary rings")
        app.buttons["openRecoverySummary"].tap()
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["openMorningInsights"].tap()
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["openSleepSummary"].tap()
        XCTAssertTrue(app.buttons["Sleep options"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Sleep"].exists)
        XCTAssertEqual(app.staticTexts["sleepTimelineDuration"].label, "7h 25m")
        XCTAssertTrue(app.buttons["tab-Today"].isSelected)
        shot(app, "Sleep opened from Today")
        app.navigationBars["Sleep"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["openDayActivity"].waitForExistence(timeout: 10))
        app.buttons["openDayActivity"].tap()
        XCTAssertTrue(app.navigationBars["Load"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["removedWorkouts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tab-Today"].isSelected)
        XCTAssertEqual(app.staticTexts["dailyLoadValue"].label, "8.4")
        shot(app, "Load opened from Today")
        app.navigationBars["Load"].buttons.element(boundBy: 0).tap()
        let steps = app.buttons["openSteps"]
        for _ in 0..<5 where !steps.isHittable { app.swipeUp() }
        XCTAssertTrue(steps.isHittable); steps.tap()
        XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout: 10))
    }
    func testPastDayNavigationAndSwipeBackPreserveToday() {
        let app = launch(device: "INSIGHT-REVIEW")
        expectValue("Good", in: app.buttons["openMorningInsights"])
        app.buttons["Previous day"].tap()
        expectValue("Learning", in: app.buttons["openMorningInsights"])
        let sleep = app.buttons["openSleepSummary"].value as? String
        let load = app.buttons["openDayActivity"].value as? String
        for (ring, title) in [("openSleepSummary", "Sleep"), ("openRecoverySummary", "Recovery"), ("openDayActivity", "Load")] {
            app.buttons[ring].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["tab-Today"].isSelected)
            if title == "Sleep" {
                XCTAssertTrue(app.staticTexts["sleepTimelineDuration"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.staticTexts["sleepTimelineDuration"].label, sleep?.components(separatedBy: ",").first)
            }
            if title == "Load" { XCTAssertEqual(app.staticTexts["dailyLoadValue"].label, load) }
            app.coordinate(withNormalizedOffset: .init(dx: 0.005, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)))
            XCTAssertTrue(app.buttons["openSleepSummary"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["Back to today"].exists)
            XCTAssertEqual(app.buttons["openSleepSummary"].value as? String, sleep)
            XCTAssertEqual(app.buttons["openDayActivity"].value as? String, load)
        }
        let row = app.buttons["openMorningInsights"]
        let y = row.frame.minY
        row.tap()
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertEqual(row.frame.minY, y, accuracy: 3)
    }

    func testGoalCompletionCelebratesInStepsCard() {
        let app = launch(device: "STEPS-COMPLETE-" + UUID().uuidString)
        expectValue("8,200 of 8,000 steps, goal reached", in: app.descendants(matching: .any)["cutStepsProgress"].firstMatch)
        app.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["stepGoalCelebrationPlayed"].waitForExistence(timeout: 10))
        shot(app, "Completed steps card")
    }
    func testStepsUsesConfiguredGoalOnlyForToday() {
        let app = launch(device: "STEPS-GOAL")
        expectValue("8,200 of 12,000 steps", in: app.descendants(matching: .any)["cutStepsProgress"].firstMatch)
        shot(app, "Steps target and compact outlook")
        app.buttons["Previous day"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["cutStepsProgress"].firstMatch.exists)
        shot(app, "Past steps without a retroactive target")
        app.buttons["Back to today"].tap()
        expectValue("8,200 of 12,000 steps", in: app.descendants(matching: .any)["cutStepsProgress"].firstMatch)
    }
    func testRecoveryStatesAndDetails() {
        for state in ["zero", "full", "learning", "unusual_signals", "old-server"] {
            let app = launch(device: "RECOVERY-" + state)
            expectValue(state == "zero" ? "0" : state == "full" ? "100" : "No reading", in: app.buttons["openRecoverySummary"])
            shot(app, "Recovery " + state)
            app.buttons["openRecoverySummary"].tap()
            XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 10))
            let chart = app.otherElements["recoveryHistoryChart"]
            XCTAssertTrue(chart.waitForExistence(timeout: 10))
            chart.coordinate(withNormalizedOffset: .init(dx: 0.4, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["recoveryStatus"].waitForExistence(timeout: 10))
            shot(app, "Recovery detail " + state)
            app.terminate()
        }
    }
    func testSelectedDayUpdatesAllReadings() {
        let app = launch(device: "INSIGHT-REVIEW")
        expectValue("Good", in: app.buttons["openMorningInsights"])
        expectValue("75", in: app.buttons["openRecoverySummary"])
        expectValue("7h 25m, 93% of 8h goal", in: app.buttons["openSleepSummary"])
        app.buttons["Previous day"].tap()
        expectValue("Learning", in: app.buttons["openMorningInsights"])
        expectValue("No reading", in: app.buttons["openRecoverySummary"])
        XCTAssertNotEqual(app.buttons["openSleepSummary"].value as? String, "7h 25m, 93% of 8h goal")
        shot(app, "Yesterday summary rings")
        app.buttons["Back to today"].tap()
        expectValue("Good", in: app.buttons["openMorningInsights"])
        expectValue("75", in: app.buttons["openRecoverySummary"])
        expectValue("7h 25m, 93% of 8h goal", in: app.buttons["openSleepSummary"])
    }
    func testLargeTextRecoveryDetail() {
        let app = launch(large: true)
        let recovery = app.buttons["openRecoverySummary"]
        expectValue("75", in: recovery)
        for _ in 0..<6 where !recovery.isHittable { app.swipeUp() }
        recovery.tap()
        XCTAssertTrue(app.navigationBars["Recovery"].waitForExistence(timeout: 10))
        let chart = app.otherElements["recoveryHistoryChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        chart.coordinate(withNormalizedOffset: .init(dx: 0.4, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["recoveryStatus"].waitForExistence(timeout: 10))
        shot(app, "Recovery largest text")
        app.swipeUp()
        shot(app, "Recovery readings largest text")
        app.buttons["About recovery"].tap()
        XCTAssertTrue(app.navigationBars["About recovery"].waitForExistence(timeout: 10))
        shot(app, "Recovery method largest text")
        app.buttons["Done"].tap()
    }
    func testLoadingIndicatorsBecomeReadings() {
        let app = launch(device: "RINGS-SLOW-" + UUID().uuidString)
        expectValue("Loading", in: app.buttons["openSleepSummary"])
        expectValue("Loading", in: app.buttons["openMorningInsights"])
        expectValue("Loading", in: app.buttons["openDayActivity"])
        expectValue("Loading", in: app.buttons["openRecoverySummary"])
        shot(app, "Today rings loading")
        expectValue("7h 25m, 93% of 8h goal", in: app.buttons["openSleepSummary"])
        expectValue("Learning", in: app.buttons["openMorningInsights"])
        expectValue("8.4", in: app.buttons["openDayActivity"])
        shot(app, "Today rings loaded")
    }
    func testMissingReadingsStayMissing() {
        let app = launch(device: "RINGS-EMPTY")
        expectValue("Retry", in: app.buttons["openMorningInsights"])
        expectValue("No reading", in: app.buttons["openSleepSummary"])
        expectValue("No reading", in: app.buttons["openDayActivity"])
        expectValue("No reading", in: app.buttons["openRecoverySummary"])
        XCTAssertTrue(app.buttons["openSleepSummary"].isEnabled)
        shot(app, "Today rings missing readings")
        app.buttons["openSleepSummary"].tap()
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No main sleep"].waitForExistence(timeout: 10))
        app.navigationBars["Sleep"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["openSleepSummary"].waitForExistence(timeout: 10))
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
