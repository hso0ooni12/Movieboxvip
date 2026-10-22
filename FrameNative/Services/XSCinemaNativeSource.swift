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
    var episodes: [XSCinemaEpisode]
    var tmdbID: Int? = nil

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

private struct XSCinemaCinemetaCatalog: Decodable {
    let metas: [XSCinemaCinemetaMeta]
}
private struct XSCinemaCinemetaMeta: Decodable {
    let id: String
    let name: String
    let type: String?
    let poster: String?
    let background: String?
    let description: String?
    let releaseInfo: String?
    let imdbRating: String?
    let videos: [XSCinemaCinemetaVideo]?
}
private struct XSCinemaCinemetaVideo: Decodable {
    let id: String
    let season: Int?
    let episode: Int?
    let title: String?
    let thumbnail: String?
}
private struct XSCinemaCinemetaDetail: Decodable {
    let meta: XSCinemaCinemetaMeta
}

actor XSCinemaCatalogAPI {
    static let shared = XSCinemaCatalogAPI()
    private let base = "https://v3-cinemeta.strem.io"

    private func data(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 18)
        request.setValue("XS-TV-Native-Cinema/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let r = response as? HTTPURLResponse,
              (200..<300).contains(r.statusCode), !data.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func media(_ meta: XSCinemaCinemetaMeta, kind: XSCinemaMediaKind) -> XSCinemaMedia {
        let eps = (meta.videos ?? []).compactMap { v -> XSCinemaEpisode? in
            guard let season = v.season, let number = v.episode, season > 0 else { return nil }
            return XSCinemaEpisode(id: v.id, season: season, number: number,
                                   title: v.title ?? "Episode \(number)", thumbnail: v.thumbnail)
        }
        return XSCinemaMedia(id: kind.rawValue + ":" + meta.id,
                             title: meta.name, kind: kind,
                             poster: meta.poster, backdrop: meta.background,
                             summary: meta.description ?? "",
                             year: meta.releaseInfo ?? "",
                             rating: Double(meta.imdbRating ?? "") ?? 0,
                             playableURL: nil, sourceURL: nil, licenseURL: nil,
                             imdbID: meta.id, episodes: eps)
    }

    func catalog(_ kind: XSCinemaMediaKind, skip: Int = 0) async throws -> [XSCinemaMedia] {
        let extra = skip == 0 ? "" : "/skip=\(skip)"
        guard let url = URL(string: base + "/catalog/\(kind.rawValue)/top\(extra).json") else { return [] }
        let bytes = try await data(url)
        let value = try JSONDecoder().decode(XSCinemaCinemetaCatalog.self, from: bytes)
        return value.metas.map { media($0,kind:kind) }
    }

    func search(_ phrase: String, kind: XSCinemaMediaKind) async throws -> [XSCinemaMedia] {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: base + "/catalog/\(kind.rawValue)/top/search=\(encoded).json") else { return [] }
        let bytes = try await data(url)
        let value = try JSONDecoder().decode(XSCinemaCinemetaCatalog.self, from: bytes)
        return value.metas.map { media($0,kind:kind) }
    }

    func detail(_ item: XSCinemaMedia) async -> XSCinemaMedia {
        guard let imdb = item.imdbID,
              let url = URL(string: base + "/meta/\(item.kind.rawValue)/\(imdb).json"),
              let data = try? await data(url),
              let wrapper = try? JSONDecoder().decode(XSCinemaCinemetaDetail.self, from: data) else {
            return item
        }
        return media(wrapper.meta, kind: item.kind)
    }

    // This separate collection includes only material with an explicit open
    // redistribution license, and an actual MP4 in its source metadata.
    func openFilms() async -> [XSCinemaMedia] {
        var c = URLComponents(string: "https://archive.org/advancedsearch.php")!
        c.queryItems = [
            URLQueryItem(name: "q", value: "mediatype:movies AND licenseurl:http*"),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "rows", value: "30"),
            URLQueryItem(name: "output", value: "json")
        ]
        guard let url = c.url, let raw = try? await data(url),
              let body = try? JSONSerialization.jsonObject(with: raw) as? [String:Any],
              let response = body["response"] as? [String:Any],
              let docs = response["docs"] as? [[String:Any]] else { return [] }
        var result: [XSCinemaMedia] = []
        for doc in docs.prefix(18) {
            guard let id = doc["identifier"] as? String,
                  id.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil,
                  let metadataURL = URL(string: "https://archive.org/metadata/\(id)"),
                  let d = try? await data(metadataURL),
                  let object = try? JSONSerialization.jsonObject(with: d) as? [String:Any],
                  let meta = object["metadata"] as? [String:Any],
                  let files = object["files"] as? [[String:Any]],
                  let license = meta["licenseurl"] as? String else { continue }
            let valid = license.lowercased().contains("creativecommons.org/licenses/by/") ||
                        license.lowercased().contains("creativecommons.org/licenses/by-sa/") ||
                        license.lowercased().contains("creativecommons.org/publicdomain/zero/")
            guard valid else { continue }
            let mp4 = files.compactMap { f -> (String,Int)? in
                guard let name = f["name"] as? String, name.lowercased().hasSuffix(".mp4"),
                      let size = Int(f["size"] as? String ?? ""), size > 4_000_000,
                      size < 3_000_000_000 else { return nil }
                return (name,size)
            }.sorted { $0.1 < $1.1 }.first?.0
            guard let file = mp4,
                  let encoded = file.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { continue }
            let title = (meta["title"] as? String) ?? id
            let imageName = files.compactMap { $0["name"] as? String }
                .first { $0.lowercased().hasSuffix(".jpg") || $0.lowercased().hasSuffix(".png") }
            let poster = imageName.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) }
                .map { "https://archive.org/download/\(id)/\($0)" }
            result.append(XSCinemaMedia(
                id:"archive:"+id, title:title, kind:.movie,
                poster:poster, backdrop:poster,
                summary: "عمل متاح بموجب ترخيص مفتوح من Internet Archive.",
                year:"", rating:0,
                playableURL:"https://archive.org/download/\(id)/\(encoded)",
                sourceURL:"https://archive.org/details/\(id)",
                licenseURL:license, imdbID:nil, episodes:[]))
        }
        return result
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
    private let movieCache = "XSTV.NativeCinema.movie.v25"
    private let seriesCache = "XSTV.NativeCinema.series.v25"
    private let freeCache = "XSTV.NativeCinema.free.v25"

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? [])
        movies = restoreCache(movieCache)
        series = restoreCache(seriesCache)
        freeMovies = restoreCache(freeCache)
        skips[.movie] = movies.count
        skips[.series] = series.count
    }

    private func restoreCache(_ key: String) -> [XSCinemaMedia] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let values = try? JSONDecoder().decode([XSCinemaMedia].self, from: data) else { return [] }
        return values
    }

    private func persist(_ values: [XSCinemaMedia], key: String) {
        guard let data = try? JSONEncoder().encode(Array(values.prefix(250))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func list(_ kind: XSCinemaMediaKind) -> [XSCinemaMedia] {
        kind == .movie ? movies : series
    }
    func favorite(_ item: XSCinemaMedia) -> Bool { favorites.contains(item.id) }
    func toggle(_ item: XSCinemaMedia) {
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        UserDefaults.standard.set(Array(favorites),forKey:favoriteKey)
    }
    func boot(force: Bool = false) async {
        guard !loading && (!loaded || force) else { return }
        loading = true
        error = nil
        // Fetch both independently: a failed series request cannot blank films.
        async let movieRequest = XSCinemaV25FlexibleCatalog.shared.catalog(.movie)
        async let seriesRequest = XSCinemaV25FlexibleCatalog.shared.catalog(.series)
        do {
            let values = try await movieRequest
            if !values.isEmpty {
                movies = values
                skips[.movie] = values.count
                persist(values, key: movieCache)
            }
        } catch {
            if movies.isEmpty { self.error = "تعذر تحديث الأفلام. حاول السحب للتحديث." }
        }
        do {
            let values = try await seriesRequest
            if !values.isEmpty {
                series = values
                skips[.series] = values.count
                persist(values, key: seriesCache)
            }
        } catch {
            if series.isEmpty { self.error = "تعذر تحديث المسلسلات. حاول السحب للتحديث." }
        }
        loaded = !movies.isEmpty || !series.isEmpty
        loading = false

        // Public-domain metadata can take minutes; it never blocks the
        // primary movie and series catalogs or the app loading spinner.
        if freeMovies.isEmpty || force {
            Task { [weak self] in
                let values = await XSCinemaCatalogAPI.shared.openFilms()
                guard let self, !values.isEmpty else { return }
                self.freeMovies = values
                self.persist(values, key: self.freeCache)
            }
        }
    }
    func more(_ kind: XSCinemaMediaKind) async {
        guard !loadingMore.contains(kind) else { return }
        loadingMore.insert(kind)
        defer { loadingMore.remove(kind) }
        do {
            let incoming = try await XSCinemaV25FlexibleCatalog.shared.catalog(kind,skip:skips[kind] ?? 0)
            let old = Set(list(kind).map(\.id))
            let unique = incoming.filter { !old.contains($0.id) }
            if kind == .movie { movies.append(contentsOf: unique); persist(movies, key: movieCache) }
            else { series.append(contentsOf: unique); persist(series, key: seriesCache) }
            skips[kind,default:0] += incoming.count
        } catch { self.error = "تعذر تحميل المزيد حالياً." }
    }
}
