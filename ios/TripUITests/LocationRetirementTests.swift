import XCTest

final class LocationRetirementTests: XCTestCase {
    func testPreviousSharingPreferenceCannotExposeLocationControls() {
        let app = XCUIApplication()
        app.launchArguments += ["-shareLocation", "YES"]
        app.launch()
        let menu = app.buttons["trip-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["section-Plan"].exists)
        XCTAssertFalse(app.buttons["section-Where"].exists)
        XCTAssertFalse(app.buttons["Share my location"].exists)
        menu.tap()
        XCTAssertFalse(app.buttons["Where"].exists)
        app.buttons["Places"].tap()
        XCTAssertTrue(app.navigationBars["Places"].waitForExistence(timeout: 10))
    }
}
