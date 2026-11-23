import XCTest

extension XCUIApplication {
    /// Every synthetic launch gets an explicit appearance. Accessibility and light
    /// appearance tests can override these without leaking assumptions into later tests.
    @MainActor func launchSynthetic() {
        if !launchArguments.contains("-UIPreferredContentSizeCategoryName") {
            launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        if !launchArguments.contains("-AppleInterfaceStyle") {
            launchArguments += ["-AppleInterfaceStyle", "Dark"]
        }
        launch()
    }
}
