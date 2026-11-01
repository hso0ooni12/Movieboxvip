import XCTest

final class WatchedNativeUITests: XCTestCase {
    @MainActor
    func testNativeBrowseAndDetailScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-preview"]
        app.launch()
        let details = app.buttons["hero-details-0"]
        let detailsLink = app.links["hero-details-0"]
        XCTAssertTrue(details.waitForExistence(timeout: 12) || detailsLink.waitForExistence(timeout: 3))
        capture("01-native-home")
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["Live TV"].exists)
        XCTAssertFalse(app.tabBars.buttons["القنوات"].exists)
        if details.exists { details.tap() } else { detailsLink.tap() }
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 7))
        capture("02-native-details")
        XCTAssertTrue(app.buttons["play-title"].exists)
        app.buttons["play-title"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        // A browsing preview must clearly report that playback is pending, rather than open a website.
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "النسخة التجريبية")).firstMatch.exists)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
