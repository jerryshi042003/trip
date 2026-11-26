import XCTest

final class ItineraryTests: XCTestCase {
    func testJerryCanOpenHisItineraryFromRegionalPlan() {
        let app = XCUIApplication()
        app.launch()

        let travelers = app.segmentedControls.firstMatch
        let jerry = travelers.buttons["Jerry"]
        XCTAssertTrue(jerry.waitForExistence(timeout: 12))
        if !jerry.isSelected { jerry.tap() }

        let itinerary = app.buttons["traveler-itinerary"]
        XCTAssertTrue(itinerary.waitForExistence(timeout: 12))
        itinerary.tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ITF J30 Manila"].exists)
        XCTAssertTrue(app.staticTexts["PCA Open qualifying"].exists)
        XCTAssertTrue(app.staticTexts["Japan"].exists)

        app.navigationBars["Itinerary"].buttons.firstMatch.tap()
        XCTAssertTrue(itinerary.waitForExistence(timeout: 5))
        travelers.buttons["Tom"].tap()
        XCTAssertTrue(app.staticTexts["Tom’s updates"].waitForExistence(timeout: 5))
        XCTAssertFalse(itinerary.exists)
    }
}
