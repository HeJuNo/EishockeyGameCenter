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

    /// The back button sits inside the page's tab bar and brings you back to the start page.
    @MainActor func testBackButtonInTabBarGoesBack() {
        let app = XCUIApplication()
        app.launch()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 15))
        let chip = app.links["ICE"].firstMatch  // league chip in the hero opens the league page
        XCTAssertTrue(chip.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["Back"].exists, "no back button on the start page")
        chip.tap()
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(back.frame.minY, web.frame.minY, "back button must be inside the page, not above it")
        back.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: back)
        wait(for: [gone], timeout: 10)  // back on the start page, the button is hidden again
    }
}
