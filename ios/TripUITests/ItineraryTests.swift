import XCTest

final class ItineraryTests: XCTestCase {
    func testJerryCanOpenHisItineraryFromRegionalPlan() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.navigationBars["Manila"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.staticTexts["Find your PCA match time"].waitForExistence(timeout: 12))
        XCTAssertFalse(app.staticTexts["Choose Japan dates after PCA"].exists)
        XCTAssertEqual(app.segmentedControls.count, 0)

        let more = app.buttons["trip-menu"]
        more.tap()
        let itinerary = app.buttons["Itinerary"]
        XCTAssertTrue(itinerary.waitForExistence(timeout: 5))
        itinerary.tap()
        XCTAssertTrue(app.navigationBars["Itinerary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ITF J30 Manila"].exists)
        XCTAssertTrue(app.staticTexts["PCA Open qualifying"].exists)
        XCTAssertTrue(app.staticTexts["Japan"].exists)

        app.navigationBars["Itinerary"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Manila"].waitForExistence(timeout: 5))
        more.tap()
        app.buttons["Tom’s trip"].tap()
        XCTAssertTrue(app.staticTexts["Tom’s updates"].waitForExistence(timeout: 5))
        XCTAssertFalse(itinerary.exists)
    }

    func testAgassiSourcePlaysInsideTrip() {
        let app = XCUIApplication()
        app.launchArguments = ["-testOfficialYouTubePlayback"]
        app.launch()
        app.buttons["trip-menu"].tap()
        app.buttons["Trip plans"].tap()
        app.buttons["trip-region-Manila"].tap()
        let clip = app.buttons["Watch Agassi at 9:37"]
        for _ in 0..<5 where !clip.isHittable { app.swipeUp() }
        XCTAssertTrue(clip.isHittable)
        clip.tap()
        let close = app.buttons["closeOfficialYouTube"]
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        let play = app.webViews.buttons["Play video"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 20))
        play.tap()
        let playback = app.staticTexts["officialYouTubePlaybackTime"]
        let started = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let time = Double(playback.label) else { return false }
            return (574...581).contains(time)
        }, object: playback)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 15), .completed)
        XCTAssertEqual(app.state, .runningForeground)
        close.tap()
        XCTAssertTrue(clip.waitForExistence(timeout: 8))
    }
}
