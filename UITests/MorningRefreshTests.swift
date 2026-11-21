import XCTest

/// The synthetic server stays Updating for fifteen seconds, then returns ready.
/// The comparisons detail must refresh without a manual reload.
@MainActor final class MorningRefreshTests: XCTestCase {
    func testComparisonsLeaveUpdatingWithoutPullToRefresh() {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "MORNING-REFRESH-\(UUID().uuidString)",
            "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28479",
            "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "today"]
        app.launch()
        let link = app.buttons["openMorningInsights"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        for _ in 0..<12 where !link.isHittable { app.swipeUp() }
        link.tap()
        let status = app.staticTexts["morningOutlookStatus"].firstMatch
        XCTAssertTrue(app.descendants(matching: .any)["morningInsightsLoading"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Updating"].exists)
        let ready = NSPredicate(format: "exists == true AND label == %@", "Learning")
        expectation(for: ready, evaluatedWith: status)
        waitForExpectations(timeout: 25)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Morning outlook refreshed automatically"; image.lifetime = .keepAlways; add(image)
        XCTAssertTrue(app.navigationBars["Morning insights"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["morningOutlookStatus"].firstMatch.label, "Learning")
    }
}
