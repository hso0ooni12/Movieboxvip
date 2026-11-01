import SafariServices
import XCTest
@testable import WatchedNative

final class SitePlaybackTests: XCTestCase {
    func testEpisodeUsesDirectPublicWatchURLAndSelectedEpisode() throws {
        let title = try XCTUnwrap(MediaTitle(site: ["id": 125988, "name": "Silo", "media_type": "tv"]))
        let request = SitePlaybackRequest(title: title, season: 2, episode: 3)
        XCTAssertEqual(request.url.absoluteString, "https://watched.cx/tv/125988?s=2&e=3")
        XCTAssertFalse(request.url.absoluteString.contains("&t="), "The system browser owns resume timing")
    }

    func testMovieDoesNotCarryEpisodeParametersAndEveryPresentationIsFresh() throws {
        let title = try XCTUnwrap(MediaTitle(site: ["id": 550, "title": "Movie"]))
        let first = SitePlaybackRequest(title: title, season: 9, episode: 8)
        let second = SitePlaybackRequest(title: title)
        XCTAssertEqual(first.url.absoluteString, "https://watched.cx/movie/550")
        XCTAssertNotEqual(first.id, second.id)
    }

    func testPlayNowKeepsVisibleSeasonInsteadOfJumpingToOldProgress() throws {
        let title = try XCTUnwrap(MediaTitle(site: ["id": 125988, "name": "Silo", "media_type": "tv"]))
        let first = MediaEpisode(id: 21, name: "First episode", episode_number: 1)
        let tapped = MediaEpisode(id: 24, name: "Fourth episode", episode_number: 4)
        let old = WatchProgress(title: title, position: 90, duration: 3600, season: 1, episode: 8, updatedAt: Date())

        let playNow = SitePlaybackRequest.selected(title: title, visibleSeason: 2,
                                                   visibleEpisodes: [first, tapped], tappedEpisode: nil,
                                                   savedProgress: old)
        XCTAssertEqual(playNow.url.absoluteString, "https://watched.cx/tv/125988?s=2&e=1")

        let explicit = SitePlaybackRequest.selected(title: title, visibleSeason: 2,
                                                    visibleEpisodes: [first, tapped], tappedEpisode: tapped,
                                                    savedProgress: old)
        XCTAssertEqual(explicit.url.absoluteString, "https://watched.cx/tv/125988?s=2&e=4")

        let resume = SitePlaybackRequest.selected(title: title, visibleSeason: 1,
                                                  visibleEpisodes: [first], tappedEpisode: nil,
                                                  savedProgress: old)
        XCTAssertEqual(resume.url.absoluteString, "https://watched.cx/tv/125988?s=1&e=8")
    }

    @MainActor
    func testFactoryUsesRealSystemSafariWithVisibleCloseControls() {
        let browser = SystemSafariPlayerFactory.make(url: URL(string: "https://watched.cx/movie/550")!)
        XCTAssertEqual(browser.dismissButtonStyle, .close)
        XCTAssertFalse(browser.configuration.entersReaderIfAvailable)
        XCTAssertFalse(browser.configuration.barCollapsingEnabled)
        XCTAssertNil(browser.parent, "Safari must be presented modally, not embedded as a child")
    }
}
