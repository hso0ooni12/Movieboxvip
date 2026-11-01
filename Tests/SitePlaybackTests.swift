import XCTest
@testable import WatchedNative

final class SitePlaybackTests: XCTestCase {
    func testEpisodeUsesDirectPublicWatchURLAndSelectedEpisode() throws {
        let title = try XCTUnwrap(MediaTitle(site: ["id": 125988, "name": "Silo", "media_type": "tv"]))
        let request = SitePlaybackRequest(title: title, season: 2, episode: 3, resumeAt: 34.5)
        XCTAssertEqual(request.url.absoluteString, "https://watched.cx/tv/125988?s=2&e=3&t=34")
        let route = try XCTUnwrap(SitePlayerRoute(url: request.url))
        XCTAssertEqual(route.season, 2); XCTAssertEqual(route.episode, 3)
        XCTAssertEqual(SitePlayerNavigation.action(for: request.url), .play)
    }

    func testMovieDoesNotCarryEpisodeParametersAndEveryPresentationIsFresh() throws {
        let title = try XCTUnwrap(MediaTitle(site: ["id": 550, "title": "Movie"]))
        let first = SitePlaybackRequest(title: title, season: 9, episode: 8, resumeAt: .nan)
        let second = SitePlaybackRequest(title: title)
        XCTAssertEqual(first.url.absoluteString, "https://watched.cx/movie/550")
        XCTAssertNotEqual(first.id, second.id)
    }

    func testWebsiteBrowseBackAndHomeReturnToAppWhileNextEpisodeStaysInPlayer() throws {
        for path in ["/browse/tv/125988?s=1", "/browse/movie/550", "/home", "/shows"] {
            XCTAssertEqual(SitePlayerNavigation.action(for: try XCTUnwrap(URL(string: "https://watched.cx" + path))), .returnToApp)
        }
        XCTAssertEqual(SitePlayerNavigation.action(for: try XCTUnwrap(URL(string: "https://watched.cx/tv/125988?s=1&e=2"))), .play)
    }

    func testExternalWindowsAndNonSecurePagesCannotReplacePlayer() throws {
        for raw in ["https://example.com/home", "https://watched.cx.example.com/tv/1", "http://watched.cx/tv/1", "https://user@watched.cx/tv/1", "https://watched.cx:444/tv/1", "javascript:alert(1)"] {
            XCTAssertEqual(SitePlayerNavigation.action(for: try XCTUnwrap(URL(string: raw))), .block)
        }
    }
}
