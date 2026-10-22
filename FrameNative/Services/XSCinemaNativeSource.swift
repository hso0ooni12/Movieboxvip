import SwiftUI
import Foundation

// Native browsing model. Cinemeta is a *catalog*, not an unlicensed video source.
// Only explicitly CC-licensed Internet Archive videos have native Play URLs.
enum XSCinemaMediaKind: String, Codable, Sendable {
    case movie, series
    var label: String { self == .movie ? "فيلم" : "مسلسل" }
}

struct XSCinemaMedia: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let kind: XSCinemaMediaKind
    var poster: String?
    var backdrop: String?
    var summary: String
    var year: String
    var rating: Double
    var playableURL: String?
    var sourceURL: String?
    var licenseURL: String?
    var imdbID: String?
    var tmdbID: Int?
    var episodes: [XSCinemaEpisode]

    var imageURL: URL? { poster.flatMap(URL.init(string:)) }
    var backdropURL: URL? { backdrop.flatMap(URL.init(string:)) ?? imageURL }
    var streamURL: URL? { playableURL.flatMap(URL.init(string:)) }
    var isPlayable: Bool { streamURL != nil && licenseURL != nil }
}

struct XSCinemaEpisode: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    let thumbnail: String?
}

// The Cinemeta "metas" array contains heterogeneous objects. One malformed
// artwork/episode value must not blank out the entire home page.
actor XSCinemaCatalogAPI {
    static let shared = XSCinemaCatalogAPI()
    private let base = "https://v3-cinemeta.strem.io"

    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 14)
        request.setValue("XS-TV/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let r = response as? HTTPURLResponse,
              (200..<300).contains(r.statusCode), !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func string(_ value: Any?) -> String? {
        if let str = value as? String { return str }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func media(_ object: [String: Any], kind: XSCinemaMediaKind) -> XSCinemaMedia? {
        guard let id = string(object["id"]), !id.isEmpty,
              let title = string(object["name"]), !title.isEmpty else { return nil }
        let eps = (object["videos"] as? [[String: Any]] ?? []).compactMap { ep -> XSCinemaEpisode? in
            guard let seasonText = string(ep["season"]), let season = Int(seasonText),
                  let numberText = string(ep["episode"]), let number = Int(numberText),
                  season > 0, number > 0 else { return nil }
            let episodeID = string(ep["id"]) ?? id + ":\(season):\(number)"
            return XSCinemaEpisode(id: episodeID, season: season, number: number,
                                   title: string(ep["title"]) ?? "Episode \(number)",
                                   thumbnail: string(ep["thumbnail"]))
        }
        let tmdb = string(object["moviedb_id"]).flatMap(Int.init)
        let stars = string(object["imdbRating"]).flatMap(Double.init) ?? 0
        return XSCinemaMedia(
            id: kind.rawValue + ":" + id, title: title, kind: kind,
            poster: string(object["poster"]), backdrop: string(object["background"]),
            summary: string(object["description"]) ?? "",
            year: string(object["releaseInfo"]) ?? string(object["year"]) ?? "",
            rating: stars, playableURL: nil,
            sourceURL: nil, licenseURL: nil, imdbID: id,
            tmdbID: tmdb, episodes: eps)
    }

    private func catalogResponse(_ url: URL, kind: XSCinemaMediaKind) async throws -> [XSCinemaMedia] {
        let payload = try await data(url)
        return Self.decodeCatalog(payload, kind: kind)
    }

    nonisolated static func decodeCatalog(_ payload: Data, kind: XSCinemaMediaKind) -> [XSCinemaMedia] {
        // Keep parser non-throwing for individual missing fields.
        guard let top = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let rows = top["metas"] as? [[String: Any]] else { return [] }
        // Swift-actor isolation: a static nonisolated factory does not access actor
        // instance fields, so keep a local primitive converter here.
        func str(_ obj: Any?) -> String? {
            if let text = obj as? String { return text }
            if let num = obj as? NSNumber { return num.stringValue }
            return nil
        }
        return rows.compactMap { row -> XSCinemaMedia? in
            guard let id = str(row["id"]), !id.isEmpty,
                  let title = str(row["name"]), !title.isEmpty else { return nil }
            let episodes = (row["videos"] as? [[String: Any]] ?? []).compactMap { ep -> XSCinemaEpisode? in
                guard let seasonS = str(ep["season"]), let season = Int(seasonS),
                      let episodeS = str(ep["episode"]), let number = Int(episodeS),
                      season > 0, number > 0 else { return nil }
                return XSCinemaEpisode(
                    id: str(ep["id"]) ?? "\(id):\(season):\(number)",
                    season: season, number: number,
                    title: str(ep["title"]) ?? "Episode \(number)",
                    thumbnail: str(ep["thumbnail"]))
            }
            return XSCinemaMedia(
                id: kind.rawValue + ":" + id, title: title, kind: kind,
                poster: str(row["poster"]), backdrop: str(row["background"]),
                summary: str(row["description"]) ?? "",
                year: str(row["releaseInfo"]) ?? str(row["year"]) ?? "",
                rating: str(row["imdbRating"]).flatMap(Double.init) ?? 0,
                playableURL: nil, sourceURL: nil, licenseURL: nil,
                imdbID: id,
                tmdbID: str(row["moviedb_id"]).flatMap(Int.init),
                episodes: episodes)
        }
    }

    func catalog(_ kind: XSCinemaMediaKind, skip: Int = 0) async throws -> [XSCinemaMedia] {
        let extra = skip == 0 ? "" : "/skip=\(skip)"
        guard let url = URL(string: base + "/catalog/\(kind.rawValue)/top\(extra).json")
        else { return [] }
        return try await catalogResponse(url, kind: kind)
    }

    func search(_ phrase: String, kind: XSCinemaMediaKind) async throws -> [XSCinemaMedia] {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: base + "/catalog/\(kind.rawValue)/top/search=\(encoded).json")
        else { return [] }
        return try await catalogResponse(url, kind: kind)
    }

    func detail(_ item: XSCinemaMedia) async -> XSCinemaMedia {
        guard let imdb = item.imdbID,
              let url = URL(string: base + "/meta/\(item.kind.rawValue)/\(imdb).json"),
              let payload = try? await data(url),
              let top = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let object = top["meta"] as? [String: Any],
              let body = try? JSONSerialization.data(withJSONObject: ["metas": [object]]),
              let updated = Self.decodeCatalog(body, kind: item.kind).first else {
            return item
        }
        return updated
    }

    func openFilms() async -> [XSCinemaMedia] {
        var components = URLComponents(string: "https://archive.org/advancedsearch.php")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "mediatype:movies AND licenseurl:http*"),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "rows", value: "20"),
            URLQueryItem(name: "output", value: "json")
        ]
        guard let url = components.url,
              let raw = try? await data(url),
              let body = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let response = body["response"] as? [String: Any],
              let docs = response["docs"] as? [[String: Any]] else { return [] }

        var films: [XSCinemaMedia] = []
        // Limited lightweight scan: not more than ten entries, no video downloads.
        for item in docs.prefix(10) {
            guard let id = item["identifier"] as? String,
                  id.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
                  let endpoint = URL(string: "https://archive.org/metadata/\(id)"),
                  let data = try? await data(endpoint),
                  let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let meta = info["metadata"] as? [String: Any],
                  let license = meta["licenseurl"] as? String,
                  license.contains("creativecommons.org/licenses/by/") ||
                    license.contains("creativecommons.org/licenses/by-sa/") ||
                    license.contains("creativecommons.org/publicdomain/zero/"),
                  let files = info["files"] as? [[String: Any]] else { continue }

            let mp4 = files.compactMap { f -> (String, Int)? in
                guard let filename = f["name"] as? String,
                      filename.lowercased().hasSuffix(".mp4"),
                      let bytes = Int(f["size"] as? String ?? ""), bytes > 4_000_000,
                      bytes < 3_000_000_000 else { return nil }
                return (filename, bytes)
            }.sorted { $0.1 < $1.1 }.first?.0
            guard let filename = mp4,
                  let escaped = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            else { continue }
            let artwork = files.compactMap { $0["name"] as? String }
                .first { $0.lowercased().hasSuffix(".jpg") }
                .flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
                .map { "https://archive.org/download/\(id)/\($0)" }
            films.append(XSCinemaMedia(
                id: "archive:" + id,
                title: (meta["title"] as? String) ?? id,
                kind: .movie, poster: artwork, backdrop: artwork,
                summary: "فيلم بترخيص مفتوح من Internet Archive.",
                year: "", rating: 0,
                playableURL: "https://archive.org/download/\(id)/\(escaped)",
                sourceURL: "https://archive.org/details/\(id)",
                licenseURL: license, imdbID: nil, tmdbID: nil, episodes: []))
        }
        return films
    }
}

