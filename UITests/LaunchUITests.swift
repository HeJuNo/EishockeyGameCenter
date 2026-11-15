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
        XCTAssertTrue(back.waitForExistence(timeout: 40))
        XCTAssertGreaterThanOrEqual(back.frame.minY, web.frame.minY, "back button must be inside the page, not above it")
        back.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: back)
        wait(for: [gone], timeout: 10)  // back on the start page, the button is hidden again
    }

    /// The settings button opens the menu; the choice is kept.
    @MainActor func testSettingsMenuKeepsTheAppearanceChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearance", "system"]
        app.launch()
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 40), "settings button on the start page")
        XCTAssertTrue(app.links["ICE"].firstMatch.waitForExistence(timeout: 40), "start page content")   // a tap while the page still loads is dropped
        gear.tap()
        let dark = app.buttons["Dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["System"].isSelected)
        dark.tap()
        app.buttons["Done"].tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Done"])
        wait(for: [closed], timeout: 5)
        gear.tap()
        XCTAssertTrue(app.buttons["Dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Dark"].isSelected, "the choice is still Dark")
    }

    private func openSettings(_ app: XCUIApplication) {
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 40), "settings button on the start page")
        XCTAssertTrue(app.links["ICE"].firstMatch.waitForExistence(timeout: 40), "start page content")   // a tap while the page still loads is dropped
        gear.tap()
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    }

    /// A watched page is listed in the settings and can be stopped there.
    @MainActor func testWatchedPageShowsInSettingsAndCanBeStopped() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearance", "system", "-watchSeed", "game"]
        app.launch()
        openSettings(app)
        let row = app.staticTexts["Seed game"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.swipeLeft()
        app.buttons["Stop watching"].tap()
        let empty = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Nothing watched yet'")).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
    }

    @MainActor func testCategorySwitchesExist() {
        let app = XCUIApplication()
        app.launchArguments = ["-appearance", "system", "-watchSeed", "none"]
        app.launch()
        openSettings(app)
        for title in ["Scores and game start/end", "Lineups", "Statistics and tables"] {
            XCTAssertTrue(app.switches[title].waitForExistence(timeout: 5), title)
        }
        app.swipeUp()   // the lists below the fold
        XCTAssertTrue(app.buttons["Check now"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Load all list entries"].exists)
    }
}
