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
        app.buttons["Retry"].tap()  // reloads, fails again, error screen comes back
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 15))
    }

    /// The back button must sit above the page, not float over its content.
    @MainActor func testBackButtonDoesNotCoverThePage() {
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        let chip = app.links["ICE"].firstMatch  // league chip in the hero opens the league page
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        chip.tap()
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertLessThanOrEqual(back.frame.maxY, web.frame.minY + 1, "back button overlaps the web view")
    }
}
