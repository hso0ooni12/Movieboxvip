import Foundation
import SwiftUI

enum XSVODKind: String, Codable, Sendable { case movie, series }

struct XSVODCategory: Hashable, Codable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct XSVODTitle: Codable, Hashable, Identifiable, Sendable {
    let kind: XSVODKind
    let streamID: Int
    let title: String
    let categoryID: String
    let poster: String?
    let backdrop: String?
    let plot: String
    let genre: String
    let released: String
    let rating: Double
    let fileExtension: String
    let added: Int

    var id: String { kind.rawValue + ":" + String(streamID) }
    var imageURL: URL? {
        guard let poster, let url = URL(string: poster),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
    var backdropURL: URL? {
        guard let backdrop, let url = URL(string: backdrop),
              ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return imageURL }
        return url
    }
    var year: String {
        let match = released.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression)
        if let match { return String(released[match]) }
        let titleMatch = title.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression)
        return titleMatch.map { String(title[$0]) } ?? ""
    }
}

struct XSVODEpisode: Codable, Hashable, Identifiable, Sendable {
    let id: Int
    let season: Int
    let number: Int
    let name: String
    let fileExtension: String
    let poster: String?
    let synopsis: String
    var imageURL: URL? { poster.flatMap(URL.init(string:)) }
}

struct XSVODCatalogSnapshot: Codable, Sendable {
    let categoriesMovies: [XSVODCategory]
    let categoriesSeries: [XSVODCategory]
    let movies: [XSVODTitle]
    let series: [XSVODTitle]
    let timestamp: Date
}

enum XSVODFailure: LocalizedError {
    case notConfigured, unavailable, forbidden, malformed
    var errorDescription: String? {
        switch self {
        case .notConfigured: return "بيانات اشتراك الأفلام والمسلسلات غير متوفرة."
        case .unavailable: return "تعذر الاتصال بمكتبة الفيديو. حاول مرة ثانية."
        case .forbidden: return "الاشتراك الحالي لا يسمح بعرض هذا المحتوى."
        case .malformed: return "مزود الخدمة رجّع بيانات غير صالحة."
        }
    }
}

