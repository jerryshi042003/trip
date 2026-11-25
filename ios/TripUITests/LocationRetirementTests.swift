import XCTest

final class LocationRetirementTests: XCTestCase {
    func testPreviousSharingPreferenceCannotExposeLocationControls() {
        let app = XCUIApplication()
        app.launchArguments += ["-shareLocation", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["section-Plan"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["section-Where"].exists)
        XCTAssertFalse(app.buttons["Share my location"].exists)
        app.buttons["section-Places"].tap()
        XCTAssertTrue(app.navigationBars["Places"].waitForExistence(timeout: 10))
    }
}
