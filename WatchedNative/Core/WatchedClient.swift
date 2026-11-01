import Foundation

actor WatchedClient {
    static let shared = WatchedClient()
    private let origin = URL(string: "https://watched.cx")!
    private let session: URLSession
    private var actionIDs: [String: String] = [
        "searchMoviesAction": "60e250dff32c6009bd9a34592aede73d123d3ba847",
        "discoverMoviesAction": "60a9c45de950f1706fd94e182fd7a8faf14ff599ed",
        "searchShowsAction": "6023983ca5a157789448cb0b7204aeabf4332b5629",
        "discoverShowsAction": "606d0cfaa6d48f66d87a21584dd01e6cc602170d95",
        "getProviderRowAction": "60b1ef9a1f0b2b5408dff2808552fc27fbc164b793"
    ]

    init(session suppliedSession: URLSession? = nil) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = URLCache(memoryCapacity: 16_000_000, diskCapacity: 64_000_000)
        session = suppliedSession ?? URLSession(configuration: configuration)
    }

    private func get(_ path: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: origin), url.host == origin.host else { throw WatchedError.malformed }
        var request = URLRequest(url: url)
        request.setValue("text/html,application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw WatchedError.malformed }
        if response.statusCode == 401 || response.statusCode == 403 { throw WatchedError.blocked }
        if response.statusCode == 429 { throw WatchedError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw WatchedError.server(response.statusCode) }
        return (data, response)
    }

    func home() async throws -> HomeSnapshot {
        let (data, _) = try await get("/home")
        let html = String(decoding: data, as: UTF8.self)
        await refreshActionIDs(in: html)
        return try HTMLFlightDecoder.document(fromHTML: html).home()
    }

    func catalog(kind: MediaKind, filters: CatalogFilters, page: Int) async throws -> CatalogPage {
        if page == 1 {
            var components = URLComponents()
            components.path = "/\(kind.route)"
            var query: [URLQueryItem] = []
            if !filters.query.isEmpty { query.append(URLQueryItem(name: "q", value: filters.query)) }
            if let id = filters.genreID { query.append(URLQueryItem(name: "genre", value: String(id))) }
            if let id = filters.providerID, kind == .movie { query.append(URLQueryItem(name: "provider", value: String(id))) }
            query.append(URLQueryItem(name: "sort", value: filters.sort))
            components.queryItems = query
            let (data, _) = try await get(components.string ?? "/\(kind.route)")
            let html = String(decoding: data, as: UTF8.self)
            await refreshActionIDs(in: html)
            return try HTMLFlightDecoder.document(fromHTML: html).catalog(kind: kind)
        }
        let suffix = kind == .movie ? "MoviesAction" : "ShowsAction"
        let name = (filters.query.isEmpty ? "discover" : "search") + suffix
        let firstArgument: Any = filters.query.isEmpty ? filters.actionValue as Any : filters.query as Any
        let args: [Any] = [firstArgument, page]
        return try await action(name, route: "/\(kind.route)", arguments: args).catalog(kind: kind)
    }

    func provider(_ option: ProviderOption, kind: MediaKind) async throws -> [MediaTitle] {
        let document = try await action("getProviderRowAction", route: "/home", arguments: [kind.rawValue, option.id])
        for (_, value) in document.records {
            if let array = value as? [[String: Any]] {
                return array.compactMap { MediaTitle(site: $0, kind: kind) }
            }
        }
        throw WatchedError.malformed
    }

    func detail(_ title: MediaTitle) async throws -> TitleDetails {
        let (data, _) = try await get(title.detailPath)
        return try HTMLFlightDecoder.document(fromHTML: String(decoding: data, as: UTF8.self)).detail(fallback: title)
    }

    func episodes(tmdbID: Int, season: Int) async throws -> [MediaEpisode] {
        let (data, _) = try await get("/api/episodes?tmdbId=\(tmdbID)&season=\(season)")
        struct Response: Decodable { let episodes: [MediaEpisode] }
        return try JSONDecoder().decode(Response.self, from: data).episodes
    }

    /// Uses the same JSON request and response fields observed in the supplied film watch-page script.
    /// A clearance/authentication response is terminal; it is never worked around through another route.
    func playback(title: MediaTitle, season: Int? = nil, episode: Int? = nil, resumeAt: Double = 0) async throws -> PlaybackDescriptor {
        let target = target(title: title, season: season, episode: episode)
        do {
            let response = try await post("/api/vod/server", body: target.merging(["server": "jycdn"]) { _, new in new })
            return try VODResponseDecoder.descriptor(response, title: title, origin: origin, season: season, episode: episode, resumeAt: resumeAt)
        } catch let error as WatchedError {
            switch error {
            case .blocked, .rateLimited: throw error
            default: return try await fallbackPlayback(title: title, season: season, episode: episode, resumeAt: resumeAt)
            }
        }
    }

    func fallbackPlayback(title: MediaTitle, season: Int?, episode: Int?, resumeAt: Double) async throws -> PlaybackDescriptor {
        let response = try await post("/api/vod/moviebox-fallback", body: target(title: title, season: season, episode: episode))
        var descriptor = try VODResponseDecoder.descriptor(response, title: title, origin: origin, season: season, episode: episode, resumeAt: resumeAt)
        descriptor.usedFallback = true
        return descriptor
    }

    func subtitles(title: MediaTitle, season: Int?, episode: Int?) async throws -> [ExternalSubtitle] {
        let response = try await post("/api/vod/subtitles", body: target(title: title, season: season, episode: episode))
        return VODResponseDecoder.subtitles(response, origin: origin)
    }

    func releasePlayback(sessionID: String) async {
        _ = try? await post("/api/jycdn/session", body: ["sessionId": sessionID])
    }

    private func target(title: MediaTitle, season: Int?, episode: Int?) -> [String: Any] {
        var target: [String: Any] = ["tmdbId": title.tmdbID, "mediaType": title.kind.rawValue]
        if let season { target["season"] = season }
        if let episode { target["episode"] = episode }
        return target
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: path, relativeTo: origin) else { throw WatchedError.malformed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await perform(request)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw WatchedError.malformed }
        return object
    }

    private func action(_ name: String, route: String, arguments: [Any]) async throws -> FlightDocument {
        guard let identifier = actionIDs[name], let url = URL(string: route, relativeTo: origin) else { throw WatchedError.malformed }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: arguments)
        request.setValue(identifier, forHTTPHeaderField: "Next-Action")
        request.setValue("text/x-component", forHTTPHeaderField: "Accept")
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
        let (data, _) = try await perform(request)
        return FlightDocument(String(decoding: data, as: UTF8.self))
    }

    /// Refresh build-dependent action identifiers from the same public scripts referenced by the page.
    private func refreshActionIDs(in html: String) async {
        guard let regex = try? NSRegularExpression(pattern: #"<script[^>]+src="([^"]+)""#) else { return }
        let source = html as NSString
        let paths = regex.matches(in: html, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) }
            .filter { $0.contains("/app/") && $0.contains("page-") }
        for path in paths.prefix(2) {
            guard !Task.isCancelled, let (data, _) = try? await get(path) else { continue }
            let text = String(decoding: data, as: UTF8.self) as NSString
            guard let pattern = try? NSRegularExpression(pattern: #"createServerReference\)\("([a-f0-9]{40,64})".{0,160}?"([A-Za-z]+Action)""#) else { continue }
            for match in pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
                actionIDs[text.substring(with: match.range(at: 2))] = text.substring(with: match.range(at: 1))
            }
        }
    }
}
