import Foundation

struct TMDBClient {
    enum APIError: LocalizedError {
        case missingToken
        case invalidResponse
        case http(Int, String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .missingToken: return "TMDB token is missing."
            case .invalidResponse: return "The server returned an invalid response."
            case .http(let code, let message): return message.isEmpty ? "TMDB request failed (\(code))." : message
            case .decoding: return "Couldn’t read the catalog response."
            }
        }
    }

    let token: String
    let language: String
    private let base = URL(string: "https://api.themoviedb.org/3")!

    init(token: String, language: String = "en-US") {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.language = language
    }

    func validate() async throws {
        _ = try await request(path: "/configuration", query: [], as: ConfigurationResponse.self)
    }

    func trendingMovies(page: Int = 1) async throws -> [MediaItem] {
        let response = try await request(path: "/trending/movie/week", query: [
            .init(name: "language", value: language),
            .init(name: "page", value: String(page))
        ], as: ListResponse.self)
        return response.results.compactMap { $0.mediaItem(forcedKind: .movie) }
    }

    func trendingTV(page: Int = 1) async throws -> [MediaItem] {
        let response = try await request(path: "/trending/tv/week", query: [
            .init(name: "language", value: language),
            .init(name: "page", value: String(page))
        ], as: ListResponse.self)
        return response.results.compactMap { $0.mediaItem(forcedKind: .tv) }
    }

    func anime(page: Int = 1) async throws -> [MediaItem] {
        let response = try await request(path: "/discover/tv", query: [
            .init(name: "language", value: language),
            .init(name: "page", value: String(page)),
            .init(name: "sort_by", value: "popularity.desc"),
            .init(name: "with_genres", value: "16"),
            .init(name: "with_original_language", value: "ja"),
            .init(name: "include_adult", value: "false")
        ], as: ListResponse.self)
        return response.results.compactMap {
            guard var item = $0.mediaItem(forcedKind: .anime) else { return nil }
            item = MediaItem(
                tmdbID: item.tmdbID,
                kind: .anime,
                title: item.title,
                overview: item.overview,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                releaseDate: item.releaseDate,
                voteAverage: item.voteAverage,
                genreIDs: item.genreIDs
            )
            return item
        }
    }

    func popularMovies(page: Int = 1) async throws -> [MediaItem] {
        let response = try await request(path: "/movie/popular", query: [
            .init(name: "language", value: language),
            .init(name: "page", value: String(page))
        ], as: ListResponse.self)
        return response.results.compactMap { $0.mediaItem(forcedKind: .movie) }
    }

    func popularTV(page: Int = 1) async throws -> [MediaItem] {
        let response = try await request(path: "/tv/popular", query: [
            .init(name: "language", value: language),
            .init(name: "page", value: String(page))
        ], as: ListResponse.self)
        return response.results.compactMap { $0.mediaItem(forcedKind: .tv) }
    }

    func search(_ query: String, page: Int = 1) async throws -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response = try await request(path: "/search/multi", query: [
            .init(name: "query", value: trimmed),
            .init(name: "language", value: language),
            .init(name: "page", value: String(page)),
            .init(name: "include_adult", value: "false")
        ], as: ListResponse.self)
        return response.results.compactMap { result in
            guard let type = result.mediaType else { return nil }
            switch type {
            case "movie": return result.mediaItem(forcedKind: .movie)
            case "tv": return result.mediaItem(forcedKind: result.isLikelyAnime ? .anime : .tv)
            default: return nil
            }
        }
    }

    func details(for item: MediaItem) async throws -> MediaDetails {
        switch item.kind {
        case .movie:
            let r = try await request(path: "/movie/\(item.tmdbID)", query: [
                .init(name: "language", value: language)
            ], as: DetailsResponse.self)
            return r.mediaDetails(fallback: item, kind: .movie)
        case .tv, .anime:
            let r = try await request(path: "/tv/\(item.tmdbID)", query: [
                .init(name: "language", value: language)
            ], as: DetailsResponse.self)
            return r.mediaDetails(fallback: item, kind: item.kind)
        }
    }

    func seasons(for item: MediaItem) async throws -> [SeasonInfo] {
        guard item.kind != .movie else { return [] }
        let r = try await request(path: "/tv/\(item.tmdbID)", query: [
            .init(name: "language", value: language)
        ], as: DetailsResponse.self)
        return (r.seasons ?? []).filter { $0.seasonNumber > 0 }.map {
            SeasonInfo(id: $0.id, seasonNumber: $0.seasonNumber, name: $0.name, episodeCount: $0.episodeCount, posterPath: $0.posterPath)
        }
    }

    func episodes(tmdbID: Int, season: Int) async throws -> [Episode] {
        let r = try await request(path: "/tv/\(tmdbID)/season/\(season)", query: [
            .init(name: "language", value: language)
        ], as: SeasonResponse.self)
        return r.episodes.map {
            Episode(id: $0.id, episodeNumber: $0.episodeNumber, name: $0.name, overview: $0.overview ?? "", airDate: $0.airDate, stillPath: $0.stillPath, runtime: $0.runtime)
        }
    }

    private func request<T: Decodable>(path: String, query: [URLQueryItem], as type: T.Type) async throws -> T {
        guard !token.isEmpty else { throw APIError.missingToken }
        guard var components = URLComponents(url: base.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidResponse
        }
        components.queryItems = query
        guard let url = components.url else { throw APIError.invalidResponse }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FrameNative/2.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).statusMessage) ?? ""
            throw APIError.http(http.statusCode, message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

private struct ConfigurationResponse: Decodable {
    let images: ConfigurationImages?
}
private struct ConfigurationImages: Decodable {
    let secureBaseURL: String?
    enum CodingKeys: String, CodingKey { case secureBaseURL = "secure_base_url" }
}
private struct ErrorResponse: Decodable {
    let statusMessage: String?
    enum CodingKeys: String, CodingKey { case statusMessage = "status_message" }
}
private struct ListResponse: Decodable {
    let results: [ListResult]
}
private struct ListResult: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let genreIDs: [Int]?
    let mediaType: String?
    let originalLanguage: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case genreIDs = "genre_ids"
        case mediaType = "media_type"
        case originalLanguage = "original_language"
    }

    var isLikelyAnime: Bool {
        originalLanguage == "ja" && (genreIDs ?? []).contains(16)
    }

    func mediaItem(forcedKind: MediaKind) -> MediaItem? {
        let resolvedTitle = (title ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedTitle.isEmpty else { return nil }
        return MediaItem(
            tmdbID: id,
            kind: forcedKind,
            title: resolvedTitle,
            overview: overview ?? "",
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: releaseDate ?? firstAirDate,
            voteAverage: voteAverage ?? 0,
            genreIDs: genreIDs ?? []
        )
    }
}

