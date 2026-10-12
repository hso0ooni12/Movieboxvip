import SwiftUI

struct DetailView: View {
    let item: MediaItem
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @State private var details: MediaDetails?
    @State private var seasons: [SeasonInfo] = []
    @State private var selectedSeason: Int?
    @State private var episodes: [Episode] = []
    @State private var loading = true
    @State private var episodeLoading = false
    @State private var error: String?
    @State private var heroAppeared = false

    var body: some View {
        ZStack {
            XSBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero

                    VStack(alignment: .leading, spacing: 24) {
                        actionRow

                        if let saved, saved.currentTime > 5 {
                            resumeCard(saved)
                        }

                        metadataStrip

                        if let tagline = details?.tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.title3.weight(.semibold))
                                .italic()
                                .foregroundStyle(.white.opacity(0.86))
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("About")
                                .font(.title3.bold())
                            Text(currentItem.overview.isEmpty ? "No overview available." : currentItem.overview)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.78))
                                .lineSpacing(5)
                        }

                        if item.kind != .movie {
                            episodeSection
                        }

                        let related = app.related(to: currentItem)
                        if !related.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("More Like This")
                                    .font(.title2.bold())
                                Text("More titles from the XS TV catalog you may enjoy")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ScrollView(.horizontal) {
                                    LazyHStack(spacing: 14) {
                                        ForEach(related) { relatedItem in
                                            NavigationLink(value: relatedItem) {
                                                MediaCard(item: relatedItem, width: 148)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.bottom, 4)
                                }
                                .scrollIndicators(.hidden)
                            }
                        }

                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.45), for: .navigationBar)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        .task { await load() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.78)) {
                heroAppeared = true
            }
        }
    }

    private var currentItem: MediaItem {
        details?.item ?? item
    }

    private var saved: WatchProgress? {
        library.progress(for: item)
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePoster(item: currentItem, backdrop: true, cornerRadius: 0)
                .frame(height: 460)
                .scaleEffect(heroAppeared ? 1.0 : 1.04)
                .opacity(heroAppeared ? 1 : 0.72)

            LinearGradient(
                colors: [.black.opacity(0.02), .black.opacity(0.16), .black.opacity(0.99)],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [.purple.opacity(0.22), .pink.opacity(0.08), .orange.opacity(0.03), .clear],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
            .blendMode(.screen)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    GlassBadge(text: currentItem.kind == .tv ? "SERIES" : currentItem.kind.title.uppercased())
                    GlassBadge(text: currentItem.year)
                    if currentItem.voteAverage > 0 {
                        GlassBadge(text: currentItem.ratingText, systemImage: "star.fill")
                    }
                }

                Text(currentItem.title)
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                if let genres = details?.genres, !genres.isEmpty {
                    Text(genres.prefix(4).joined(separator: "  •  "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                } else if !currentItem.subtitle.isEmpty {
                    Text(currentItem.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .offset(y: heroAppeared ? 0 : 18)
            .opacity(heroAppeared ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.72), value: heroAppeared)
    }

    private var actionRow: some View {
        HStack(spacing: 11) {
            if let playback = primaryPlayback {
                NavigationLink {
                    FrameXTVPlayerScreen(
                        item: currentItem,
                        playback: playback,
                        nextPlayback: primaryNextPlayback,
                        nextLabel: primaryNextLabel
                    )
                } label: {
                    Label(primaryPlayLabel, systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }

            Button {
                library.toggleFavorite(currentItem)
            } label: {
                Image(systemName: library.isFavorite(currentItem) ? "checkmark" : "plus")
                    .font(.headline.bold())
                    .frame(width: 52, height: 52)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .accessibilityLabel(library.isFavorite(currentItem) ? "Remove from My List" : "Add to My List")
        }
    }

    private func resumeCard(_ progress: WatchProgress) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Continue Watching", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline.bold())
                Spacer()
                Text(progress.episodeLabel ?? "Resume")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.10))
                    LinearGradient(colors: [.purple, .pink, .orange], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * progress.fraction)
                        .clipShape(Capsule())
                }
            }
            .frame(height: 5)

            HStack {
                Text("\(Int(progress.fraction * 100))% watched")
                Spacer()
                if progress.duration > progress.currentTime {
                    let minutes = Int((progress.duration - progress.currentTime) / 60)
                    if minutes > 0 { Text("\(minutes)m remaining") }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.07)))
    }

    private var metadataStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                if let runtime = details?.runtimeText {
                    FeaturePill(title: runtime, systemImage: "clock")
                }
                if let status = details?.status, !status.isEmpty {
                    FeaturePill(title: status, systemImage: "checkmark.seal")
                }
                if let seasons = details?.numberOfSeasons, seasons > 0 {
                    FeaturePill(title: "\(seasons) Seasons", systemImage: "square.stack.3d.up")
                }
                FeaturePill(title: "All Servers", systemImage: "server.rack")
                FeaturePill(title: "Subtitles", systemImage: "captions.bubble.fill")
                FeaturePill(title: "Auto Resume", systemImage: "play.circle")
            }
        }
        .scrollIndicators(.hidden)
    }

    private var moviePlayback: FrameXTVPlayback {
        FrameXTVPlayback(tmdbID: item.tmdbID, startAt: saved?.currentTime ?? 0)
    }

    private var primaryPlayback: FrameXTVPlayback? {
        if item.kind == .movie {
            return moviePlayback
        }

        if let season = saved?.season,
           let episode = saved?.episode,
           seasons.contains(where: { $0.seasonNumber == season }) {
            return FrameXTVPlayback(
                tmdbID: item.tmdbID,
                season: season,
                episode: episode,
                startAt: saved?.currentTime ?? 0
            )
        }

        guard let firstEpisode = episodes.first else { return nil }
        return FrameXTVPlayback(
            tmdbID: item.tmdbID,
            season: selectedSeason ?? 1,
            episode: firstEpisode.episodeNumber
        )
    }

    private var primaryPlayLabel: String {
        if item.kind == .movie {
            return (saved?.currentTime ?? 0) > 5 ? "Resume" : "Play"
        }

        if let season = saved?.season,
           let episode = saved?.episode,
           (saved?.currentTime ?? 0) > 5 {
            return "Resume S\(season) E\(episode)"
        }

        if let first = episodes.first {
            return "Play S\(selectedSeason ?? 1) E\(first.episodeNumber)"
        }

        return "Play"
    }

    private var primaryNextPlayback: FrameXTVPlayback? {
        guard item.kind != .movie,
              let playback = primaryPlayback,
              let season = playback.season,
              let episodeNumber = playback.episode,
              selectedSeason == season,
              let index = episodes.firstIndex(where: { $0.episodeNumber == episodeNumber }) else {
            return nil
        }
        return nextPlayback(after: index)
    }

    private var primaryNextLabel: String? {
        guard item.kind != .movie,
              let playback = primaryPlayback,
              let season = playback.season,
              let episodeNumber = playback.episode,
              selectedSeason == season,
              let index = episodes.firstIndex(where: { $0.episodeNumber == episodeNumber }) else {
            return nil
        }
        return nextLabel(after: index)
    }

    @ViewBuilder
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Episodes")
                        .font(.title2.bold())
                    if let selectedSeason {
                        Text("Season \(selectedSeason) · \(episodes.count) episodes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !seasons.isEmpty {
                    Picker(
                        "Season",
                        selection: Binding(
                            get: { selectedSeason ?? seasons.first?.seasonNumber ?? 1 },
                            set: { value in
                                selectedSeason = value
                                Task { await loadEpisodes(season: value) }
                            }
                        )
                    ) {
                        ForEach(seasons) { season in
                            Text(season.name).tag(season.seasonNumber)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(.ultraThinMaterial, in: Capsule())
                }
            }

            if episodeLoading {
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.05))
                            .frame(height: 96)
                    }
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        NavigationLink {
                            FrameXTVPlayerScreen(
                                item: currentItem,
                                playback: episodePlayback(episode),
                                nextPlayback: nextPlayback(after: index),
                                nextLabel: nextLabel(after: index)
                            )
                        } label: {
                            EpisodeRow(
                                episode: episode,
                                current: isCurrent(episode),
                                progress: episodeProgress(episode)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func episodeProgress(_ episode: Episode) -> Double? {
        guard let saved,
              saved.season == selectedSeason,
              saved.episode == episode.episodeNumber,
              saved.duration > 0 else { return nil }
        return saved.fraction
    }

    private func episodePlayback(_ episode: Episode) -> FrameXTVPlayback {
        let season = selectedSeason ?? 1
        let resume = (saved?.season == season && saved?.episode == episode.episodeNumber)
            ? (saved?.currentTime ?? 0)
            : 0

        return FrameXTVPlayback(
            tmdbID: item.tmdbID,
            season: season,
            episode: episode.episodeNumber,
            startAt: resume
        )
    }

    private func nextPlayback(after index: Int) -> FrameXTVPlayback? {
        let season = selectedSeason ?? 1

        if episodes.indices.contains(index + 1) {
            return FrameXTVPlayback(
                tmdbID: item.tmdbID,
                season: season,
                episode: episodes[index + 1].episodeNumber
            )
        }

        if let nextSeason = seasons
            .map(\.seasonNumber)
            .filter({ $0 > season })
            .sorted()
            .first {
            return FrameXTVPlayback(tmdbID: item.tmdbID, season: nextSeason, episode: 1)
        }

        return nil
    }

    private func nextLabel(after index: Int) -> String? {
        let season = selectedSeason ?? 1

        if episodes.indices.contains(index + 1) {
            let next = episodes[index + 1]
            return "S\(season) · E\(next.episodeNumber)  \(next.name)"
        }

        if let nextSeason = seasons
            .map(\.seasonNumber)
            .filter({ $0 > season })
            .sorted()
            .first {
            return "Season \(nextSeason) · Episode 1"
        }

        return nil
    }

    private func isCurrent(_ episode: Episode) -> Bool {
        saved?.season == selectedSeason && saved?.episode == episode.episodeNumber
    }

    @MainActor
    private func load() async {
        loading = true
        error = nil

        do {
            async let detailRequest = app.details(for: item)
            async let seasonRequest = app.seasons(for: item)
            details = try await detailRequest

            if item.kind != .movie {
                seasons = try await seasonRequest
                let preferred = saved?.season.flatMap { season in
                    seasons.contains(where: { $0.seasonNumber == season }) ? season : nil
                }
                let first = preferred ?? seasons.first?.seasonNumber
                selectedSeason = first
                if let first { await loadEpisodes(season: first) }
            }
        } catch {
            self.error = error.localizedDescription
        }

        loading = false
    }

    @MainActor
    private func loadEpisodes(season: Int) async {
        episodeLoading = true
        do {
            episodes = try await app.episodes(tmdbID: item.tmdbID, season: season)
        } catch {
            self.error = error.localizedDescription
        }
        episodeLoading = false
    }
}

private struct FeaturePill: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08)))
            .foregroundStyle(.white.opacity(0.86))
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let current: Bool
    var progress: Double? = nil

    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .bottomLeading) {
                if let url = episode.stillURL() {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.white.opacity(0.055)
                        }
                    }
                } else {
                    Color.white.opacity(0.055)
                }

                LinearGradient(colors: [.clear, .black.opacity(0.74)], startPoint: .center, endPoint: .bottom)

                HStack {
                    Text("E\(episode.episodeNumber)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.7), in: Capsule())
                    Spacer()
                    Image(systemName: "play.fill")
                        .font(.caption.bold())
                        .frame(width: 32, height: 32)
                        .background(.white, in: Circle())
                        .foregroundStyle(.black)
                }
                .padding(8)
            }
            .frame(width: 138, height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(episode.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if current {
                        Image(systemName: "clock.fill")
                            .foregroundStyle(.pink)
                            .font(.caption)
                    }
                }

                if !episode.overview.isEmpty {
                    Text(episode.overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let runtime = episode.runtime {
                    Text("\(runtime) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.09))
                            LinearGradient(colors: [.purple, .pink, .orange], startPoint: .leading, endPoint: .trailing)
                                .frame(width: proxy.size.width * progress)
                                .clipShape(Capsule())
                        }
                    }
                    .frame(height: 3)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(.white.opacity(current ? 0.075 : 0.035), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(current ? 0.12 : 0.055)))
        .foregroundStyle(.white)
    }
}
