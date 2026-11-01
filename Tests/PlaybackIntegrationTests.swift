import Foundation
import XCTest
@testable import WatchedNative

private final class WatchedRequestStub: URLProtocol, @unchecked Sendable {
    struct Reply { let status: Int; let body: Data; var headers: [String: String] = ["Content-Type": "application/json"] }
    private static let lock = NSLock()
    private static var replies: [Reply] = []
    private static var recorded: [URLRequest] = []
    static func prepare(_ values: [(Int, [String: Any])]) throws {
        let encoded = try values.map { Reply(status: $0.0, body: try JSONSerialization.data(withJSONObject: $0.1)) }
        lock.lock(); defer { lock.unlock() }
        replies = encoded; recorded = []
    }
    static func requests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return recorded
    }
    static func setReplies(_ values: [Reply]) {
        lock.lock(); defer { lock.unlock() }; replies = values; recorded = []
    }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "watched.cx" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let reply = Self.replies.isEmpty ? nil : Self.replies.removeFirst()
        Self.lock.unlock()
        guard let reply, let url = request.url, let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class PlaybackIntegrationTests: XCTestCase {
    private func client() -> WatchedClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WatchedRequestStub.self]
        return WatchedClient(session: URLSession(configuration: configuration))
    }
    private var movie: MediaTitle { MediaTitle(site: ["id": 1400940, "title": "Clayface", "media_type": "movie"])! }
    private var stream: [String: Any] { ["stream": ["kind": "hls", "sources": [["url": "https://media.example.invalid/master.m3u8", "quality": "Auto", "kind": "hls"]]]] }

    func testFilmReadsInitialWatchStreamWithoutCallingProtectedSwitchAPI() async throws {
        WatchedRequestStub.setReplies([try htmlReply(kind: .movie, id: 1400940)])
        let descriptor = try await client().playback(title: movie, resumeAt: 42)
        let request = try XCTUnwrap(WatchedRequestStub.requests().first)
        XCTAssertEqual(request.url?.path, "/movie/1400940")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(WatchedRequestStub.requests().count, 1)
        XCTAssertEqual(descriptor.resumeAt, 42)
        XCTAssertEqual(descriptor.sources.count, 1)
        XCTAssertEqual(descriptor.sources.first?.kind, "mp4")
        XCTAssertEqual(descriptor.sources.first?.label, "1080p")
        XCTAssertEqual(descriptor.sources.first?.url.absoluteString, "https://watched.cx/api/jycdn/media/fixture-stream")
    }

    func test403IsTerminalWithoutAlternateRouteOrCookieCopy() async throws {
        try WatchedRequestStub.prepare([(403, ["error": "verification required"]), (200, stream)])
        do {
            _ = try await client().playback(title: movie)
            XCTFail("A denied source must not fall through to another route")
        } catch WatchedError.blocked { }
        XCTAssertEqual(WatchedRequestStub.requests().count, 1)
        XCTAssertNil(WatchedRequestStub.requests().first?.value(forHTTPHeaderField: "Cookie"))
    }

    func testClearedUnavailableInitialStreamCanUseObservedFallback() async throws {
        WatchedRequestStub.setReplies([try htmlReply(kind: .movie, id: 1400940, placeholder: true),
                                      .init(status: 404, body: try JSONSerialization.data(withJSONObject: ["error": "unavailable"])),
                                      .init(status: 200, body: try JSONSerialization.data(withJSONObject: stream))])
        let result = try await client().playback(title: movie)
        XCTAssertEqual(result.title.tmdbID, 1400940)
        XCTAssertEqual(WatchedRequestStub.requests().map { $0.url?.path }, ["/movie/1400940", "/api/vod/server", "/api/vod/moviebox-fallback"])
    }

    func testSiloReadsExactEpisodeProgressAndRelativeSubtitles() async throws {
        let silo = try XCTUnwrap(MediaTitle(site: ["id": 125988, "name": "Silo", "media_type": "tv"]))
        WatchedRequestStub.setReplies([try htmlReply(kind: .tv, id: 125988, season: 1, episode: 1)])
        let descriptor = try await client().playback(title: silo, season: 1, episode: 1, resumeAt: 34)
        let request = try XCTUnwrap(WatchedRequestStub.requests().first)
        XCTAssertEqual(request.url?.path, "/tv/125988")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: true)?.queryItems
        XCTAssertEqual(query?.first(where: { $0.name == "s" })?.value, "1")
        XCTAssertEqual(query?.first(where: { $0.name == "e" })?.value, "1")
        XCTAssertEqual(descriptor.resumeAt, 34)
        XCTAssertEqual(descriptor.season, 1)
        XCTAssertEqual(descriptor.episode, 1)
        XCTAssertEqual(descriptor.subtitles.first?.url.absoluteString, "https://watched.cx/api/jycdn/media/fixture-english")
    }

    func testServerClearanceFalseRejectsEvenAnEmbeddedURLWithoutProbingAPI() async throws {
        WatchedRequestStub.setReplies([try htmlReply(kind: .movie, id: 1400940, cleared: false)])
        do { _ = try await client().playback(title: movie); XCTFail("Server verification must be honored") }
        catch WatchedError.verificationRequired { }
        XCTAssertEqual(WatchedRequestStub.requests().count, 1)
    }

    func testExplicitClearanceHeaderRequiresUserVerification() async throws {
        WatchedRequestStub.setReplies([.init(status: 403, body: Data(), headers: ["x-clearance": "needed"])])
        do { _ = try await client().playback(title: movie); XCTFail("Expected user verification") }
        catch WatchedError.verificationRequired { }
        XCTAssertEqual(WatchedRequestStub.requests().count, 1)
    }

    func testWrongEpisodeDoesNotReuseAnotherEpisodesStream() async throws {
        let silo = try XCTUnwrap(MediaTitle(site: ["id": 125988, "name": "Silo", "media_type": "tv"]))
        WatchedRequestStub.setReplies([try htmlReply(kind: .tv, id: 125988, season: 1, episode: 2)])
        do { _ = try await client().playback(title: silo, season: 1, episode: 1); XCTFail("Expected exact episode match") }
        catch WatchedError.malformed { }
        XCTAssertEqual(WatchedRequestStub.requests().count, 1)
    }

    func testEveryPlayReadsAFreshLeaseInsteadOfReusingArchivedURL() async throws {
        WatchedRequestStub.setReplies([try htmlReply(kind: .movie, id: 1400940, mediaPath: "/api/jycdn/media/lease-a"),
                                      try htmlReply(kind: .movie, id: 1400940, mediaPath: "/api/jycdn/media/lease-b")])
        let service = client()
        let first = try await service.playback(title: movie)
        let second = try await service.playback(title: movie)
        XCTAssertNotEqual(first.sources.first?.url, second.sources.first?.url)
        XCTAssertEqual(WatchedRequestStub.requests().count, 2)
        XCTAssertTrue(WatchedRequestStub.requests().allSatisfy { $0.httpMethod == "GET" && $0.cachePolicy == .reloadIgnoringLocalCacheData })
    }

    func testVerificationCookiesAreRestrictedToTheFirstParty() {
        XCTAssertTrue(SourceCookiePolicy.isFirstParty(domain: "watched.cx"))
        XCTAssertTrue(SourceCookiePolicy.isFirstParty(domain: ".watched.cx"))
        XCTAssertTrue(SourceCookiePolicy.isFirstParty(domain: "eu.watched.cx"))
        XCTAssertFalse(SourceCookiePolicy.isFirstParty(domain: "evilwatched.cx"))
        XCTAssertFalse(SourceCookiePolicy.isFirstParty(domain: "watched.cx.evil.invalid"))
        XCTAssertFalse(SourceCookiePolicy.isFirstParty(domain: "unrelated.invalid"))
    }

    func testOnlyUserCompletedFirstPartySessionCanEnterNativeCookieStore() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WatchedRequestStub.self]
        let storage = try XCTUnwrap(configuration.httpCookieStorage)
        let source = try XCTUnwrap(HTTPCookie(properties: [.domain: "watched.cx", .path: "/", .name: "fixture-session", .value: "test-only", .secure: "TRUE"]))
        let unrelated = try XCTUnwrap(HTTPCookie(properties: [.domain: "unrelated.invalid", .path: "/", .name: "unrelated-session", .value: "test-only"]))
        let service = WatchedClient(session: URLSession(configuration: configuration))
        await service.acceptVerifiedSourceCookies([source, unrelated])
        XCTAssertTrue(storage.cookies?.contains(where: { $0.name == "fixture-session" }) ?? false)
        XCTAssertFalse(storage.cookies?.contains(where: { $0.name == "unrelated-session" }) ?? true)
    }

    func testSeriesSubtitlesPreserveEpisodeAndResolveSameSiteURL() async throws {
        let title = try XCTUnwrap(MediaTitle(site: ["id": 1396, "name": "Breaking Bad", "media_type": "tv"]))
        try WatchedRequestStub.prepare([(200, ["subtitles": [["url": "/api/subs/test", "label": "العربية", "language": "ar"]]])])
        let tracks = try await client().subtitles(title: title, season: 2, episode: 3)
        let request = try XCTUnwrap(WatchedRequestStub.requests().first)
        let body = try requestBody(request)
        XCTAssertEqual(body["season"] as? Int, 2)
        XCTAssertEqual(body["episode"] as? Int, 3)
        XCTAssertEqual(tracks.first?.language, "ar")
        XCTAssertEqual(tracks.first?.url.absoluteString, "https://watched.cx/api/subs/test")
    }

    func testPlaybackDecoderRejectsBlobAndUnsafeURLs() throws {
        let value: [String: Any] = ["stream": ["sources": [["url": "blob:https://watched.cx/local", "quality": "Auto"], ["url": "http://media.example.invalid/file.mp4"]]]]
        XCTAssertThrowsError(try VODResponseDecoder.descriptor(value, title: movie, origin: URL(string: "https://watched.cx")!, season: nil, episode: nil, resumeAt: 0))
    }

    func testHLSQualityChoicesComeFromAdvertisedMasterRenditions() {
        let master = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080,CODECS=\"avc1\"\nfull.m3u8\n#EXT-X-STREAM-INF:RESOLUTION=1280x720,BANDWIDTH=3000000\nhd.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2900000,RESOLUTION=1280x720\nhd-alternative.m3u8\n"
        XCTAssertEqual(HLSMasterParser.renditions(master), [HLSRendition(width: 1920, height: 1080, bandwidth: 6000000), HLSRendition(width: 1280, height: 720, bandwidth: 3000000)])
        XCTAssertTrue(HLSMasterParser.renditions("#EXTM3U\n#EXTINF:6,\nsegment.ts").isEmpty)
    }

    private func requestBody(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody { return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]) }
        let stream = try XCTUnwrap(request.httpBodyStream)
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(buffer, count: count)
        }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Reproduces the supplied Silo watch-page shape, with all signed URLs/session values replaced.
    /// Split script chunks also reproduce the streamed JSON boundary in the supplied page source.
    private func htmlReply(kind: MediaKind, id: Int, season: Int? = nil, episode: Int? = nil, cleared: Bool = true,
                           placeholder: Bool = false, mediaPath: String = "/api/jycdn/media/fixture-stream") throws -> WatchedRequestStub.Reply {
        var progress: [String: Any] = ["tmdbId": id, "mediaType": kind.rawValue]
        if let season { progress["season"] = season }
        if let episode { progress["episode"] = episode }
        let stream: [String: Any] = ["sources": [["url": mediaPath, "quality": "1080p", "name": "jyCDN", "kind": "mp4", "origin": "jycdn", "server": "jycdn"]],
                                    "kind": "mp4", "placeholder": placeholder, "sessionId": "fixture-session",
                                    "subtitles": [["id": "fixture-sub", "url": "/api/jycdn/media/fixture-english", "label": "English", "language": "en"]]]
        let props: [String: Any] = ["title": kind == .tv ? "Silo" : "Clayface", "progress": progress, "cleared": cleared, "stream": stream]
        let node: [Any] = ["$", "$L15", NSNull(), props]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: node, options: [.sortedKeys]), as: UTF8.self)
        let payload = "15:I[71500,[],\"VodPlayer\"]\n14:\(json)\n"
        let boundary = payload.index(payload.startIndex, offsetBy: payload.count / 2)
        let fragments = [String(payload[..<boundary]), String(payload[boundary...])]
        let scripts = try fragments.map { fragment -> String in
            let array = String(decoding: try JSONSerialization.data(withJSONObject: [fragment]), as: UTF8.self)
            return "<script>self.__next_f.push([1,\(array.dropFirst().dropLast())])</script>"
        }.joined()
        return .init(status: 200, body: Data("<html>\(scripts)</html>".utf8), headers: ["Content-Type": "text/html"])
    }
}