private struct DetailsResponse: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let runtime: Int?
    let episodeRunTime: [Int]?
    let numberOfSeasons: Int?
    let status: String?
    let tagline: String?
    let genres: [GenreResponse]?
    let seasons: [SeasonListResponse]?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, runtime, status, tagline, genres, seasons
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case episodeRunTime = "episode_run_time"
        case numberOfSeasons = "number_of_seasons"
    }

    func mediaDetails(fallback: MediaItem, kind: MediaKind) -> MediaDetails {
        let genreNames = (genres ?? []).map(\.name)
        let runtimeValue = runtime ?? episodeRunTime?.first
        let item = MediaItem(
            tmdbID: id,
            kind: kind,
            title: title ?? name ?? fallback.title,
            overview: overview ?? fallback.overview,
            posterPath: posterPath ?? fallback.posterPath,
            backdropPath: backdropPath ?? fallback.backdropPath,
            releaseDate: releaseDate ?? firstAirDate ?? fallback.releaseDate,
            voteAverage: voteAverage ?? fallback.voteAverage,
            genreIDs: fallback.genreIDs
        )
        return MediaDetails(item: item, runtime: runtimeValue, numberOfSeasons: numberOfSeasons, status: status, tagline: tagline, genres: genreNames)
    }
}
private struct GenreResponse: Decodable {
    let id: Int
    let name: String
}
private struct SeasonListResponse: Decodable {
    let id: Int
    let seasonNumber: Int
    let name: String
    let episodeCount: Int
    let posterPath: String?
    enum CodingKeys: String, CodingKey {
        case id, name
        case seasonNumber = "season_number"
        case episodeCount = "episode_count"
        case posterPath = "poster_path"
    }
}
private struct SeasonResponse: Decodable {
    let episodes: [EpisodeResponse]
}
private struct EpisodeResponse: Decodable {
    let id: Int
    let episodeNumber: Int
    let name: String
    let overview: String?
    let airDate: String?
    let stillPath: String?
    let runtime: Int?
    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case stillPath = "still_path"
    }
}
