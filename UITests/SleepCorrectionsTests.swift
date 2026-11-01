import XCTest

/// Uses only the isolated fake UI-REVIEW readings from the backend fixture.
final class SleepCorrectionsTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28472", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "sleep"]
        app.launch(); return app
    }
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testEditMergeResetAndUndoSleep() {
        let app = launch()
        let options = app.buttons["Sleep options"]
        XCTAssertTrue(options.waitForExistence(timeout: 20)); options.tap()
        app.buttons["Edit sleep"].tap()
        XCTAssertTrue(app.staticTexts["Fell asleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Woke up"].exists)
        screenshot(app, "Sleep editor matches Today")
        app.buttons["saveSleep"].tap()
        XCTAssertTrue(options.waitForExistence(timeout: 20)); options.tap(); app.buttons["Merge sleep"].tap()
        let neighbour = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Nap,'")).firstMatch
        XCTAssertTrue(neighbour.waitForExistence(timeout: 10)); neighbour.tap()
        screenshot(app, "Merge sleep with missing readings")
        app.buttons["saveSleep"].tap()
        XCTAssertTrue(options.waitForExistence(timeout: 20))
        assertMergedPeriod()
        options.tap(); app.buttons["Reset to automatic"].tap()
        app.buttons["Review reset"].tap()
        XCTAssertTrue(app.buttons["confirmAnalysisReset"].waitForExistence(timeout: 10))
        screenshot(app, "Review reversible reset")
        app.buttons["confirmAnalysisReset"].tap()
        let undo = app.buttons["Undo reset"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 20))
        screenshot(app, "Reset saved with Undo")
        undo.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Reset undone' OR label == 'History updated'")).firstMatch.waitForExistence(timeout: 20))
        app.buttons["Done"].tap()
        XCTAssertTrue(options.waitForExistence(timeout: 20))
    }
    private func assertMergedPeriod() {
        let base = ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28472"
        var request = URLRequest(url: URL(string: base + "/v1/devices/UI-REVIEW/sleep-sessions")!)
        request.setValue("Bearer ui-test-token", forHTTPHeaderField: "Authorization")
        let done = expectation(description: "Saved merged sleep")
        URLSession.shared.dataTask(with: request) { data, _, error in
            XCTAssertNil(error)
            let rows = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[String: Any]] } ?? []
            let edited = rows.first { $0["kind"] as? String == "main" && $0["edited"] as? Bool == true }
            XCTAssertEqual(edited?["duration_s"] as? Int, 9000, "Merge the nearest fragment from this night")
            done.fulfill()
        }.resume()
        wait(for: [done], timeout: 10)
    }
}
