import XCTest

/// The synthetic server stays Updating for eight seconds, then returns ready.
/// The old five-minute Today refresh cannot pass this regression test.
@MainActor final class MorningRefreshTests: XCTestCase {
    func testTodayLeavesUpdatingWithoutPullToRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "MORNING-REFRESH-\(UUID().uuidString)",
            "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28479",
            "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "today"]
        app.launch()
        let status = app.staticTexts["morningOutlookStatus"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(status.label, "Updating")
        let ready = NSPredicate(format: "label == %@", "Learning")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 20)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Morning outlook refreshed automatically"; image.lifetime = .keepAlways; add(image)
        app.buttons["openMorningInsights"].tap()
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["morningOutlookStatus"].firstMatch.label, "Learning")
    }
}
