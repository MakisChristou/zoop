import XCTest

/// Uses only the synthetic UI-REVIEW backend. Physical Health permissions and
/// background wake delivery remain a separate on-device acceptance check.
@MainActor final class HealthWeightTests: XCTestCase {
    private func launch(large: Bool = false, serial: String = "UI-REVIEW") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", serial, "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-weightUnit", "kg"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchSynthetic()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if allow.waitForExistence(timeout: 2) { allow.tap() }
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func profile(_ app: XCUIApplication) {
        let button = app.buttons["openProfile"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        let ready = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: button)
        wait(for: [ready], timeout: 10)
        button.tap()
        XCTAssertTrue(app.navigationBars["Profile & settings"].waitForExistence(timeout: 15))
    }
    private func openWeight(_ app: XCUIApplication) {
        let card = app.buttons["todayWeight"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        // All weight scenarios include historical readings. Wait for those to
        // arrive before scrolling, since they resize the Today layout.
        XCTAssertTrue(app.buttons["View weight chart"].waitForExistence(timeout: 15))
        let viewport = app.frame
        let readableArea = (viewport.minY + viewport.height * 0.2)...(viewport.minY + viewport.height * 0.78)
        let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.40))
        let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.66))
        for _ in 0..<20 {
            let y = card.frame.midY
            if readableArea.contains(y) && card.isHittable { break }
            if y > readableArea.upperBound {
                lower.press(forDuration: 0.05, thenDragTo: upper)
            } else {
                upper.press(forDuration: 0.05, thenDragTo: lower)
            }
        }
        XCTAssertTrue(card.isHittable)
        XCTAssertTrue(readableArea.contains(card.frame.midY))
        shot(app, "Compact Today weight card")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
    }
    /// Seed a synthetic connected HealthSync journal with exportWeight=true on the
    /// UI-REVIEW simulator before running. Never run against a personal connection.
    func testConnectedWeightSwitchSavesWithoutConfirmation() throws {
        let app = launch(); profile(app)
        app.buttons["Apple Health"].tap()
        XCTAssertTrue(app.navigationBars["Apple Health"].waitForExistence(timeout: 5))
        let toggle = app.switches["Export weight"]
        for _ in 0..<20 {
            if toggle.exists && toggle.isHittable && toggle.frame.midY < app.frame.maxY - 50 && toggle.frame.minY > 90 { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        try XCTSkipIf(toggle.value as? String != "1", "Requires a synthetic connected journal with weight export enabled")
        XCTAssertFalse(app.buttons["Update permissions"].exists)
        XCTAssertTrue(NSPredicate(format: "enabled == true").evaluate(with: toggle))
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let saved = expectation(for: NSPredicate(format: "value == '0' AND enabled == true"), evaluatedWith: toggle)
        wait(for: [saved], timeout: 15)
        shot(app, "Health switch saved directly")
        app.terminate()
        let reopened = launch(); profile(reopened)
        reopened.buttons["Apple Health"].tap()
        for _ in 0..<20 {
            let control = reopened.switches["Export weight"]
            if control.exists && control.isHittable && control.frame.midY < reopened.frame.maxY - 50 && control.frame.minY > 90 { break }
            reopened.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05, thenDragTo: reopened.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        XCTAssertTrue(reopened.switches["Export weight"].waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.switches["Export weight"].value as? String, "0")
        XCTAssertFalse(reopened.buttons["Update permissions"].exists)
        shot(reopened, "Health switch remains saved after relaunch")
    }
    func testWeightRangesOptionsAndImportNavigation() {
        let app = launch(serial: "WEIGHT-CHART-" + UUID().uuidString); openWeight(app)
        XCTAssertTrue(app.segmentedControls.buttons["Month"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Recent weigh-ins"].exists)
        XCTAssertFalse(app.staticTexts["This week’s check-ins"].exists)
        XCTAssertFalse(app.buttons["openWeightImport"].exists)
        let monthDates = app.staticTexts["weightChartDates"].label
        app.segmentedControls.buttons["Week"].tap()
        XCTAssertNotEqual(app.staticTexts["weightChartDates"].label, monthDates)
        app.segmentedControls.buttons["All"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["All"].isSelected)
        shot(app, "Weight trend all history")
        let chart = app.descendants(matching: .any)["Weight chart"].firstMatch
        XCTAssertTrue(chart.exists)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Selected weigh-in"), object: app.staticTexts["weightChartHeadline"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        let latest = app.buttons["weightChartLatest"]
        XCTAssertTrue(latest.isEnabled && latest.isHittable)
        shot(app, "Selected weight measurement")
        latest.tap()
        XCTAssertFalse(app.buttons["weightChartLatest"].exists)
        app.buttons["Weight options"].tap()
        XCTAssertTrue(app.switches["weightMovingAverage"].waitForExistence(timeout: 5))
        app.switches["weightMovingAverage"].tap()
        let importAction = app.buttons["importWeightFromOptions"]
        XCTAssertTrue(importAction.waitForExistence(timeout: 5))
        importAction.press(forDuration: 0.1)
        XCTAssertTrue(app.navigationBars["Import weight history"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirmWeightImport"].exists)
        shot(app, "Weight import setup")
        app.buttons["Close"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
    }
    private func savedWeights(_ serial: String) async throws -> [[String: Any]] {
        let base = ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28476"
        let (data, _) = try await URLSession.shared.data(from: URL(string: base + "/v1/devices/" + serial + "/weights")!)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }
    func testLoggedDayOpensExistingWeightForEditing() async throws { try await checkExistingWeightEdit(large: false) }
    func testLoggedDayEditAtLargeText() async throws { try await checkExistingWeightEdit(large: true) }
    private func checkExistingWeightEdit(large: Bool) async throws {
        let serial = "WEIGHT-MANUAL-" + UUID().uuidString
        let before = try await savedWeights(serial)
        let app = launch(large: large, serial: serial); openWeight(app)
        XCTAssertFalse(app.buttons["logWeight"].exists)
        app.buttons["openWeightReading"].tap()
        let input = app.textFields["weightInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Edit weight"].exists)
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        if let value = input.value as? String { input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        input.typeText("81.4")
        app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["logWeight"].exists)
        var after = try await savedWeights(serial)
        for _ in 0..<50 where after.first(where: { $0["id"] as? String == "snoop:layout-0" })?["kg"] as? Double != 81.4 {
            try await Task.sleep(for: .milliseconds(100)); after = try await savedWeights(serial)
        }
        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after.first(where: { $0["id"] as? String == "snoop:layout-0" })?["kg"] as? Double, 81.4)
        shot(app, "Daily weight edited without an extra log")
    }
    func testFirstDailyLogRemovesAddAndImportedDayIsReadOnly() async throws {
        let serial = "WEIGHT-EMPTY-" + UUID().uuidString
        let before = try await savedWeights(serial)
        let app = launch(serial: serial); openWeight(app)
        XCTAssertTrue(app.buttons["logWeight"].waitForExistence(timeout: 5)); app.buttons["logWeight"].tap()
        XCTAssertTrue(app.buttons["saveWeight"].waitForExistence(timeout: 5)); app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["logWeight"].exists)
        app.buttons["openWeightReading"].tap()
        XCTAssertTrue(app.navigationBars["Edit weight"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        var after = try await savedWeights(serial)
        for _ in 0..<50 where after.count == before.count {
            try await Task.sleep(for: .milliseconds(100)); after = try await savedWeights(serial)
        }
        XCTAssertEqual(after.count, before.count + 1)
        app.terminate()
        let imported = launch(serial: "WEIGHT-HEALTH-" + UUID().uuidString); openWeight(imported)
        XCTAssertFalse(imported.buttons["logWeight"].exists)
        imported.buttons["openWeightReading"].tap()
        XCTAssertTrue(imported.staticTexts["Edit this measurement in Apple Health."].waitForExistence(timeout: 5))
        XCTAssertFalse(imported.buttons["saveWeight"].exists)
        XCTAssertFalse(imported.textFields["weightInput"].exists)
        shot(imported, "Imported weight remains owned by Health")
    }
    func testWeightCSVShareSheet() { checkWeightCSVShareSheet(large: false) }
    func testWeightCSVShareSheetAtLargeText() { checkWeightCSVShareSheet(large: true) }
    private func checkWeightCSVShareSheet(large: Bool) {
        let app = launch(large: large, serial: "UI-CSV-REVIEW"); openWeight(app)
        app.buttons["Weight options"].tap()
        let export = app.buttons["exportWeightCSV"]
        for _ in 0..<12 {
            if export.exists && export.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        shot(app, "Weight CSV export option")
        export.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10))
        shot(app, "Weight CSV share sheet")
    }
    func testSwipingHistoryAndReturningToLatest() {
        // Keep chart navigation independent of an older simulator's Health journal.
        let app = launch(serial: "WEIGHT-CHART-" + UUID().uuidString); openWeight(app)
        XCTAssertTrue(app.segmentedControls.buttons["Month"].waitForExistence(timeout: 10))
        let dates = app.staticTexts["weightChartDates"]
        let latestDates = dates.label
        XCTAssertTrue(app.descendants(matching: .any)["weightChartValue"].firstMatch.label.contains("kg"))
        shot(app, "Current weight period")
        let chart = app.descendants(matching: .any)["Weight chart"].firstMatch
        chart.swipeRight()
        XCTAssertTrue(NSPredicate(format: "label != %@", latestDates).evaluate(with: dates))
        let olderDates = dates.label
        XCTAssertTrue(app.buttons["weightChartLatest"].exists)
        shot(app, "Earlier weight period")
        app.segmentedControls.buttons["Week"].tap()
        XCTAssertTrue(dates.label.contains(" – "))
        app.segmentedControls.buttons["Month"].tap()
        XCTAssertEqual(dates.label, olderDates)
        chart.swipeLeft()
        XCTAssertNotEqual(dates.label, olderDates)
        if app.buttons["weightChartLatest"].exists { app.buttons["weightChartLatest"].tap() }
        XCTAssertEqual(dates.label, latestDates)
        chart.swipeLeft()
        XCTAssertEqual(dates.label, latestDates)
        chart.tap()
        XCTAssertTrue(app.buttons["weightChartLatest"].waitForExistence(timeout: 5))
        let left = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let right = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        left.press(forDuration: 0.35, thenDragTo: right)
        XCTAssertEqual(app.staticTexts["weightChartHeadline"].label, "Selected weigh-in")
        XCTAssertEqual(dates.label, latestDates)
        shot(app, "Held finger inspects without paging")
        app.buttons["weightChartLatest"].tap()
        XCTAssertFalse(app.buttons["weightChartLatest"].exists)
        app.segmentedControls.buttons["Week"].tap()
        let week = dates.label
        chart.swipeRight()
        XCTAssertNotEqual(dates.label, week)
        app.buttons["weightChartLatest"].tap()
        XCTAssertEqual(dates.label, week)
        app.segmentedControls.buttons["3 months"].tap()
        shot(app, "Three calendar months")
        app.buttons["Weight options"].tap()
        app.buttons["weightHistory"].tap()
        XCTAssertTrue(app.navigationBars["All weigh-ins"].waitForExistence(timeout: 5))
    }
    func testWeightEntryHistoryAndHealthSettings() {
        let app = launch(serial: "WEIGHT-EMPTY-" + UUID().uuidString); openWeight(app)
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        app.buttons["logWeight"].tap()
        let field = app.textFields["weightInput"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        if let value = field.value as? String, value != "Weight", !value.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count)) }
        field.typeText("81.4"); shot(app, "Focused weight entry"); app.buttons["saveWeight"].tap()
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        app.buttons["Weight options"].tap()
        app.buttons["weightHistory"].tap()
        XCTAssertTrue(app.navigationBars["All weigh-ins"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["81.4 kg"].firstMatch.waitForExistence(timeout: 10))
        shot(app, "Weight history")
        app.navigationBars["All weigh-ins"].buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        app.navigationBars["Weight"].buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["todayLogWeight"].exists)
        XCTAssertTrue(app.buttons["todayWeight"].firstMatch.label.contains("81.4"))
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
        let app = launch(large: true, serial: "WEIGHT-EMPTY-" + UUID().uuidString); openWeight(app)
        XCTAssertTrue(app.navigationBars["Weight"].waitForExistence(timeout: 5))
        let log = app.buttons["logWeight"]
        // isHittable can be true while the button's centre is under the tab bar.
        for _ in 0..<6 where log.frame.maxY >= app.buttons["tab-Today"].frame.minY - 20 { app.swipeUp() }
        XCTAssertTrue(log.isHittable)
        shot(app, "Weight accessibility text")
        app.buttons["logWeight"].tap()
        XCTAssertTrue(app.textFields["weightInput"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveWeight"].isHittable)
        shot(app, "Weight entry accessibility text")
        app.buttons["Cancel"].tap()
        app.buttons["Weight options"].tap()
        let history = app.buttons["weightHistory"]
        for _ in 0..<8 { if history.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(history.isHittable)
        shot(app, "Weight accessibility chart and history")
        history.tap()
        XCTAssertTrue(app.navigationBars["All weigh-ins"].waitForExistence(timeout: 5))
        shot(app, "Weight history accessibility text")
        app.navigationBars["All weigh-ins"].buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
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
