import Foundation

/// A fresh, public watch-page URL. Playback is owned by the website inside system Safari.
struct SitePlaybackRequest: Identifiable {
    let id = UUID()
    let title: MediaTitle
    let season: Int?
    let episode: Int?

    init(title: MediaTitle, season: Int? = nil, episode: Int? = nil) {
        self.title = title
        self.season = title.kind == .tv ? max(0, season ?? 1) : nil
        self.episode = title.kind == .tv ? max(1, episode ?? 1) : nil
    }

    /// Keep "Play now" in the season the viewer is looking at. An older native
    /// progress entry must not silently jump to a different season; the website
    /// itself remains responsible for resuming its playback session.
    static func selected(
        title: MediaTitle,
        visibleSeason: Int,
        visibleEpisodes: [MediaEpisode],
        tappedEpisode: MediaEpisode?,
        savedProgress: WatchProgress?
    ) -> SitePlaybackRequest {
        guard title.kind == .tv else { return SitePlaybackRequest(title: title) }
        let resumeEpisode = savedProgress?.season == visibleSeason ? savedProgress?.episode : nil
        let episode = tappedEpisode?.episode_number ?? resumeEpisode ?? visibleEpisodes.first?.episode_number ?? 1
        return SitePlaybackRequest(title: title, season: visibleSeason, episode: episode)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = "https"; components.host = "watched.cx"
        components.path = "/\(title.kind.rawValue)/\(title.tmdbID)"
        var query: [URLQueryItem] = []
        if let season, let episode {
            query += [URLQueryItem(name: "s", value: String(season)), URLQueryItem(name: "e", value: String(episode))]
        }
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }
}
