import Foundation
import SwiftUI

enum AppAPIError: LocalizedError {
    case invalidResponse
    case invalidFeed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "تعذّر تحميل المحتوى الآن."
        case .invalidFeed: "مصدر الفيديو غير متوافق."
        }
    }
}

actor CinemetaAPI {
    static let shared = CinemetaAPI()
    private let base = "https://v3-cinemeta.strem.io"

    private func fetch<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 18)
        request.setValue("GemflixNative/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode else { throw AppAPIError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func list(_ kind: MediaKind, skip: Int = 0) async throws -> [MediaTitle] {
        let suffix = skip > 0 ? "/skip=\(skip)" : ""
        let path = "\(base)/catalog/\(kind.catalogPath)/top\(suffix).json"
        guard let url = URL(string: path) else { throw AppAPIError.invalidResponse }
        let data: CinemetaCatalogResponse = try await fetch(url)
        return data.metas.map { $0.asTitle(kind) }
    }

    func search(_ query: String, kind: MediaKind) async throws -> [MediaTitle] {
        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(base)/catalog/\(kind.catalogPath)/top/search=\(escaped).json") else {
            return []
        }
        let data: CinemetaCatalogResponse = try await fetch(url)
        return data.metas.map { $0.asTitle(kind) }
    }

    func detail(_ title: MediaTitle) async -> MediaTitle {
        guard let url = URL(string: "\(base)/meta/\(title.kind.catalogPath)/\(title.id).json"),
              let value: CinemetaDetailsResponse = try? await fetch(url) else { return title }
        return value.meta.asTitle(title.kind)
    }
}

// Gemflix exposes a server-rendered home-seed document. It is catalogue
// metadata, never a source of movie URLs or a promise that a title is playable.
private struct GemflixHomepage: Decodable {
    let trending: [GemflixHomepageTitle]
    let topToday: [GemflixHomepageTitle]
}

private struct GemflixHomepageTitle: Decodable {
    let id: Int
    let title: String
    let overview: String?
    let poster_path: String?
    let backdrop_path: String?
    let release_date: String?
    let vote_average: Double?
    let genre_ids: [Int]?
    let media_type: String?

    func asTitle() -> MediaTitle {
        let names: [Int: String] = [28: "Action", 12: "Adventure", 16: "Animation",
                                    35: "Comedy", 80: "Crime", 18: "Drama",
                                    27: "Horror", 878: "Science Fiction", 9648: "Mystery",
                                    53: "Thriller", 10749: "Romance", 14: "Fantasy"]
        return MediaTitle(id: "tmdb:\(id)", title: title, kind: .movie,
                          synopsis: overview ?? "", year: String((release_date ?? "").prefix(4)),
                          rating: (vote_average ?? 0) > 0 ? String(format: "%.1f", vote_average ?? 0) : "",
                          posterURL: poster_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w500\($0)") },
                          backdropURL: backdrop_path.flatMap { URL(string: "https://image.tmdb.org/t/p/w1280\($0)") },
                          episodes: [], genres: (genre_ids ?? []).compactMap { names[$0] })
    }
}

actor GemflixHomepageAPI {
    static let shared = GemflixHomepageAPI()

    func featured() async throws -> [MediaTitle] {
        do { return try await liveFeatured() }
        catch {
            guard let url = Bundle.main.url(forResource: "GemflixSeed", withExtension: "json") else { throw error }
            let seed = try JSONDecoder().decode(GemflixHomepage.self, from: Data(contentsOf: url))
            return titles(from: seed)
        }
    }

    private func liveFeatured() async throws -> [MediaTitle] {
        guard let url = URL(string: "https://gemflix.site/") else { throw AppAPIError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode,
              data.count < 2_500_000, let html = String(data: data, encoding: .utf8) else {
            throw AppAPIError.invalidResponse
        }
        let expression = try NSRegularExpression(pattern: "<script[^>]*id=\\\"home-seed\\\"[^>]*>(.*?)</script>",
                                                 options: [.dotMatchesLineSeparators])
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = expression.firstMatch(in: html, range: range),
              let payloadRange = Range(match.range(at: 1), in: html),
              let payload = String(html[payloadRange]).data(using: .utf8) else {
            throw AppAPIError.invalidResponse
        }
        let seed = try JSONDecoder().decode(GemflixHomepage.self, from: payload)
        return titles(from: seed)
    }

    private func titles(from seed: GemflixHomepage) -> [MediaTitle] {
        var unique = Set<Int>()
        return (seed.topToday + seed.trending)
            .filter { ($0.media_type ?? "movie") == "movie" && unique.insert($0.id).inserted }
            .map { $0.asTitle() }
    }
}

actor StreamFeedAPI {
    static let shared = StreamFeedAPI()
    private var cached: PlaybackFeed?

    func load(refresh: Bool = false) async throws -> PlaybackFeed {
        if let cached, !refresh { return cached }
        let manifestString = (Bundle.main.object(forInfoDictionaryKey: "NATIVE_FEED_URL") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: manifestString), url.scheme == "https" {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode,
                  data.count < 2_000_000 else { throw AppAPIError.invalidFeed }
            let feed = try JSONDecoder().decode(PlaybackFeed.self, from: data)
            cached = sanitize(feed)
            return cached!
        }
        guard let url = Bundle.main.url(forResource: "SampleFeed", withExtension: "json") else {
            throw AppAPIError.invalidFeed
        }
        let feed = try JSONDecoder().decode(PlaybackFeed.self, from: Data(contentsOf: url))
        cached = sanitize(feed)
        return cached!
    }

    private func sanitize(_ feed: PlaybackFeed) -> PlaybackFeed {
        PlaybackFeed(version: feed.version,
                     entries: feed.entries.mapValues { entry in
                         PlaybackEntry(sources: entry.sources.filter(\.isSupported),
                                       subtitles: entry.subtitles.filter { $0.url.scheme == "https" })
                     })
    }
}

@MainActor
final class CinemaStore: ObservableObject {
    @Published var movies: [MediaTitle] = []
    @Published var series: [MediaTitle] = []
    @Published var gemflixFeatured: [MediaTitle] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var favorites: Set<String> = []
    @Published var searching = false
    @Published var searchResults: [MediaTitle] = []

    private var feed: PlaybackFeed?
    private var searchTask: Task<Void, Never>?

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "gemflix.favorites") ?? [])
    }

    func start() async {
        guard movies.isEmpty, series.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            async let m = CinemetaAPI.shared.list(.movie)
            async let s = CinemetaAPI.shared.list(.series)
            movies = try await m
            series = try await s
        } catch {
            errorMessage = "تعذّر تحديث المكتبة. اسحب الشاشة لإعادة المحاولة."
        }
        gemflixFeatured = (try? await GemflixHomepageAPI.shared.featured()) ?? []
        do {
            feed = try await StreamFeedAPI.shared.load()
        } catch {
            if errorMessage == nil { errorMessage = "تعذّر قراءة مصدر البث." }
        }
    }

    func reload() async {
        movies = []
        series = []
        gemflixFeatured = []
        feed = nil
        await start()
    }

    func detail(_ item: MediaTitle) async -> MediaTitle {
        await CinemetaAPI.shared.detail(item)
    }

    func entry(for key: String) -> PlaybackEntry? { feed?.entries[key] }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "gemflix.favorites")
    }

    func search(_ query: String, kind: MediaKind) {
        searchTask?.cancel()
        searchResults = []
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            let results = (try? await CinemetaAPI.shared.search(query, kind: kind)) ?? []
            guard !Task.isCancelled else { return }
            searchResults = results
            searching = false
        }
    }
}
