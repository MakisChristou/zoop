import XCTest

@MainActor final class WeeklyWeightUITests: XCTestCase {
    private func launch(large: Bool = false, screen: String = "weekly-weight") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "WEEKLY-" + UUID().uuidString, "-serverURL", "http://127.0.0.1:28482", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", screen]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch(); if screen == "weekly-weight" { XCTAssertTrue(app.staticTexts["weeklyWeightStatus"].waitForExistence(timeout: 20)) }; return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a) }
    func testOutlookAndConfigurableGoal() {
        let app = launch(); XCTAssertTrue(app.staticTexts["Total lost"].waitForExistence(timeout: 5)); shot(app, "Weekly outlook")
        let edit = app.buttons["editWeightGoal"]
        for _ in 0..<6 where !edit.isHittable { app.swipeUp() }; edit.tap()
        let input = app.textFields["weeklyLossInput"]; XCTAssertTrue(input.waitForExistence(timeout: 5))
        let finish = app.switches["hasCutFinish"]
        for _ in 0..<4 where !finish.isHittable { app.swipeUp() }
        XCTAssertTrue(finish.isHittable)
        shot(app, "Cut setup with finish")
        finish.tap()
        for _ in 0..<4 where !input.isHittable { app.swipeDown() }
        let original = input.value as? String
        if (Double(original ?? "") ?? 0) > 0.5 { app.otherElements["weeklyLossRuler"].swipeRight() }
        else { app.otherElements["weeklyLossRuler"].swipeLeft() }
        let chosen = input.value as? String
        XCTAssertNotEqual(chosen, original)
        let steps = app.textFields["cutStepsInput"]
        for _ in 0..<6 where !steps.isHittable { app.swipeUp() }
        XCTAssertTrue(steps.isHittable); steps.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let oldSteps = steps.value as? String ?? ""
        steps.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldSteps.count) + "9000")
        XCTAssertEqual(steps.value as? String, "9000")
        shot(app, "Cut steps setup")
        let save = app.buttons["saveWeightGoal"]; for _ in 0..<4 where !save.isHittable { app.swipeUp() }; XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(input.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["weeklyWeightStatus"].waitForExistence(timeout: 10))
        let editAgain = app.buttons["editWeightGoal"]
        for _ in 0..<6 where !editAgain.isHittable { app.swipeUp() }; editAgain.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 5)); XCTAssertEqual(input.value as? String, chosen)
        XCTAssertEqual(app.switches["hasCutFinish"].value as? String, "0")
        XCTAssertEqual(app.textFields["cutStepsInput"].value as? String, "9000")
        app.buttons["Cancel"].tap()
    }
    func testSmallPhoneAndAccessibilityText() {
        let app = launch(large: true); shot(app, "Weekly outlook large text")
        let edit = app.buttons["editWeightGoal"]; for _ in 0..<10 where !edit.isHittable { app.swipeUp() }; XCTAssertTrue(edit.isHittable); edit.tap()
        XCTAssertTrue(app.textFields["weeklyLossInput"].waitForExistence(timeout: 5)); shot(app, "Cut setup large text")
        let steps = app.textFields["cutStepsInput"]
        for _ in 0..<10 where !steps.isHittable { app.swipeUp() }
        XCTAssertTrue(steps.isHittable); shot(app, "Step goal large text")
        let save = app.buttons["saveWeightGoal"]; XCTAssertTrue(save.isHittable)
        app.buttons["Cancel"].tap()
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

}
