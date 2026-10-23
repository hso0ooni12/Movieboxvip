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
    let moviedb_id: XSCinemaFlexibleIdentifier?
    let videos: [XSCinemaCinemetaVideo]?
}
private struct XSCinemaCinemetaVideo: Decodable {
    let id: String?
    let season: Int?
    let episode: Int?
    let title: String?
    let thumbnail: String?
}

private struct XSCinemaFlexibleIdentifier: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let v = try decoder.singleValueContainer()
        if let s = try? v.decode(String.self) { value = s }
        else if let n = try? v.decode(Int.self) { value = String(n) }
        else { value = "" }
    }
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
            return XSCinemaEpisode(id: v.id ?? "\(season):\(number)", season: season, number: number,
                                   title: v.title ?? "Episode \(number)", thumbnail: v.thumbnail)
        }
        // ETWatch's publicly exposed site navigation uses TMDB identifiers
        // and a title/year slug. This is a browser navigation destination,
        // never an extracted/guessed media stream URL.
        let slug = meta.name.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-",
                                  options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let year = (meta.releaseInfo ?? "").range(
            of: #"(?:19|20)\d{2}"#, options: .regularExpression)
            .map { String((meta.releaseInfo ?? "")[$0]) }
        let kindPath = kind == .movie ? "movie" : "series"
        let route = meta.moviedb_id?.value.isEmpty == false
            ? "https://www.etwatch.net/\(kindPath)/\(meta.moviedb_id!.value)-\(slug)\(year.map { "-" + $0 } ?? "")"
            : nil
        return XSCinemaMedia(id: kind.rawValue + ":" + meta.id,
                             title: meta.name, kind: kind,
                             poster: meta.poster, backdrop: meta.background,
                             summary: meta.description ?? "",
                             year: meta.releaseInfo ?? "",
                             rating: Double(meta.imdbRating ?? "") ?? 0,
                             playableURL: nil, sourceURL: route, licenseURL: nil,
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
    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? [])
        // Compile-time catalog from verified public metadata. Populate Home
        // instantly, independently of the network or licensed video sources.
        movies = XSCinemaNativeSeed.movies
        series = XSCinemaNativeSeed.series
    }

    func list(_ kind: XSCinemaMediaKind) -> [XSCinemaMedia] {
        kind == .movie ? movies : series
    }
    func favorite(_ item: XSCinemaMedia) -> Bool { favorites.contains(item.id) }
    func toggle(_ item: XSCinemaMedia) {
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        UserDefaults.standard.set(Array(favorites),forKey:favoriteKey)
    }
    func boot() async {
        guard !loaded && !loading else { return }
        loading = true
        defer { loading = false }
        async let a = XSCinemaCatalogAPI.shared.catalog(.movie)
        async let b = XSCinemaCatalogAPI.shared.catalog(.series)
        async let c = XSCinemaCatalogAPI.shared.openFilms()
        do {
            let m = try await a
            if !m.isEmpty { movies = m }
            skips[.movie] = m.count
        } catch {
            self.error = "تعذر تحميل الأفلام الآن."
        }
        do {
            let s = try await b
            if !s.isEmpty { series = s }
            skips[.series] = s.count
        } catch {
            self.error = "تعذر تحميل المسلسلات الآن."
        }
        freeMovies = await c
        loaded = !movies.isEmpty || !series.isEmpty || !freeMovies.isEmpty
    }
    func refresh() async {
        guard !loading else { return }
        loaded = false
        await boot()
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
