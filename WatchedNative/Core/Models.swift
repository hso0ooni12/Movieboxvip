import Foundation

enum MediaKind: String, Codable, CaseIterable, Sendable {
    case movie, tv
    var title: String { self == .movie ? "الأفلام" : "المسلسلات" }
    var route: String { self == .movie ? "movies" : "shows" }
}

struct MediaTitle: Identifiable, Hashable, Codable, Sendable {
    let tmdbID: Int
    let kind: MediaKind
    let name: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: String?
    var rating: Double
    var genres: [String]
    var runtime: Int?
    var id: String { "\(kind.rawValue):\(tmdbID)" }
    var year: String { String((releaseDate ?? "").prefix(4)) }
    var posterURL: URL? { imageURL(posterPath, size: "w500") }
    var backdropURL: URL? { imageURL(backdropPath ?? posterPath, size: "w1280") }
    var detailPath: String { "/browse/\(kind.rawValue)/\(tmdbID)" }

    func imageURL(_ path: String?, size: String) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("https://") { return URL(string: path) }
        if path.hasPrefix("/manual-thumbnails/") { return URL(string: "https://watched.cx\(path)") }
        guard path.hasPrefix("/") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    init?(site value: [String: Any], kind fallback: MediaKind? = nil) {
        guard let id = (value["id"] as? NSNumber)?.intValue, id > 0,
              let name = (value["title"] as? String) ?? (value["name"] as? String), !name.isEmpty else { return nil }
        tmdbID = id
        kind = (value["media_type"] as? String).flatMap(MediaKind.init(rawValue:))
            ?? (value["type"] as? String).flatMap(MediaKind.init(rawValue:))
            ?? fallback ?? (value["title"] != nil ? .movie : .tv)
        self.name = name
        overview = value["overview"] as? String ?? ""
        posterPath = value["poster_path"] as? String
        backdropPath = value["backdrop_path"] as? String
        releaseDate = (value["release_date"] as? String) ?? (value["first_air_date"] as? String)
        rating = (value["vote_average"] as? NSNumber)?.doubleValue ?? 0
        genres = (value["genres"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
        runtime = (value["runtime"] as? NSNumber)?.intValue
    }
}

struct MediaRail: Identifiable, Codable, Sendable {
    var id: String
    var title: String
    var items: [MediaTitle]
}

struct ProviderOption: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let label: String
}

struct HomeSnapshot: Codable, Sendable {
    var featured: [MediaTitle]
    var rails: [MediaRail]
    var providers: [ProviderOption]
    var capturedAt: String?
    var allTitles: [MediaTitle] {
        var seen = Set<String>()
        return (featured + rails.flatMap(\.items)).filter { seen.insert($0.id).inserted }
    }
}

struct CatalogFilters: Equatable, Sendable {
    var query = ""
    var genreID: Int?
    var providerID: Int?
    var sort = "popularity.desc"
    var actionValue: [String: Any] {
        var value: [String: Any] = ["sortBy": sort]
        if let genreID { value["genreId"] = genreID }
        if let providerID { value["watchProviderId"] = providerID }
        return value
    }
}

struct CatalogPage: Sendable {
    var items: [MediaTitle]
    var page: Int
    var totalPages: Int
}

struct MediaEpisode: Identifiable, Codable, Sendable {
    let id: Int
    let name: String
    let episode_number: Int
    var still_path: String?
    var overview: String?
}

struct WatchProgress: Codable, Identifiable, Sendable {
    let title: MediaTitle
    var position: Double
    var duration: Double
    var season: Int?
    var episode: Int?
    var updatedAt: Date
    var id: String { title.id }
    var fraction: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
}

enum WatchedError: Error, LocalizedError {
    case blocked
    case server(Int)
    case malformed
    case playbackIntegrationPending
    case unsupportedStream
    var errorDescription: String? {
        switch self {
        case .blocked: return "تعذّر الاتصال بالمصدر من هذه الشبكة. حاول لاحقاً."
        case .server: return "المصدر غير متاح حالياً. حاول مرة ثانية."
        case .malformed: return "تعذّر تحميل بيانات هذا القسم."
        case .playbackIntegrationPending: return "المشاهدة غير متاحة في هذه النسخة التجريبية بعد."
        case .unsupportedStream: return "صيغة الفيديو غير مدعومة على هذا الجهاز."
        }
    }
}
