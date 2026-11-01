import XCTest

/// Uses only the synthetic UI-REVIEW backend. Physical Health permissions and
/// background wake delivery remain a separate on-device acceptance check.
final class HealthWeightTests: XCTestCase {
    private func launch(large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28474", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-weightUnit", "kg"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func profile(_ app: XCUIApplication) {
        let button = app.buttons["openProfile"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15)); button.tap()
        XCTAssertTrue(app.navigationBars["Profile & settings"].waitForExistence(timeout: 5))
    }
    private func openWeight(_ app: XCUIApplication) {
        let card = app.buttons["todayWeight"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        for _ in 0..<10 { if card.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(card.isHittable); shot(app, "Compact Today weight card"); card.tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
    }
    func testWeightRangesOptionsAndImportNavigation() {
        let app = launch(); openWeight(app)
        XCTAssertTrue(app.segmentedControls.buttons["30D"].waitForExistence(timeout: 10))
        let monthDates = app.staticTexts["weightChartDates"].label
        app.segmentedControls.buttons["7D"].tap()
        XCTAssertNotEqual(app.staticTexts["weightChartDates"].label, monthDates)
        app.segmentedControls.buttons["All"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["All"].isSelected)
        shot(app, "Weight trend all history")
        let chart = app.descendants(matching: .any)["Weight chart"].firstMatch
        XCTAssertTrue(chart.exists); chart.tap()
        XCTAssertTrue(app.buttons["weightChartLatest"].waitForExistence(timeout: 5))
        shot(app, "Selected weight measurement")
        app.buttons["weightChartLatest"].tap()
        XCTAssertFalse(app.buttons["weightChartLatest"].exists)
        app.buttons["Weight options"].tap()
        let importAction = app.buttons["Import weight history"]
        XCTAssertTrue(importAction.waitForExistence(timeout: 5))
        importAction.press(forDuration: 0.1)
        XCTAssertTrue(app.navigationBars["Import weight history"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirmWeightImport"].exists)
        shot(app, "Weight import setup")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
    }
    func testSwipingHistoryAndReturningToLatest() {
        let app = launch(); openWeight(app)
        XCTAssertTrue(app.segmentedControls.buttons["30D"].waitForExistence(timeout: 10))
        let dates = app.staticTexts["weightChartDates"]
        let latestDates = dates.label
        XCTAssertTrue(app.staticTexts["weightChartValue"].label.contains("kg"))
        shot(app, "Current weight period")
        let chart = app.descendants(matching: .any)["Weight chart"].firstMatch
        chart.swipeRight()
        XCTAssertTrue(NSPredicate(format: "label != %@", latestDates).evaluate(with: dates))
        let olderDates = dates.label
        XCTAssertTrue(app.buttons["weightChartLatest"].exists)
        shot(app, "Earlier weight period")
        app.segmentedControls.buttons["7D"].tap()
        XCTAssertEqual(dates.label.components(separatedBy: " – ").last, olderDates.components(separatedBy: " – ").last)
        app.segmentedControls.buttons["30D"].tap()
        XCTAssertEqual(dates.label, olderDates)
        chart.swipeLeft()
        XCTAssertNotEqual(dates.label, olderDates)
        if app.buttons["weightChartLatest"].exists { app.buttons["weightChartLatest"].tap() }
        XCTAssertEqual(dates.label, latestDates)
        chart.swipeLeft()
        XCTAssertEqual(dates.label, latestDates)
        chart.tap()
        XCTAssertTrue(app.buttons["weightChartLatest"].waitForExistence(timeout: 5))
        shot(app, "Tap selection after scrolling")
        app.buttons["weightChartLatest"].tap()
        XCTAssertFalse(app.buttons["weightChartLatest"].exists)
        app.segmentedControls.buttons["7D"].tap()
        let week = dates.label
        chart.swipeRight()
        XCTAssertNotEqual(dates.label, week)
        app.buttons["weightChartLatest"].tap()
        XCTAssertEqual(dates.label, week)
        app.segmentedControls.buttons["90D"].tap()
        shot(app, "Ninety day weight window")
        app.buttons["weightHistory"].tap()
        XCTAssertTrue(app.navigationBars["All weigh-ins"].waitForExistence(timeout: 5))
    }
    func testWeightEntryHistoryAndHealthSettings() {
        let app = launch(); openWeight(app)
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        app.buttons["logWeight"].tap()
        let field = app.textFields["weightInput"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        if let value = field.value as? String, value != "Weight", !value.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText("81.4"); app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        app.buttons["weightHistory"].tap()
        XCTAssertTrue(app.navigationBars["All weigh-ins"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["81.4 kg"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "Weight history")
        app.navigationBars["All weigh-ins"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Weight"].buttons.element(boundBy: 0).tap()
        profile(app)
        XCTAssertFalse(app.buttons["Weight"].exists)
        app.buttons["Apple Health"].tap()
        XCTAssertTrue(app.navigationBars["Apple Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Export steps"].exists)
        XCTAssertTrue(app.switches["Import weight"].exists)
        XCTAssertTrue(app.switches["Export weight"].exists)
        shot(app, "Health connection")
    }
    func testLargeTextWeightAndConnectionRemainAccessible() {
        let app = launch(large: true); openWeight(app)
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["logWeight"].isHittable)
        shot(app, "Weight accessibility text")
        let history = app.buttons["weightHistory"]
        for _ in 0..<8 { if history.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(history.isHittable)
        shot(app, "Weight accessibility chart and history")
        history.tap()
        XCTAssertTrue(app.navigationBars["All weigh-ins"].waitForExistence(timeout: 5))
        shot(app, "Weight history accessibility text")
        app.navigationBars["All weigh-ins"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Weight"].buttons.element(boundBy: 0).tap()
        profile(app)
        XCTAssertFalse(app.buttons["Weight"].exists)
        app.buttons["Apple Health"].tap()
        XCTAssertTrue(app.navigationBars["Apple Health"].waitForExistence(timeout: 5))
        for _ in 0..<8 { if app.buttons["Connect Apple Health"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["Connect Apple Health"].isHittable)
        shot(app, "Health accessibility text")
    }
}
