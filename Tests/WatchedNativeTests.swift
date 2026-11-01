import XCTest
@testable import WatchedNative

final class WatchedNativeTests: XCTestCase {
    func testHomeArchiveDecodesRealTitlesAndSeparatesRows() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "home-flight", withExtension: "html"))
        let html = try String(contentsOf: url, encoding: .utf8)
        let home = try HTMLFlightDecoder.document(fromHTML: html).home()
        XCTAssertEqual(home.featured.first?.name, "Clayface")
        XCTAssertEqual(home.featured.first?.tmdbID, 1400940)
        XCTAssertEqual(home.rails.count, 5)
        XCTAssertTrue(home.rails.contains { $0.title == "Top movies of the week" })
        XCTAssertTrue(home.rails.contains { $0.title == "On Disney+" })
        XCTAssertGreaterThan(home.allTitles.count, 50)
        XCTAssertEqual(home.allTitles.count, Set(home.allTitles.map(\.id)).count)
        XCTAssertFalse(home.allTitles.contains { $0.tmdbID <= 0 })
    }

    func testFlightReferencesAndUTF8TextRecords() throws {
        let text = "0:[\"$\",\"$L2\",null,{\"items\":\"$1\"}]\n1:[{\"id\":1,\"title\":\"أهلاً\",\"media_type\":\"movie\"}]\n2:T4,éé\n"
        let doc = FlightDocument(text)
        let snapshot = try doc.home()
        XCTAssertEqual(snapshot.featured.first?.name, "أهلاً")
        XCTAssertEqual(doc.resolve("$2") as? String, "éé")
    }

    func testCatalogActionResponseIgnoresNonJSONMetadata() throws {
        let doc = FlightDocument("0:{\"a\":\"$@1\"}\n1:{\"page\":2,\"total_pages\":3,\"results\":[{\"id\":278,\"title\":\"The Shawshank Redemption\"}]}\n2:E{\"digest\":\"test\"}\n")
        let page = try doc.catalog(kind: .movie)
        XCTAssertEqual(page.page, 2)
        XCTAssertEqual(page.totalPages, 3)
        XCTAssertEqual(page.items.first?.tmdbID, 278)
    }

    func testMalformedResponseFailsInsteadOfShowingInventedContent() {
        XCTAssertThrowsError(try HTMLFlightDecoder.document(fromHTML: "<html>Request blocked</html>"))
        XCTAssertThrowsError(try FlightDocument("0:{\"error\":\"blocked\"}\n").home())
    }

    func testSubtitlesPreserveArabicAndRespectDelayAndCueEnd() {
        let source = "WEBVTT\n\n00:00:01.000 --> 00:00:03.000 align:center\n<b>أهلاً يا حسن</b>\n\n00:00:04.000 --> 00:00:06.000\nSecond line\n"
        let cues = SubtitleParser.parse(source)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(SubtitleParser.text(at: 1.2, offset: 0, cues: cues), "أهلاً يا حسن")
        XCTAssertEqual(SubtitleParser.text(at: 1.2, offset: 1, cues: cues), "")
        XCTAssertEqual(SubtitleParser.text(at: 2.2, offset: 1, cues: cues), "أهلاً يا حسن")
        XCTAssertEqual(SubtitleParser.text(at: 3, offset: 0, cues: cues), "")
        XCTAssertEqual(SubtitleParser.text(at: 4, offset: 0, cues: cues), "Second line")
    }

    func testSRTAndInvalidCueHandling() {
        let source = "1\r\n00:01:00,500 --> 00:01:02,500\r\nHello\r\nworld\r\n\r\n2\r\n00:01:04,000 --> 00:01:03,000\r\nInvalid\r\n"
        let cues = SubtitleParser.parse(source)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.start, 60.5)
        XCTAssertEqual(cues.first?.text, "Hello\nworld")
    }
}
