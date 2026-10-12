import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var language: String {
        didSet { UserDefaults.standard.set(language, forKey: Keys.language) }
    }
    @Published var trendingMovies: [MediaItem] = []
    @Published var trendingTV: [MediaItem] = []
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

    // Catalog authentication lives on the Railway proxy. The iOS app never needs a TMDB secret.
    var isConfigured: Bool { true }
    var client: TMDBClient { TMDBClient(token: "", language: language) }

    func loadHome(force: Bool = false) async {
        if didLoad && !force { return }
        isLoading = true
        errorMessage = nil
        do {
            async let movies = client.trendingMovies()
            async let tv = client.trendingTV()
            async let animeItems = client.anime()
            let result = try await (movies, tv, animeItems)
            trendingMovies = result.0
            trendingTV = result.1
            anime = result.2
            didLoad = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func list(for kind: MediaKind) -> [MediaItem] {
        switch kind {
        case .movie: return trendingMovies
        case .tv: return trendingTV
        case .anime: return anime
        }
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
