import XCTest

final class WatchedNativeUITests: XCTestCase {
    @MainActor
    func testSystemSafariCloseReturnsDirectlyToOriginalNativeDetails() {
        let app = launchPreview()
        openFirstMovie(app)
        capture("02-native-details")
        app.buttons["play-title"].tap()
        XCTAssertTrue(browserText("/movie/1400940", in: app).waitForExistence(timeout: 12))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("03-real-system-safari-offline-fixture")
        closeSafari(in: app)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detail-title"].label, "Clayface")
        XCTAssertFalse(app.webViews.firstMatch.exists)
    }

    @MainActor
    func testWebsiteNavigationStillAllowsSystemCloseToReturnToApp() {
        let app = launchPreview()
        openFirstMovie(app)
        app.buttons["play-title"].tap()
        XCTAssertTrue(browserText("/movie/1400940", in: app).waitForExistence(timeout: 12))
        let back = app.webViews.links["Website back"]
        if back.waitForExistence(timeout: 3) { back.tap() }
        else { XCUIApplication(bundleIdentifier: "com.apple.SafariViewService").webViews.links["Website back"].tap() }
        XCTAssertTrue(browserText("Offline browser navigation fixture", in: app).waitForExistence(timeout: 10))
        closeSafari(in: app)
        XCTAssertTrue(app.staticTexts["detail-title"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detail-title"].label, "Clayface")
    }

    @MainActor
    func testEpisodeOpensExactURLAndClosingPreservesListAndReopening() {
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
        for _ in 0..<2 {
            episode.tap()
            XCTAssertTrue(browserText("/tv/96677?s=1&e=2", in: app).waitForExistence(timeout: 12))
            closeSafari(in: app)
            XCTAssertTrue(episode.waitForExistence(timeout: 8))
            XCTAssertTrue(episode.isHittable)
        }
    }

    @MainActor
    private func browserText(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let local = app.webViews.staticTexts[label]
        if local.waitForExistence(timeout: 3) { return local }
        return XCUIApplication(bundleIdentifier: "com.apple.SafariViewService").webViews.staticTexts[label]
    }

    @MainActor
    private func closeSafari(in app: XCUIApplication) {
        let predicate = NSPredicate(format: "label IN %@", ["Close", "Done", "Dismiss", "إغلاق", "تم"])
        let local = app.buttons.matching(predicate).firstMatch
        if local.waitForExistence(timeout: 4) { local.tap(); return }
        let system = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService").buttons.matching(predicate).firstMatch
        XCTAssertTrue(system.waitForExistence(timeout: 6)); system.tap()
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
