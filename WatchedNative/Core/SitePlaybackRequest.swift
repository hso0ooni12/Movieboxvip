import Foundation

/// A fresh, public watch-page URL. Playback is owned by the website inside one modal.
struct SitePlaybackRequest: Identifiable {
    let id = UUID()
    let title: MediaTitle
    let season: Int?
    let episode: Int?
    let resumeAt: Double

    init(title: MediaTitle, season: Int? = nil, episode: Int? = nil, resumeAt: Double = 0) {
        self.title = title
        self.season = title.kind == .tv ? max(0, season ?? 1) : nil
        self.episode = title.kind == .tv ? max(1, episode ?? 1) : nil
        self.resumeAt = resumeAt.isFinite ? max(0, resumeAt) : 0
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "https"; components.host = "watched.cx"
        components.path = "/\(title.kind.rawValue)/\(title.tmdbID)"
        var query: [URLQueryItem] = []
        if let season, let episode {
            query += [URLQueryItem(name: "s", value: String(season)), URLQueryItem(name: "e", value: String(episode))]
        }
        if resumeAt >= 1 { query.append(URLQueryItem(name: "t", value: String(Int(min(resumeAt, 604_800))))) }
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }
}

struct SitePlayerRoute: Equatable {
    let kind: MediaKind
    let tmdbID: Int
    let season: Int?
    let episode: Int?

    init?(url: URL) {
        guard SitePlayerNavigation.isSource(url) else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2, let kind = MediaKind(rawValue: String(parts[0])),
              let id = Int(parts[1]), id > 0 else { return nil }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        self.kind = kind; tmdbID = id
        season = kind == .tv ? max(0, Int(query.first(where: { $0.name == "s" })?.value ?? "1") ?? 1) : nil
        episode = kind == .tv ? max(1, Int(query.first(where: { $0.name == "e" })?.value ?? "1") ?? 1) : nil
    }
}

enum SitePlayerNavigation {
    enum Action: Equatable { case play, returnToApp, block }

    static func isSource(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "watched.cx"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    static func action(for url: URL) -> Action {
        guard isSource(url) else { return .block }
        return SitePlayerRoute(url: url) != nil ? .play : .returnToApp
    }
}
