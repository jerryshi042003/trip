import XCTest

final class JapanShopMapTests: XCTestCase {
    func testNamedShopsShowTheirOwnProductsAndDistance() {
        let app = XCUIApplication()
        app.launch()
        let menu = app.buttons["trip-menu"]
        XCTAssertTrue(menu.waitForExistence(timeout: 12))
        menu.tap()
        app.buttons["Japan shop map"].tap()

        let shop = app.staticTexts["shop-detail-name"]
        XCTAssertTrue(shop.waitForExistence(timeout: 12))
        XCTAssertEqual(shop.label, "Windsor Shinjuku")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "¥2,277")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["shop-detail-distance"].label.contains("from Tokyo Station"))

        let snapshot = XCTAttachment(screenshot: app.screenshot())
        snapshot.name = "Windsor Shinjuku on Apple Maps"
        snapshot.lifetime = .keepAlways
        add(snapshot)

        let tabio = app.buttons["shop-tabio-daimaru-tokyo"]
        XCTAssertTrue(tabio.isHittable)
        tabio.tap()
        XCTAssertEqual(shop.label, "Tabio MEN · Daimaru Tokyo")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "¥1,100")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "¥2,277")).firstMatch.exists)

        let xebio = app.buttons["shop-xebio-kawasaki"]
        XCTAssertTrue(xebio.isHittable)
        xebio.tap()
        XCTAssertEqual(shop.label, "Xebio Kawasaki Le Front")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "¥2,420")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["shop-detail-distance"].label.contains("from Tokyo Station"))

        let kawasaki = XCTAttachment(screenshot: app.screenshot())
        kawasaki.name = "Xebio Kawasaki on Apple Maps"
        kawasaki.lifetime = .keepAlways
        add(kawasaki)
    }
}
