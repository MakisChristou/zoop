import XCTest

/// Run against synthetic history only; records visual attachments and interaction metrics.
@MainActor final class PerformanceNavigationTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", "UI-REVIEW", "-serverURL", ProcessInfo.processInfo.environment["SNOOP_UI_SERVER_URL"] ?? "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "trends"]
        app.launch(); return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testTrendsScrollingSwitchingAndReturning() {
        let app = launch()
        XCTAssertTrue(app.buttons["HRV"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["trendReadingDate"].waitForExistence(timeout: 15))
        shot(app,"Trends initial")
        for range in ["3 months","Year","Month"] {
            let choice = app.segmentedControls.buttons[range]
            XCTAssertTrue(choice.exists); choice.tap()
        }
        app.buttons["HRV"].tap()
        shot(app,"Trends HRV")
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            app.swipeUp(); app.swipeDown()
        }
        app.buttons["tab-Today"].tap()
        XCTAssertTrue(app.buttons["Previous day"].waitForExistence(timeout: 15))
        app.buttons["Previous day"].tap()
        XCTAssertTrue(app.staticTexts["Yesterday"].waitForExistence(timeout: 10))
        shot(app,"Today previous day")
        app.buttons["tab-Trends"].tap()
        XCTAssertTrue(app.buttons["HRV"].waitForExistence(timeout: 10))
        shot(app,"Trends restored")
    }
}