actor XSVODService {
    static let shared = XSVODService()

    private var config: IPTVCredentials? {
        guard let credentials = XSIPTVEmbeddedConfig.credentials, credentials.isComplete else { return nil }
        return credentials
    }

    private static func string(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }
    private static func number(_ v: Any?) -> Int {
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s) ?? 0 }
        return 0
    }
    private static func rating(_ v: Any?) -> Double {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) ?? 0 }
        return 0
    }
    private static func isAllowed(_ name: String) -> Bool {
        let lower = name.lowercased()
        let restricted = ["xxx", "18+", "adult", "porn", "erotic",
                          "sex movies", "onlyfans", "playboy", "hentai",
                          "anime", "أنمي", "انمي", "аниме"]
        return !restricted.contains { lower.contains($0) }
    }

    private func request(_ action: String, parameter: (String, String)? = nil) async throws -> Any {
        guard let config else { throw XSVODFailure.notConfigured }
        guard var components = URLComponents(string: config.normalizedHost + "/player_api.php") else {
            throw XSVODFailure.malformed
        }
        var queries: [URLQueryItem] = [
            .init(name: "username", value: config.username),
            .init(name: "password", value: config.password),
            .init(name: "action", value: action)
        ]
        if let parameter { queries.append(.init(name: parameter.0, value: parameter.1)) }
        components.queryItems = queries
        guard let url = components.url else { throw XSVODFailure.malformed }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 40)
        request.setValue("XS-TV/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw XSVODFailure.unavailable }
            if http.statusCode == 401 || http.statusCode == 403 { throw XSVODFailure.forbidden }
            guard (200..<300).contains(http.statusCode) else { throw XSVODFailure.unavailable }
            return try JSONSerialization.jsonObject(with: data)
        } catch let error as XSVODFailure {
            throw error
        } catch {
            // Never surface the original URLSession error; some error messages
            // contain the username/password URL from Xtream player_api.php.
            throw XSVODFailure.unavailable
        }
    }

    private func categories(action: String) async throws -> [XSVODCategory] {
        guard let rows = try await request(action) as? [[String: Any]] else {
            throw XSVODFailure.malformed
        }
        return rows.compactMap { row in
            let id = Self.string(row["category_id"])
            let name = Self.string(row["category_name"])
            guard !id.isEmpty && !name.isEmpty && Self.isAllowed(name) else { return nil }
            return XSVODCategory(id: id, name: name)
        }
    }

    private func titles(action: String, kind: XSVODKind,
                        allowedCategories: Set<String>) async throws -> [XSVODTitle] {
        guard let rows = try await request(action) as? [[String: Any]] else {
            throw XSVODFailure.malformed
        }
        return rows.compactMap { row in
            let id = Self.number(row[kind == .movie ? "stream_id" : "series_id"])
            let name = Self.string(row["name"])
            let cat = Self.string(row["category_id"])
            guard id > 0, !name.isEmpty, Self.isAllowed(name),
                  allowedCategories.contains(cat) else { return nil }
            let backdrops = (row["backdrop_path"] as? [String]) ?? []
            return XSVODTitle(
                kind: kind, streamID: id, title: name, categoryID: cat,
                poster: Self.string(row[kind == .movie ? "stream_icon" : "cover"]),
                backdrop: backdrops.first,
                plot: Self.string(row["plot"]),
                genre: Self.string(row["genre"]),
                released: Self.string(row["releaseDate"] ?? row["releasedate"]),
                rating: Self.rating(row["rating"]),
                fileExtension: Self.string(row["container_extension"]),
                added: Self.number(row["added"] ?? row["last_modified"])
            )
        }
    }

    // Load the two massive VOD catalogs independently so movies appear while
    // the provider is still loading thousands of series (and vice versa).
    func catalogFor(kind: XSVODKind) async throws -> ([XSVODCategory], [XSVODTitle]) {
        let categoriesAction = kind == .movie ? "get_vod_categories" : "get_series_categories"
        let titlesAction = kind == .movie ? "get_vod_streams" : "get_series"
        let categories = try await categories(action: categoriesAction)
        let items = try await titles(action: titlesAction, kind: kind,
                                     allowedCategories: Set(categories.map(\.id)))
        return (categories, items)
    }

    func catalog() async throws -> XSVODCatalogSnapshot {
        async let movieCategories = categories(action: "get_vod_categories")
        async let seriesCategories = categories(action: "get_series_categories")
        let mc = try await movieCategories
        let sc = try await seriesCategories
        async let movies = titles(action: "get_vod_streams", kind: .movie,
                                  allowedCategories: Set(mc.map(\.id)))
        async let series = titles(action: "get_series", kind: .series,
                                  allowedCategories: Set(sc.map(\.id)))
        return try await XSVODCatalogSnapshot(
            categoriesMovies: mc, categoriesSeries: sc,
            movies: movies, series: series, timestamp: Date())
    }

    func moviePlaybackURL(_ item: XSVODTitle) -> URL? {
        guard item.kind == .movie else { return nil }
        return playbackURL(path: "movie", id: item.streamID, ext: item.fileExtension)
    }

    func episodePlaybackURL(_ item: XSVODEpisode) -> URL? {
        playbackURL(path: "series", id: item.id, ext: item.fileExtension)
    }

    private func playbackURL(path: String, id: Int, ext: String) -> URL? {
        guard let config, id > 0 else { return nil }
        let safe = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
        let user = config.username.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
        let pass = config.password.addingPercentEncoding(withAllowedCharacters: safe) ?? ""
        let suffix = ext.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExt = ["mkv", "mp4", "ts", "m3u8", "avi", "mov"].contains(suffix) ? suffix : "mp4"
        return URL(string: "\(config.normalizedHost)/\(path)/\(user)/\(pass)/\(id).\(cleanExt)")
    }

    func episodes(for seriesID: Int) async throws -> [XSVODEpisode] {
        guard let response = try await request("get_series_info",
                                               parameter: ("series_id", String(seriesID))) as? [String: Any],
              let seasons = response["episodes"] as? [String: Any] else {
            throw XSVODFailure.malformed
        }
        var result: [XSVODEpisode] = []
        for (season, value) in seasons {
            guard let rows = value as? [[String: Any]] else { continue }
            for row in rows {
                let info = row["info"] as? [String: Any] ?? [:]
                let episodeID = Self.number(row["id"])
                guard episodeID > 0 else { continue }
                result.append(XSVODEpisode(
                    id: episodeID, season: Int(season) ?? 0,
                    number: Self.number(row["episode_num"]),
                    name: Self.string(row["title"]).isEmpty
                        ? "Episode \(Self.number(row["episode_num"]))"
                        : Self.string(row["title"]),
                    fileExtension: Self.string(row["container_extension"]),
                    poster: Self.string(info["movie_image"]),
                    synopsis: Self.string(info["plot"])
                ))
            }
        }
        return result.sorted { a, b in
            a.season == b.season ? a.number < b.number : a.season < b.season
        }
    }
}

