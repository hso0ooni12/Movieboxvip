import Foundation

/// Website navigation routes, never media URLs. Both forms are published by
/// ETWatch's own movie/episode links.
enum XSETWatchRoutes {
    static func watchURL(source: URL, isSeries: Bool, season: Int? = nil,
                         episode: Int? = nil) -> URL? {
        guard source.scheme == "https",
              ["etwatch.net", "www.etwatch.net"].contains(source.host?.lowercased() ?? "") else { return nil }
        let parts = source.path.split(separator: "/").map(String.init)
        let rawID: String
        if parts.count >= 3 && parts[0] == "watch" {
            rawID = parts[2]
        } else if parts.count >= 2 && ["movie", "series"].contains(parts[0]) {
            rawID = String(parts[1].prefix(while: { $0.isNumber }))
        } else { return nil }
        guard !rawID.isEmpty, rawID.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let path = isSeries
            ? "/watch/tv/\(rawID)/\(max(1, season ?? 1))/\(max(1, episode ?? 1))"
            : "/watch/movie/\(rawID)"
        return URL(string: "https://www.etwatch.net" + path)
    }
}
