import XCTest

@MainActor final class TodayHealthTilesTests: XCTestCase {
    private func open(large: Bool = false, empty: Bool = false, device: String = "INSIGHT-REVIEW") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSerial", empty ? "RINGS-EMPTY" : device, "-serverURL", "http://127.0.0.1:28476", "-ingestToken", "ui-test-token", "-onboarded", "YES", "-demoScreen", "",
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launch()
        let tile = app.buttons["todayHealth-hrv"]
        XCTAssertTrue(app.buttons["openSleepSummary"].waitForExistence(timeout: 20))
        for _ in 0..<12 where !tile.exists || !tile.isHittable { app.swipeUp() }
        XCTAssertTrue(tile.exists)
        return app
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testNightlyValuesAndAlignedTiles() {
        let app = open()
        let temperature = app.buttons["todayHealth-temperature"]
        for _ in 0..<6 where !temperature.isHittable { app.swipeUp() }
        let hrv = app.buttons["todayHealth-hrv"], rhr = app.buttons["todayHealth-restingHR"]
        XCTAssertEqual(hrv.frame.minY, rhr.frame.minY, accuracy: 1)
        XCTAssertEqual(hrv.frame.width, rhr.frame.width, accuracy: 1)
        XCTAssertEqual(hrv.frame.height, rhr.frame.height, accuracy: 1)
        XCTAssertTrue(hrv.label.contains("72 ms"))
        XCTAssertTrue(rhr.label.contains("54 bpm"))
        XCTAssertTrue(app.buttons["todayHealth-breathing"].label.contains("14.3 /min"))
        XCTAssertTrue(app.buttons["todayHealth-oxygen"].label.contains("98 %"))
        XCTAssertTrue(temperature.label.contains("33.4 °C"))
        shot(app, "Today compact health tiles")
        hrv.tap()
        XCTAssertTrue(app.buttons["insightMetric_hrv"].waitForExistence(timeout: 10))
    }
    func testLargeTextUsesSingleColumn() {
        let app = open(large: true)
        let hrv = app.buttons["todayHealth-hrv"], rhr = app.buttons["todayHealth-restingHR"]
        XCTAssertGreaterThan(rhr.frame.minY, hrv.frame.minY)
        XCTAssertEqual(hrv.frame.minX, rhr.frame.minX, accuracy: 1)
        app.swipeUp()
        shot(app, "Health tiles large text")
        let temperature = app.buttons["todayHealth-temperature"]
        for _ in 0..<8 where !temperature.isHittable { app.swipeUp() }
        XCTAssertTrue(temperature.isHittable)
        XCTAssertLessThanOrEqual(temperature.frame.maxX, app.frame.maxX)
        shot(app, "Health tiles large text lower readings")
    }
    func testNightlyCardiacReadingsSurviveUnavailableOutlook() {
        // This scope deliberately returns an insights error but valid nightly measurements.
        let app = open(device: "SLEEP-COMPARISON")
        let hrv = app.buttons["todayHealth-hrv"], rhr = app.buttons["todayHealth-restingHR"]
        XCTAssertTrue(hrv.label.contains("75 ms"))
        XCTAssertTrue(rhr.label.contains("55 bpm"))
        XCTAssertFalse(hrv.label.contains("+18%"))
        shot(app, "Nightly HRV and resting HR without outlook")
    }
    func testMissingReadingsStayMissing() {
        let app = open(empty: true)
        let temperature = app.buttons["todayHealth-temperature"]
        for _ in 0..<6 where !temperature.isHittable { app.swipeUp() }
        for key in ["hrv", "restingHR", "breathing", "oxygen", "temperature"] {
            XCTAssertTrue(app.buttons["todayHealth-" + key].label.contains("—"))
        }
        shot(app, "Health tiles without readings")
    }
}
