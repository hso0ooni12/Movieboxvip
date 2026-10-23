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
        guard !trimmed.isEmpty, let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/&?#%"))),
              let url = URL(string: base + "/catalog/\(kind.rawValue)/top/search=\(encoded).json") else { return [] }
        let bytes = try await data(url)
        let value = try JSONDecoder().decode(XSCinemaCinemetaCatalog.self, from: bytes)
        return value.metas.map { media($0,kind:kind) }
    }

    func detail(_ item: XSCinemaMedia) async -> XSCinemaMedia {
        var resolved = item
        if resolved.imdbID == nil,
           let matches = try? await search(item.title, kind: item.kind),
           let raw = item.sourceURL, let source = URL(string: raw) {
            let identity = XSETWatchRoutes.watchURL(source: source, isSeries: false)
            if let match = matches.first(where: { candidate in
                guard let raw = candidate.sourceURL, let url = URL(string: raw) else { return false }
                return XSETWatchRoutes.watchURL(source: url, isSeries: false) == identity
            }) { resolved.imdbID = match.imdbID }
        }
        guard let imdb = resolved.imdbID,
              let url = URL(string: base + "/meta/\(item.kind.rawValue)/\(imdb).json"),
              let data = try? await data(url),
              let wrapper = try? JSONDecoder().decode(XSCinemaCinemetaDetail.self, from: data) else {
            return item
        }
        let full = media(wrapper.meta, kind: item.kind)
        // Keep the source identity stable for favourites, shelves and resume.
        resolved.poster = full.poster ?? item.poster
        resolved.backdrop = full.backdrop ?? item.backdrop
        resolved.summary = full.summary
        resolved.rating = full.rating > 0 ? full.rating : item.rating
        resolved.year = full.year.isEmpty ? item.year : full.year
        resolved.episodes = full.episodes
        resolved.sourceURL = item.sourceURL ?? full.sourceURL
        return resolved
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
    @Published private(set) var shelves: [XSCinemaShelf] = []
    @Published private(set) var recents: [XSCinemaWatchRecord] = []
    @Published private(set) var moreErrors: Set<XSCinemaMediaKind> = []
    private var exhausted: Set<XSCinemaMediaKind> = []
    private var loaded = false
    private var openTask: Task<Void, Never>?
    private let recentKey = "XSTV.NativeCinema.Recent.V27"
    private var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("xstv-catalog-v27.json")
    }
    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? [])
        // Compile-time catalog from verified public metadata. Populate Home
        // instantly, independently of the network or licensed video sources.
        movies = XSCinemaNativeSeed.movies
        series = XSCinemaNativeSeed.series
        if let snapshot = XSETWatchCatalogSnapshot.bundled {
            movies = snapshot.items.filter { $0.kind == .movie }
            series = snapshot.items.filter { $0.kind == .series }
            shelves = snapshot.shelves
        }
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let saved = try? JSONDecoder().decode([XSCinemaWatchRecord].self, from: data) {
            recents = saved
        }
        if let url = cacheURL, let data = try? Data(contentsOf: url),
           let cached = try? JSONDecoder().decode([String:[XSCinemaMedia]].self, from: data) {
            if let value = cached["movies"], !value.isEmpty { movies = value }
            if let value = cached["series"], !value.isEmpty { series = value }
        }
    }
    func saveProgress(_ media: XSCinemaMedia, season: Int?, episode: Int?,
                      position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, position > 5 else { return }
        let record = XSCinemaWatchRecord(media: media, season: season, episode: episode,
                                       position: position, duration: duration, updated: Date())
        recents.removeAll { $0.id == record.id }
        if duration <= 0 || position < duration - 25 { recents.insert(record, at: 0) }
        recents = Array(recents.prefix(30))
        if let data = try? JSONEncoder().encode(recents) {
            UserDefaults.standard.set(data, forKey: recentKey)
        }
    }
    func resume(_ media: XSCinemaMedia, season: Int?, episode: Int?) -> Double {
        recents.first { $0.media.id == media.id && $0.season == season && $0.episode == episode }?.position ?? 0
    }
    func shelfItems(_ shelf: XSCinemaShelf) -> [XSCinemaMedia] {
        var lookup: [String:XSCinemaMedia] = [:]
        for media in movies + series { lookup[media.id] = media }
        return shelf.itemIDs.compactMap { lookup[$0] }
    }
    private func combined(_ current: [XSCinemaMedia], _ incoming: [XSCinemaMedia]) -> [XSCinemaMedia] {
        func key(_ item: XSCinemaMedia) -> String {
            if let raw = item.sourceURL, let source = URL(string: raw),
               let url = XSETWatchRoutes.watchURL(source: source, isSeries: item.kind == .series) {
                return url.absoluteString
            }
            return item.id
        }
        var seen = Set<String>()
        return (current + incoming).filter { seen.insert(key($0)).inserted }
    }
    func hasMore(_ kind: XSCinemaMediaKind) -> Bool { !exhausted.contains(kind) }
    private func persistCatalog() {
        guard let url = cacheURL,
              let data = try? JSONEncoder().encode(["movies":movies,"series":series]) else { return }
        try? data.write(to: url, options: .atomic)
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
        guard !loading && (force || !loaded) else { return }
        loading = true
        error = nil
        defer { loading = false }
        async let a = XSCinemaCatalogAPI.shared.catalog(.movie)
        async let b = XSCinemaCatalogAPI.shared.catalog(.series)
        var succeeded = false
        do {
            let value = try await a
            if !value.isEmpty { movies = combined(movies, value); succeeded = true }
            skips[.movie] = value.count
        } catch { self.error = "تعذر تحديث الأفلام. المكتبة المحفوظة متاحة." }
        do {
            let value = try await b
            if !value.isEmpty { series = combined(series, value); succeeded = true }
            skips[.series] = value.count
        } catch { self.error = "تعذر تحديث المسلسلات. المكتبة المحفوظة متاحة." }
        loaded = succeeded
        exhausted = []; moreErrors = []
        persistCatalog()
        // Optional open films never hold up the primary movie/series library.
        if openTask == nil && freeMovies.isEmpty {
            openTask = Task { [weak self] in
                let films = await XSCinemaCatalogAPI.shared.openFilms()
                guard let self, !Task.isCancelled else { return }
                self.freeMovies = films
                self.openTask = nil
            }
        }
    }
    func more(_ kind: XSCinemaMediaKind) async {
        guard !loadingMore.contains(kind), !exhausted.contains(kind) else { return }
        moreErrors.remove(kind)
        loadingMore.insert(kind)
        defer { loadingMore.remove(kind) }
        do {
            let incoming = try await XSCinemaCatalogAPI.shared.catalog(kind,skip:skips[kind] ?? 0)
            let previousCount = list(kind).count
            if kind == .movie { movies = combined(movies, incoming) }
            else { series = combined(series, incoming) }
            skips[kind,default:0] += incoming.count
            if incoming.isEmpty { exhausted.insert(kind) }
            _ = previousCount
            persistCatalog()
        } catch { moreErrors.insert(kind) }
    }
}
