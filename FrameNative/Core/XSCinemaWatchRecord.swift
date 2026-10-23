import Foundation

struct XSCinemaWatchRecord: Codable, Identifiable {
    let media: XSCinemaMedia
    let season: Int?
    let episode: Int?
    var position: Double
    var duration: Double
    var updated: Date
    var id: String { media.id + ":\(season ?? 0):\(episode ?? 0)" }
    var progress: Double { duration > 0 ? min(1, max(0, position / duration)) : 0 }
    var title: String {
        guard let season, let episode else { return media.title }
        return "\(media.title)  S\(season) E\(episode)"
    }
    var watchURL: URL? {
        guard let raw = media.sourceURL, let source = URL(string: raw) else { return nil }
        return XSETWatchRoutes.watchURL(source: source, isSeries: media.kind == .series,
                                       season: season, episode: episode)
    }
}
