import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Keys.language) }
    }
    @Published var trendingMovies: [MediaItem] = []
    @Published var trendingTV: [MediaItem] = []
    @Published var popularMovies: [MediaItem] = []
    @Published var popularTV: [MediaItem] = []
    @Published var anime: [MediaItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var didLoad = false

    enum Keys {
        static let language = "FrameNative.language"
    }

    init() {
        language = UserDefaults.standard.string(forKey: Keys.language) ?? "en-US"
    }

    var isConfigured: Bool { true }
    var client: TMDBClient { TMDBClient(token: "", language: language) }

    func loadHome(force: Bool = false) async {
        if isLoading || (didLoad && !force) { return }
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let movies = client.trendingMovies()
            async let tv = client.trendingTV()
            async let popularMovieItems = client.popularMovies()
            async let popularTVItems = client.popularTV()
            async let animeItems = client.anime()
            let result = try await (movies, tv, popularMovieItems, popularTVItems, animeItems)
            trendingMovies = result.0
            trendingTV = result.1
            popularMovies = result.2
            popularTV = result.3
            anime = result.4
            try Task.checkCancellation()
            didLoad = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func list(for kind: MediaKind) -> [MediaItem] {
        switch kind {
        case .movie: return deduplicated(trendingMovies + popularMovies)
        case .tv: return deduplicated(trendingTV + popularTV)
        case .anime: return anime
        }
    }

    var spotlight: [MediaItem] {
        var mixed: [MediaItem] = []
        let moviePicks = Array(trendingMovies.prefix(4))
        let tvPicks = Array(trendingTV.prefix(4))
        for index in 0..<max(moviePicks.count, tvPicks.count) {
            if moviePicks.indices.contains(index) { mixed.append(moviePicks[index]) }
            if tvPicks.indices.contains(index) { mixed.append(tvPicks[index]) }
        }
        return Array(deduplicated(mixed).prefix(6))
    }

    var topTen: [MediaItem] {
        let combined = trendingMovies + trendingTV
        return Array(deduplicated(combined).sorted { lhs, rhs in
            if lhs.voteAverage == rhs.voteAverage { return lhs.title < rhs.title }
            return lhs.voteAverage > rhs.voteAverage
        }.prefix(10))
    }

    func related(to item: MediaItem, limit: Int = 12) -> [MediaItem] {
        let source = item.kind == .movie ? list(for: .movie) : (item.kind == .anime ? anime : list(for: .tv))
        let wanted = Set(item.genreIDs)
        let ranked = source
            .filter { $0.id != item.id }
            .map { candidate -> (MediaItem, Int) in
                let overlap = Set(candidate.genreIDs).intersection(wanted).count
                return (candidate, overlap)
            }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.voteAverage > rhs.0.voteAverage }
                return lhs.1 > rhs.1
            }
            .map(\.0)
        return Array(ranked.prefix(limit))
    }

    func search(_ query: String) async throws -> [MediaItem] {
        try await client.search(query)
    }

    func details(for item: MediaItem) async throws -> MediaDetails {
        try await client.details(for: item)
    }

    func seasons(for item: MediaItem) async throws -> [SeasonInfo] {
        try await client.seasons(for: item)
    }

    func episodes(tmdbID: Int, season: Int) async throws -> [Episode] {
        try await client.episodes(tmdbID: tmdbID, season: season)
    }

    private func deduplicated(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favorites: [String: MediaItem] = [:]
    @Published private(set) var progress: [String: WatchProgress] = [:]

    private let favoritesKey = "FrameNative.favoriteItems.v2"
    private let progressKey = "FrameNative.watchProgress.v2"
    private var lastSavedProgress: [String: Double] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let decoded = try? JSONDecoder().decode([String: MediaItem].self, from: data) {
            favorites = decoded
        }
        if let data = UserDefaults.standard.data(forKey: progressKey),
           let decoded = try? JSONDecoder().decode([String: WatchProgress].self, from: data) {
            progress = decoded
        }
    }

    func isFavorite(_ item: MediaItem) -> Bool { favorites[item.id] != nil }

    func toggleFavorite(_ item: MediaItem) {
        if favorites[item.id] != nil { favorites[item.id] = nil }
        else { favorites[item.id] = item }
        saveFavorites()
    }

    var favoriteItems: [MediaItem] {
        favorites.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var continueWatching: [WatchProgress] {
        progress.values
            .filter { $0.currentTime > 5 && ($0.duration <= 0 || $0.fraction < 0.96) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func progress(for item: MediaItem) -> WatchProgress? { progress[item.id] }

    func updateProgress(item: MediaItem, season: Int?, episode: Int?, current: Double, duration: Double) {
        guard current.isFinite, duration.isFinite, current >= 0 else { return }
        let previous = progress[item.id]
        let sameEpisode = previous?.season == season && previous?.episode == episode
        let last = lastSavedProgress[item.id] ?? -100
        let shouldSave = !sameEpisode || abs(current - last) >= 4 || (duration > 0 && current / duration >= 0.95)
        guard shouldSave else { return }

        progress[item.id] = WatchProgress(
            item: item,
            season: season,
            episode: episode,
            currentTime: current,
            duration: duration,
            updatedAt: Date()
        )
        lastSavedProgress[item.id] = current
        saveProgress()
    }

    func removeProgress(for item: MediaItem) {
        progress[item.id] = nil
        lastSavedProgress[item.id] = nil
        saveProgress()
    }

    func clearWatchHistory() {
        progress.removeAll()
        lastSavedProgress.removeAll()
        saveProgress()
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    private func saveProgress() {
        if let data = try? JSONEncoder().encode(progress) {
            UserDefaults.standard.set(data, forKey: progressKey)
        }
    }
}
