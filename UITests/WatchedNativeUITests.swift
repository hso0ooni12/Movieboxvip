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
        // UI snapshots never make external playback requests or substitute sample video.
        XCTAssertTrue(app.alerts.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "معاينة الواجهة")).firstMatch.exists)
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testSourceVerificationIsExplicitAndCanBeCancelled() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-preview", "-verification-ui-preview"]
        app.launch()
        let details = app.buttons["hero-details-0"]
        XCTAssertTrue(details.waitForExistence(timeout: 12))
        details.tap()
        let play = app.buttons["play-title"]
        XCTAssertTrue(play.waitForExistence(timeout: 6)); play.tap()
        let verify = app.alerts.buttons["التحقق من المصدر"]
        XCTAssertTrue(verify.waitForExistence(timeout: 4)); verify.tap()
        let complete = app.buttons["source-verification-complete"]
        XCTAssertTrue(complete.waitForExistence(timeout: 8))
        XCTAssertFalse(complete.isEnabled)
        capture("03-native-source-verification-ui-preview")
        app.navigationBars.buttons["إلغاء"].tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 5))
    }
}
