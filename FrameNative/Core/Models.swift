import Foundation

// MARK: - Domain Models

enum MediaKind: String, Codable, CaseIterable, Identifiable {
    case movie
    case tv
    case anime

    var id: String { rawValue }
    var title: String {
        switch self {
        case .movie: return "Movies"
        case .tv: return "TV"
        case .anime: return "Anime"
        }
    }
    var symbol: String {
        switch self {
        case .movie: return "film.stack"
        case .tv: return "tv"
        case .anime: return "sparkles.tv"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Codable {
    let tmdbID: Int
    let kind: MediaKind
    let title: String
    let overview: String
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let voteAverage: Double
    let genreIDs: [Int]

    var id: String { "\(kind.rawValue)-\(tmdbID)" }
    var year: String {
        guard let releaseDate, releaseDate.count >= 4 else { return "—" }
        return String(releaseDate.prefix(4))
    }
    var ratingText: String {
        guard voteAverage > 0 else { return "—" }
        return String(format: "%.1f", voteAverage)
    }
    var genres: [String] {
        genreIDs.compactMap { TMDBGenres.name(for: $0) }
    }
    var subtitle: String {
        let g = genres.prefix(3).joined(separator: " • ")
        return g.isEmpty ? kind.title : g
    }
    func imageURL(backdrop: Bool = false, width: Int = 780) -> URL? {
        let path = backdrop ? backdropPath : posterPath
        guard let path, !path.isEmpty else { return nil }
        let size: String
        switch width {
        case ..<300: size = "w342"
        case ..<600: size = "w500"
        case ..<1000: size = "w780"
        default: size = backdrop ? "w1280" : "original"
        }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }
}

struct MediaDetails: Codable, Hashable {
    let item: MediaItem
    let runtime: Int?
    let numberOfSeasons: Int?
    let status: String?
    let tagline: String?
    let genres: [String]

    var runtimeText: String? {
        guard let runtime, runtime > 0 else { return nil }
        let h = runtime / 60
        let m = runtime % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        return "\(m)m"
    }
}

struct Episode: Identifiable, Hashable, Codable {
    let id: Int
    let episodeNumber: Int
    let name: String
    let overview: String
    let airDate: String?
    let stillPath: String?
    let runtime: Int?

    func stillURL() -> URL? {
        guard let stillPath, !stillPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w500\(stillPath)")
    }
}

struct SeasonInfo: Identifiable, Hashable, Codable {
    let id: Int
    let seasonNumber: Int
    let name: String
    let episodeCount: Int
    let posterPath: String?
}

struct WatchProgress: Codable, Hashable {
    let item: MediaItem
    var season: Int?
    var episode: Int?
    var currentTime: Double
    var duration: Double
    var updatedAt: Date

    var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    var episodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season) E\(episode)"
    }
}

enum TMDBGenres {
    private static let map: [Int: String] = [
        28: "Action", 12: "Adventure", 16: "Animation", 35: "Comedy", 80: "Crime",
        99: "Documentary", 18: "Drama", 10751: "Family", 14: "Fantasy", 36: "History",
        27: "Horror", 10402: "Music", 9648: "Mystery", 10749: "Romance", 878: "Sci-Fi",
        10770: "TV Movie", 53: "Thriller", 10752: "War", 37: "Western",
        10759: "Action & Adventure", 10762: "Kids", 10763: "News", 10764: "Reality",
        10765: "Sci-Fi & Fantasy", 10766: "Soap", 10767: "Talk", 10768: "War & Politics"
    ]
    static func name(for id: Int) -> String? { map[id] }
}
