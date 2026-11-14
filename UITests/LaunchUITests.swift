import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor func testGameCenterLoads() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))
    }

    @MainActor func testOfflineShowsRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-startURL", "https://game-center.invalid/"]
        app.launch()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 15))
    }
}