@MainActor
final class XSCinemaNativeStore: ObservableObject {
    @Published private(set) var movies: [XSCinemaMedia] = []
    @Published private(set) var series: [XSCinemaMedia] = []
    @Published private(set) var freeMovies: [XSCinemaMedia] = []
    @Published private(set) var loading = false
    @Published private(set) var loadingMore: Set<XSCinemaMediaKind> = []
    @Published private(set) var error: String?
    @Published private(set) var favorites = Set<String>()
    private let favoriteKey = "XSTV.NativeCinema.Favorites"
    private var skips: [XSCinemaMediaKind:Int] = [.movie:0, .series:0]
    private var loaded = false
    init() { favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? []) }

    func list(_ kind: XSCinemaMediaKind) -> [XSCinemaMedia] {
        kind == .movie ? movies : series
    }
    func favorite(_ item: XSCinemaMedia) -> Bool { favorites.contains(item.id) }
    func toggle(_ item: XSCinemaMedia) {
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        UserDefaults.standard.set(Array(favorites),forKey:favoriteKey)
    }
    private func bundled(_ kind: XSCinemaMediaKind) -> [XSCinemaMedia] {
        guard let url = Bundle.main.url(forResource: "xs-cinema-\(kind.rawValue)-bootstrap",
                                        withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return XSCinemaCatalogAPI.decodeCatalog(data, kind: kind)
    }

    func boot() async {
        guard !loaded && !loading else { return }
        loading = true
        defer { loading = false }
        // On-device network errors must not leave all tabs blank.
        if movies.isEmpty { movies = bundled(.movie) }
        if series.isEmpty { series = bundled(.series) }
        loaded = !movies.isEmpty || !series.isEmpty
        error = nil
        async let a = XSCinemaCatalogAPI.shared.catalog(.movie)
        async let b = XSCinemaCatalogAPI.shared.catalog(.series)
        do {
            let fetched = try await a
            if !fetched.isEmpty {
                movies = fetched
                skips[.movie] = fetched.count
                loaded = true
            }
        } catch {
            if movies.isEmpty { self.error = "تعذر جلب الأفلام، جرّب تحديث الاتصال." }
        }
        do {
            let fetched = try await b
            if !fetched.isEmpty {
                series = fetched
                skips[.series] = fetched.count
                loaded = true
            }
        } catch {
            if series.isEmpty { self.error = "تعذر جلب المسلسلات، جرّب تحديث الاتصال." }
        }
        // Open-license scanning is separate: don't block home or navigation.
        Task { [weak self] in
            let publicTitles = await XSCinemaCatalogAPI.shared.openFilms()
            self?.freeMovies = publicTitles
        }
    }
    func more(_ kind: XSCinemaMediaKind) async {
        guard !loadingMore.contains(kind) else { return }
        loadingMore.insert(kind)
        defer { loadingMore.remove(kind) }
        do {
            let incoming = try await XSCinemaCatalogAPI.shared.catalog(kind,skip:skips[kind] ?? 0)
            let old = Set(list(kind).map(\.id))
            let unique = incoming.filter { !old.contains($0.id) }
            if kind == .movie { movies.append(contentsOf: unique) }
            else { series.append(contentsOf: unique) }
            skips[kind,default:0] += incoming.count
        } catch { self.error = "تعذر تحميل المزيد حالياً." }
    }
}
