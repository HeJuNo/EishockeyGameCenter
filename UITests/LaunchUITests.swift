import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Eishockey GameCenter"].waitForExistence(timeout: 10))
    }
}
