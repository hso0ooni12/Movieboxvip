import XCTest

final class WatchedNativeUITests: XCTestCase {
    @MainActor
    func testNativeBrowseAndDetailScreens() {
        let app = launchPreview()
        openFirstMovie(app)
        capture("02-native-details")
        XCTAssertTrue(app.buttons["play-title"].exists)
        app.buttons["play-title"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.webViews.staticTexts["/movie/1400940"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("03-website-player-offline-navigation-test")
        app.buttons["close-site-player"].tap()
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    @MainActor
    func testWebsiteBackSPAAndFullscreenDoneReturnToAppInsteadOfWebsite() {
        let app = launchPreview()
        openFirstMovie(app)
        for label in ["Back", "SPA Back", "Fullscreen Done"] {
            app.buttons["play-title"].tap()
            let button = app.webViews.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 8), "Missing fixture control: \(label)")
            button.tap()
            XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 6), "\(label) should dismiss into the original detail screen")
            XCTAssertFalse(app.webViews.firstMatch.exists)
            XCTAssertEqual(app.staticTexts["detail-title"].label, "Clayface")
        }
    }

    @MainActor
    func testEpisodeOpensExactWebsitePlayerAndClosePreservesEpisodeList() {
        let app = launchPreview()
        app.tabBars.buttons["المسلسلات"].tap()
        let show = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Lupin,")).firstMatch
        let showLink = app.links.matching(NSPredicate(format: "label BEGINSWITH %@", "Lupin,")).firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 8) || showLink.waitForExistence(timeout: 3))
        if show.exists { show.tap() } else { showLink.tap() }
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 6))
        let episode = app.buttons["play-episode-1-2"]
        for _ in 0..<4 { if episode.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(episode.isHittable)
        episode.tap()
        XCTAssertTrue(app.webViews.staticTexts["/tv/96677?s=1&e=2"].waitForExistence(timeout: 8))
        app.buttons["close-site-player"].tap()
        XCTAssertTrue(episode.waitForExistence(timeout: 6))
        XCTAssertTrue(episode.isHittable)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        episode.tap()
        XCTAssertTrue(app.webViews.staticTexts["/tv/96677?s=1&e=2"].waitForExistence(timeout: 8))
        app.buttons["close-site-player"].tap()
    }

    @MainActor
    private func launchPreview() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-preview"]
        app.launch()
        return app
    }

    @MainActor
    private func openFirstMovie(_ app: XCUIApplication) {
        let details = app.buttons["hero-details-0"]
        let detailsLink = app.links["hero-details-0"]
        XCTAssertTrue(details.waitForExistence(timeout: 12) || detailsLink.waitForExistence(timeout: 3))
        capture("01-native-home")
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        XCTAssertFalse(app.tabBars.buttons["Live TV"].exists)
        XCTAssertFalse(app.tabBars.buttons["القنوات"].exists)
        if details.exists { details.tap() } else { detailsLink.tap() }
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 7))
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
