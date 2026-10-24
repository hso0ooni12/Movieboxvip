import Foundation

enum MediaKind: String, Codable, CaseIterable {
    case movie, series

    var title: String { self == .movie ? "الأفلام" : "المسلسلات" }
    var catalogPath: String { self == .movie ? "movie" : "series" }
}

struct Episode: Codable, Hashable, Identifiable {
    var season: Int
    var number: Int
    var title: String
    var artworkURL: URL?
    var id: String { "\(season)-\(number)" }
}

struct MediaTitle: Hashable, Identifiable {
    let id: String
    let title: String
    let kind: MediaKind
    var synopsis: String
    var year: String
    var rating: String
    var posterURL: URL?
    var backdropURL: URL?
    var episodes: [Episode]
    var genres: [String] = []

    var seasons: [Int] { Array(Set(episodes.map(\.season))).sorted() }
}

struct VideoSource: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let quality: String
    let url: URL

    var isSupported: Bool { ["https"].contains(url.scheme?.lowercased() ?? "") }
}

struct SubtitleSource: Codable, Hashable, Identifiable {
    let id: String
    let label: String
    let language: String
    let url: URL
}

struct PlaybackEntry: Codable, Hashable {
    var sources: [VideoSource]
    var subtitles: [SubtitleSource]
}

struct PlaybackFeed: Decodable {
    let version: Int
    let entries: [String: PlaybackEntry]
}

struct CinemetaCatalogResponse: Decodable {
    let metas: [CinemetaItem]
}

struct CinemetaDetailsResponse: Decodable {
    let meta: CinemetaItem
}

struct CinemetaItem: Decodable {
    let id: String
    let name: String
    let description: String?
    let poster: String?
    let background: String?
    let releaseInfo: String?
    let imdbRating: String?
    let videos: [CinemetaEpisode]?
    let genres: [String]?

    func asTitle(_ kind: MediaKind) -> MediaTitle {
        MediaTitle(id: id, title: name, kind: kind,
                   synopsis: description ?? "",
                   year: releaseInfo ?? "",
                   rating: imdbRating ?? "",
                   posterURL: poster.flatMap(URL.init(string:)),
                   backdropURL: background.flatMap(URL.init(string:)),
                   episodes: (videos ?? []).compactMap { video in
                       guard let season = video.season, let number = video.episode,
                             season > 0, number > 0 else { return nil }
                       return Episode(season: season, number: number,
                                      title: video.title ?? "الحلقة \(number)",
                                      artworkURL: video.thumbnail.flatMap(URL.init(string:)))
                   }.sorted { $0.season == $1.season ? $0.number < $1.number : $0.season < $1.season },
                   genres: genres ?? [])
    }
}

struct CinemetaEpisode: Decodable {
    let season: Int?
    let episode: Int?
    let title: String?
    let thumbnail: String?
}

enum PlaybackKey {
    static func movie(_ id: String) -> String { "movie:\(id)" }
    static func episode(_ id: String, season: Int, number: Int) -> String {
        "series:\(id):\(season):\(number)"
    }
}