@MainActor
final class XSVODCatalogStore: ObservableObject {
    @Published private(set) var movies: [XSVODTitle] = []
    @Published private(set) var series: [XSVODTitle] = []
    @Published private(set) var movieCategories: [XSVODCategory] = []
    @Published private(set) var seriesCategories: [XSVODCategory] = []
    @Published private(set) var loading = false
    @Published private(set) var loaded = false
    @Published private(set) var message: String?
    @Published private(set) var favorites = Set<String>()

    private let favoritesKey = "XSTV.VOD.favorites.v1"
    private let cacheName = "xs-vod-catalog-v1.json"

    private var lastFetched: Date?

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        // Never synchronously read/decode the 33k-title JSON snapshot on
        // main during app launch. Restoring is off-main in load().
    }

    var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent(cacheName)
    }

    func byKind(_ kind: XSVODKind) -> [XSVODTitle] {
        kind == .movie ? movies : series
    }

    func categories(_ kind: XSVODKind) -> [XSVODCategory] {
        kind == .movie ? movieCategories : seriesCategories
    }

    func favorite(_ item: XSVODTitle) -> Bool { favorites.contains(item.id) }

    func toggle(_ item: XSVODTitle) {
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        UserDefaults.standard.set(Array(favorites), forKey: favoritesKey)
    }

    private func restoreSnapshot() async {
        guard !loaded, let url = cacheURL else { return }
        let cached = await Task.detached(priority: .utility) { () -> XSVODCatalogSnapshot? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(XSVODCatalogSnapshot.self, from: data)
        }.value
        guard let cached, !loaded else { return }
        apply(cached)
    }

    func load(force: Bool = false) async {
        guard !loading else { return }
        if !force && !loaded { await restoreSnapshot() }
        if !force, let lastFetched,
           Date().timeIntervalSince(lastFetched) < 6 * 3600 { return }

        loading = true
        message = nil
        defer { loading = false }

        async let movieTask = XSVODService.shared.catalogFor(kind: .movie)
        async let seriesTask = XSVODService.shared.catalogFor(kind: .series)
        var gotNewData = false

        if let result = try? await movieTask {
            movieCategories = result.0
            movies = result.1
            loaded = true
            gotNewData = true
        }
        // Publish movie results immediately; don't await series first.
        if let result = try? await seriesTask {
            seriesCategories = result.0
            series = result.1
            loaded = true
            gotNewData = true
        }
        if gotNewData {
            lastFetched = Date()
            if let url = cacheURL, !movies.isEmpty && !series.isEmpty {
                let snapshot = XSVODCatalogSnapshot(
                    categoriesMovies: movieCategories, categoriesSeries: seriesCategories,
                    movies: movies, series: series, timestamp: Date())
                Task.detached(priority: .utility) {
                    if let data = try? JSONEncoder().encode(snapshot) {
                        try? data.write(to: url, options: .atomic)
                    }
                }
            }
        } else if !loaded {
            message = "تعذر تحميل مكتبة الأفلام والمسلسلات. افحص اتصالك ثم حاول مرة ثانية."
        }
    }

    private func apply(_ snapshot: XSVODCatalogSnapshot) {
        movieCategories = snapshot.categoriesMovies
        seriesCategories = snapshot.categoriesSeries
        movies = snapshot.movies
        series = snapshot.series
        loaded = true
        lastFetched = snapshot.timestamp
    }
}
