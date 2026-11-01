import Foundation
import XCTest
@testable import WatchedNative

private final class WatchedRequestStub: URLProtocol, @unchecked Sendable {
    struct Reply { let status: Int; let body: Data }
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
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "watched.cx" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.recorded.append(request)
        let reply = Self.replies.isEmpty ? nil : Self.replies.removeFirst()
        Self.lock.unlock()
        guard let reply, let url = request.url, let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]) else {
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

    func testFilmUsesObservedJSONServerRequest() async throws {
        try WatchedRequestStub.prepare([(200, stream)])
        let descriptor = try await client().playback(title: movie, resumeAt: 42)
        let request = try XCTUnwrap(WatchedRequestStub.requests().first)
        XCTAssertEqual(request.url?.path, "/api/vod/server")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try requestBody(request)
        XCTAssertEqual(body["tmdbId"] as? Int, 1400940)
        XCTAssertEqual(body["mediaType"] as? String, "movie")
        XCTAssertEqual(body["server"] as? String, "jycdn")
        XCTAssertNil(body["season"])
        XCTAssertEqual(descriptor.resumeAt, 42)
        XCTAssertEqual(descriptor.sources.count, 1)
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

    func testUnavailableSourceUsesObservedFallback() async throws {
        try WatchedRequestStub.prepare([(404, ["error": "unavailable"]), (200, stream)])
        let result = try await client().playback(title: movie)
        XCTAssertEqual(result.title.tmdbID, 1400940)
        XCTAssertEqual(WatchedRequestStub.requests().map { $0.url?.path }, ["/api/vod/server", "/api/vod/moviebox-fallback"])
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
}
