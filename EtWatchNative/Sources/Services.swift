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
        request.setValue("EtWatchNative/1.0", forHTTPHeaderField: "User-Agent")
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
                     }, football: feed.football)
    }
}

@MainActor
final class CinemaStore: ObservableObject {
    @Published var movies: [MediaTitle] = []
    @Published var series: [MediaTitle] = []
    @Published var matches: [FootballMatch] = []
    @Published var loading = false
    @Published var errorMessage: String?
    @Published var favorites: Set<String> = []
    @Published var searching = false
    @Published var searchResults: [MediaTitle] = []

    private var feed: PlaybackFeed?
    private var searchTask: Task<Void, Never>?

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "etwatch.favorites") ?? [])
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
        do {
            feed = try await StreamFeedAPI.shared.load()
            matches = feed?.football ?? []
        } catch {
            if errorMessage == nil { errorMessage = "تعذّر قراءة مصدر البث." }
        }
    }

    func reload() async {
        movies = []
        series = []
        feed = nil
        await start()
    }

    func detail(_ item: MediaTitle) async -> MediaTitle {
        await CinemetaAPI.shared.detail(item)
    }

    func entry(for key: String) -> PlaybackEntry? { feed?.entries[key] }

    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        UserDefaults.standard.set(Array(favorites), forKey: "etwatch.favorites")
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
