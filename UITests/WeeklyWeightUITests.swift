import XCTest

@MainActor final class WeeklyWeightUITests: XCTestCase {
    private func launch(large: Bool = false, screen: String = "weekly-weight", state: String = "WEEKLY") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", state + "-" + UUID().uuidString, "-serverURL", "http://127.0.0.1:28482", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen, "-reminders.stepsEnabled", "YES"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch(); if screen == "weekly-weight" && state == "WEEKLY" { XCTAssertTrue(app.staticTexts["weeklyWeightStatus"].waitForExistence(timeout: 20)) }; return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    private func tap(_ app: XCUIApplication, _ id: String) {
        if id == "editWeightGoal" || id == "About cut progress" {
            let options = app.buttons["cutOptions"]
            for _ in 0..<12 where !options.isHittable { app.swipeDown() }
            options.tap()
        }
        let button = app.buttons[id]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        for _ in 0..<12 {
            let save = app.buttons["saveWeightGoal"]
            if id.hasPrefix("editCut"), save.exists {
                let top = app.navigationBars["Edit cut"].frame.maxY + 24
                if button.frame.midY < top {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
                } else if button.frame.midY >= save.frame.minY - 24 || !button.isHittable {
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
                } else { break }
            } else if !button.isHittable { app.swipeUp() } else { break }
        }
        button.tap()
    }
    private func back(_ app: XCUIApplication) {
        for title in ["Finish date", "Daily steps", "Reminders"] where app.navigationBars[title].exists {
            app.navigationBars[title].buttons.element(boundBy: 0).tap(); return
        }
        XCTFail("Expected a goal detail page")
    }
    func testOutlookAndConfigurableGoal() {
        let app = launch(); XCTAssertTrue(app.otherElements["cutProgress"].waitForExistence(timeout: 5)); shot(app, "Weekly outlook")
        tap(app, "About cut progress"); XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5)); shot(app, "Weekly outlook info"); app.buttons["Done"].tap()
        tap(app, "editWeightGoal")
        let input = app.textFields["weeklyLossInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5))
        shot(app, "Focused cut setup")
        XCTAssertFalse(app.switches["hasCutFinish"].exists)
        XCTAssertFalse(app.switches["cutStepsReminder"].exists)
        let original = input.value as? String
        if (Double(original ?? "") ?? 0) > 0.5 { app.otherElements["weeklyLossRuler"].swipeRight() }
        else { app.otherElements["weeklyLossRuler"].swipeLeft() }
        let chosen = input.value as? String; XCTAssertNotEqual(chosen, original)
        tap(app, "editCutFinish"); XCTAssertTrue(app.switches["hasCutFinish"].waitForExistence(timeout: 5))
        shot(app, "Finish and target")
        app.switches["hasCutFinish"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); back(app)
        tap(app, "editCutReminders"); XCTAssertTrue(app.switches["cutStepsReminder"].waitForExistence(timeout: 5))
        shot(app, "Focused reminders")
        XCTAssertEqual(app.switches["cutStepsReminder"].value as? String, "1")
        app.switches["cutStepsReminder"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); XCTAssertFalse(app.datePickers["cutStepsReminderTime"].exists); back(app)
        tap(app, "editCutSteps")
        let steps = app.textFields["cutStepsInput"]; XCTAssertTrue(steps.waitForExistence(timeout: 5))
        steps.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let oldSteps = steps.value as? String ?? ""
        steps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldSteps.count) + "9000")
        XCTAssertEqual(steps.value as? String, "9000"); back(app)
        tap(app, "saveWeightGoal")
        XCTAssertTrue(input.waitForNonExistence(timeout: 10))
        tap(app, "editWeightGoal")
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, chosen)
        tap(app, "editCutFinish"); XCTAssertEqual(app.switches["hasCutFinish"].value as? String, "0"); back(app)
        tap(app, "editCutSteps"); XCTAssertEqual(app.textFields["cutStepsInput"].value as? String, "9000"); back(app)
        tap(app, "editCutReminders"); XCTAssertEqual(app.switches["cutStepsReminder"].value as? String, "0")
        app.switches["cutStepsReminder"].coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); back(app); app.buttons["Cancel"].tap()
        tap(app, "editWeightGoal"); tap(app, "editCutReminders")
        XCTAssertEqual(app.switches["cutStepsReminder"].value as? String, "0", "Cancel must discard reminder changes")
        back(app); app.buttons["Cancel"].tap()
    }
    func testSmallPhoneAndAccessibilityText() {
        let app = launch(large: true); shot(app, "Weekly outlook large text")
        let cutChart = app.otherElements["cutWeeklyChart"]
        for _ in 0..<10 where cutChart.frame.maxY > app.frame.height - 40 { app.swipeUp() }
        XCTAssertTrue(cutChart.isHittable); shot(app, "Cut chart large text")
        tap(app, "About cut progress"); shot(app, "Info large text")
        let target = app.staticTexts["Target weight"]
        for _ in 0..<8 where !target.isHittable { app.swipeUp() }
        XCTAssertTrue(target.isHittable); shot(app, "Info ending large text"); app.buttons["Done"].tap()
        tap(app, "editWeightGoal")
        XCTAssertTrue(app.textFields["weeklyLossInput"].waitForExistence(timeout: 5)); shot(app, "Cut setup large text")
        tap(app, "editCutFinish"); shot(app, "Finish large text"); back(app); shot(app, "Goal options large text")
        tap(app, "editCutReminders")
        let time = app.datePickers["cutStepsReminderTime"]
        XCTAssertTrue(time.waitForExistence(timeout: 5))
        for _ in 0..<10 where !time.isHittable { app.swipeUp() }
        XCTAssertTrue(time.isHittable); shot(app, "Reminders large text")
        back(app); tap(app, "editCutSteps")
        XCTAssertTrue(app.textFields["cutStepsInput"].waitForExistence(timeout: 5)); shot(app, "Steps large text")
        back(app); app.buttons["Cancel"].tap()
    }
    func testEmptyPausedAndErrorStates() {
        for state in ["EMPTY", "PAUSED", "PENDING", "ERROR"] {
            let app = launch(state: state)
            let action = app.buttons[state == "ERROR" ? "Retry" : "startWeightGoal"]
            XCTAssertTrue(action.waitForExistence(timeout: 15)); shot(app, "Weekly outlook " + state)
            if state == "PENDING" { XCTAssertEqual(action.label, "Edit goal") }
            if state == "EMPTY" { action.tap(); XCTAssertTrue(app.textFields["weeklyLossInput"].waitForExistence(timeout: 5)); shot(app, "Start cut empty"); app.buttons["Cancel"].tap() }
            app.terminate()
        }
    }
    func testGoalsTabOwnsCutNavigation() {
        let app = launch(screen: "today")
        XCTAssertTrue(app.tabBars.buttons["Goals"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.buttons["todayWeeklyWeight"].exists)
        let weight = app.buttons["todayWeight"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 10))
        for _ in 0..<6 where !weight.isHittable { app.swipeUp() }
        weight.tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["weightChart"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["openWeeklyWeight"].exists)
        XCTAssertFalse(app.staticTexts["Weight outlook"].exists)
        shot(app, "Weight only from Today")
        app.buttons["Weight options"].tap()
        XCTAssertTrue(app.buttons["weightHistory"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["weightGoalOptions"].exists)
        app.buttons["Done"].tap()
        app.tabBars.buttons["Goals"].tap()
        XCTAssertTrue(app.staticTexts["weeklyWeightStatus"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["Goals"].isSelected)
        shot(app, "Goals tab current cut")
        tap(app, "editWeightGoal")
        XCTAssertTrue(app.textFields["weeklyLossInput"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].exists)
        app.tabBars.buttons["Goals"].tap()
        XCTAssertTrue(app.staticTexts["weeklyWeightStatus"].waitForExistence(timeout: 5))
    }
    func testCutWeekNavigationAndChartSelection() {
        let app = launch()
        let chart = app.otherElements["cutWeeklyChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 4")
        shot(app, "Cut progress overview")
        let remaining = app.otherElements["cutDaysRemaining"].label
        app.buttons["cutPreviousWeek"].tap()
        XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 3")
        XCTAssertFalse(app.staticTexts["weeklyWeightStatus"].exists, "Do not reuse the current verdict for history")
        XCTAssertEqual(app.otherElements["cutDaysRemaining"].label, remaining)
        for _ in 0..<4 where chart.frame.maxY > app.frame.height - 130 { app.swipeUp() }
        chart.swipeRight()
        XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 2")
        chart.swipeLeft()
        XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 3")
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 1")
        XCTAssertFalse(app.buttons["cutPreviousWeek"].isEnabled)
        shot(app, "Cut history selected")
        for _ in 0..<3 { app.buttons["cutNextWeek"].tap() }
        XCTAssertFalse(app.buttons["cutNextWeek"].isEnabled)
        XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 4")
    }
    func testFirstWeekAndOpenEndedCut() {
        for state in ["FIRST", "OPEN"] {
            let app = launch(state: state)
            XCTAssertTrue(app.otherElements["cutWeeklyChart"].waitForExistence(timeout: 15))
            if state == "FIRST" {
                XCTAssertTrue((app.otherElements["cutWeeklyChart"].value as? String ?? "").contains("2 weigh-ins"))
                XCTAssertEqual(app.staticTexts["cutSelectedWeek"].label, "Week 1")
                XCTAssertFalse(app.staticTexts["Starting"].exists)
                XCTAssertFalse(app.staticTexts["First week"].exists)
                XCTAssertFalse(app.buttons["cutPreviousWeek"].isEnabled)
            } else { XCTAssertFalse(app.otherElements["cutDaysRemaining"].exists) }
            shot(app, "Cut progress " + state); app.terminate()
        }
    }
    func testWeightTargetAndStepsProgress() {
        let app = launch(screen: "today")
        let weight = app.buttons["todayWeight"].firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 20))
        for _ in 0..<5 where !weight.isHittable { app.swipeUp() }; weight.tap()
        let chart = app.otherElements["weightChart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        for _ in 0..<5 where !chart.isHittable { app.swipeUp() }
        XCTAssertTrue((chart.value as? String ?? "").contains("Target"))
        for _ in 0..<5 where chart.frame.maxY > app.frame.height - 120 { app.swipeUp() }
        shot(app, "Weight target dotted line")
        app.terminate()
        let stepsApp = launch(screen: "steps")
        let progress = stepsApp.otherElements["cutStepsProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        XCTAssertTrue((progress.value as? String ?? "").contains("8,000")); shot(stepsApp, "Cut daily steps progress")
    }

    func testCompletedStepsAndNotificationPreference() {
        let app = launch(screen: "steps", state: "COMPLETE")
        let progress = app.otherElements["cutStepsProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        XCTAssertTrue((progress.value as? String ?? "").contains("goal reached"))
        XCTAssertTrue(app.otherElements["stepGoalCelebrationPlayed"].waitForExistence(timeout: 10))
        shot(app, "Steps goal complete")
        app.terminate()
        let settingsApp = launch(screen: "profile", state: "COMPLETE")
        let notifications = settingsApp.buttons["openNotifications"]
        XCTAssertTrue(notifications.waitForExistence(timeout: 15))
        for _ in 0..<5 where !notifications.isHittable { settingsApp.swipeUp() }
        notifications.tap()
        let completion = settingsApp.switches["stepsCompletionEnabled"]
        XCTAssertTrue(completion.waitForExistence(timeout: 15))
        for _ in 0..<5 where !completion.isHittable { settingsApp.swipeUp() }
        shot(settingsApp, "Goal completion preference")
        // Turn off (no system permission dialog), then verify navigation preserves it.
        if completion.value as? String == "1" { completion.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap() }
        XCTAssertEqual(completion.value as? String, "0")
        settingsApp.navigationBars["Notifications"].buttons.element(boundBy: 0).tap()
        notifications.tap()
        XCTAssertEqual(completion.value as? String, "0")
    }

    func testCompletedStepsLargeText() {
        let app = launch(large: true, screen: "steps", state: "COMPLETE")
        let progress = app.otherElements["cutStepsProgress"]
        XCTAssertTrue(progress.waitForExistence(timeout: 20))
        for _ in 0..<5 where !progress.isHittable { app.swipeUp() }
        XCTAssertTrue(progress.isHittable)
        XCTAssertTrue((progress.value as? String ?? "").contains("goal reached"))
        XCTAssertTrue(app.otherElements["stepGoalCelebrationPlayed"].waitForExistence(timeout: 10))
        shot(app, "Completed steps large text")
    }

}
