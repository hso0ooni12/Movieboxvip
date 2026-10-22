import Foundation

/// Tolerant Cinemeta client. The upstream response is not a fixed Codable
/// schema: a single unexpected field must never blank the entire collection.
/// Cinemeta indexes media, while ETWatch remains a separate playback website.
actor XSCinemaV25FlexibleCatalog {
    static let shared = XSCinemaV25FlexibleCatalog()
    private let base = "https://v3-cinemeta.strem.io"

    private func fetch(_ path: String) async throws -> [String: Any] {
        guard let url = URL(string: base + path) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 17)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    private func text(_ value: Any?) -> String? {
        if let str = value as? String { return str }
        if let num = value as? NSNumber { return num.stringValue }
        return nil
    }

    private func number(_ value: Any?) -> Int? {
        if let str = text(value) { return Int(str) }
        return nil
    }

    private func media(_ input: [String: Any], kind: XSCinemaMediaKind) -> XSCinemaMedia? {
        guard let title = text(input["name"] ?? input["title"]),
              let imdb = text(input["id"] ?? input["imdb_id"]),
              !title.isEmpty, !imdb.isEmpty else { return nil }
        let vids = input["videos"] as? [[String: Any]] ?? []
        let episodes = vids.compactMap { video -> XSCinemaEpisode? in
            guard let season = number(video["season"]), season > 0,
                  let episode = number(video["episode"]), episode > 0 else { return nil }
            let id = text(video["id"]) ?? "\(imdb):\(season):\(episode)"
            return XSCinemaEpisode(id: id, season: season, number: episode,
                                   title: text(video["title"] ?? video["name"]) ?? "Episode \(episode)",
                                   thumbnail: text(video["thumbnail"]))
        }
        let tmdb = number(input["moviedb_id"] ?? input["tmdb_id"] ?? input["tmdbId"])
        let rating = Double(text(input["imdbRating"]) ?? "") ?? 0
        return XSCinemaMedia(
            id: "\(kind.rawValue):\(imdb)", title: title, kind: kind,
            poster: text(input["poster"]), backdrop: text(input["background"]),
            summary: text(input["description"]) ?? "",
            year: text(input["releaseInfo"] ?? input["year"]) ?? "",
            rating: rating,
            playableURL: nil, sourceURL: nil, licenseURL: nil,
            imdbID: imdb, episodes: episodes, tmdbID: tmdb)
    }

    func catalog(_ kind: XSCinemaMediaKind, skip: Int = 0) async throws -> [XSCinemaMedia] {
        let suffix = skip > 0 ? "/skip=\(skip)" : ""
        let dictionary = try await fetch("/catalog/\(kind.rawValue)/top\(suffix).json")
        guard let metas = dictionary["metas"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return metas.compactMap { media($0, kind: kind) }
    }

    func search(_ phrase: String, kind: XSCinemaMediaKind) async throws -> [XSCinemaMedia] {
        let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return [] }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
            return []
        }
        let dictionary = try await fetch("/catalog/\(kind.rawValue)/top/search=\(encoded).json")
        guard let metas = dictionary["metas"] as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return metas.compactMap { media($0, kind: kind) }
    }

    func detail(_ item: XSCinemaMedia) async -> XSCinemaMedia {
        guard let imdb = item.imdbID else { return item }
        do {
            let dictionary = try await fetch("/meta/\(item.kind.rawValue)/\(imdb).json")
            guard let meta = dictionary["meta"] as? [String: Any],
                  let resolved = media(meta, kind: item.kind) else { return item }
            // Preserve the known TMDB id if the details endpoint omits it.
            if resolved.tmdbID == nil {
                var fallback = resolved
                fallback.tmdbID = item.tmdbID
                return fallback
            }
            return resolved
        } catch {
            return item
        }
    }
}
