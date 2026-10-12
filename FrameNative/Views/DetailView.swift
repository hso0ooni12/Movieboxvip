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
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 22) {
                        actionRow
                        playbackFeatures

                        if let tagline = details?.tagline, !tagline.isEmpty {
                            Text(tagline)
                                .font(.headline)
                                .italic()
                                .foregroundStyle(.white.opacity(0.78))
                        }

                        Text(currentItem.overview.isEmpty ? "No overview available." : currentItem.overview)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.83))
                            .lineSpacing(5)

                        if item.kind != .movie { episodeSection }

                        if let error {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.orange)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 38)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.55), for: .navigationBar)
        .task { await load() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.75)) { heroAppeared = true }
        }
    }

    private var currentItem: MediaItem { details?.item ?? item }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePoster(item: currentItem, backdrop: true, cornerRadius: 0)
                .frame(height: 410)
                .scaleEffect(heroAppeared ? 1.0 : 1.035)
                .opacity(heroAppeared ? 1 : 0.72)

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.12), .black.opacity(0.98)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 7) {
                    GlassBadge(text: currentItem.year)
                    if currentItem.voteAverage > 0 { GlassBadge(text: currentItem.ratingText, systemImage: "star.fill") }
                    if let runtime = details?.runtimeText { GlassBadge(text: runtime) }
                }

                Text(currentItem.title)
                    .font(.system(size: 37, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                if let genres = details?.genres, !genres.isEmpty {
                    Text(genres.prefix(3).joined(separator: "  •  "))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
            .offset(y: heroAppeared ? 0 : 16)
            .opacity(heroAppeared ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.7), value: heroAppeared)
    }

    private var actionRow: some View {
        HStack(spacing: 11) {
            if item.kind == .movie {
                NavigationLink {
                    FrameXTVPlayerScreen(item: currentItem, playback: moviePlayback)
                } label: {
                    Label(resumeText, systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }

            Button { library.toggleFavorite(currentItem) } label: {
                Label(
                    library.isFavorite(currentItem) ? "Saved" : "My List",
                    systemImage: library.isFavorite(currentItem) ? "checkmark" : "plus"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private var playbackFeatures: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                FeaturePill(title: "Named Subtitles", systemImage: "captions.bubble.fill")
                FeaturePill(title: "Auto Next", systemImage: "forward.end.fill")
                FeaturePill(title: "Multiple Servers", systemImage: "server.rack")
                FeaturePill(title: "Resume", systemImage: "clock.arrow.circlepath")
                FeaturePill(title: "Landscape", systemImage: "rectangle.landscape")
            }
        }
        .scrollIndicators(.hidden)
    }

    private var saved: WatchProgress? { library.progress(for: item) }
    private var resumeText: String { (saved?.currentTime ?? 0) > 5 ? "Resume" : "Play" }
    private var moviePlayback: FrameXTVPlayback {
        FrameXTVPlayback(tmdbID: item.tmdbID, startAt: saved?.currentTime ?? 0)
    }

    @ViewBuilder
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Episodes").font(.title2.bold())
                    if let selectedSeason { Text("Season \(selectedSeason)").font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if !seasons.isEmpty {
                    Picker("Season", selection: Binding(
                        get: { selectedSeason ?? seasons.first?.seasonNumber ?? 1 },
                        set: { value in
                            selectedSeason = value
                            Task { await loadEpisodes(season: value) }
                        }
                    )) {
                        ForEach(seasons) { season in Text(season.name).tag(season.seasonNumber) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.075), in: Capsule())
                }
            }

            if episodeLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Loading episodes…").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 18)
            } else {
                LazyVStack(spacing: 11) {
                    ForEach(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                        NavigationLink {
                            FrameXTVPlayerScreen(
                                item: currentItem,
                                playback: episodePlayback(episode),
                                nextPlayback: nextPlayback(after: index),
                                nextLabel: nextLabel(after: index)
                            )
                        } label: {
                            EpisodeRow(episode: episode, current: isCurrent(episode))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func episodePlayback(_ episode: Episode) -> FrameXTVPlayback {
        let season = selectedSeason ?? 1
        let resume = (saved?.season == season && saved?.episode == episode.episodeNumber) ? (saved?.currentTime ?? 0) : 0
        return FrameXTVPlayback(tmdbID: item.tmdbID, season: season, episode: episode.episodeNumber, startAt: resume)
    }

    private func nextPlayback(after index: Int) -> FrameXTVPlayback? {
        let season = selectedSeason ?? 1
        if episodes.indices.contains(index + 1) {
            return FrameXTVPlayback(tmdbID: item.tmdbID, season: season, episode: episodes[index + 1].episodeNumber)
        }
        if let nextSeason = seasons.map(\.seasonNumber).filter({ $0 > season }).sorted().first {
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
        if let nextSeason = seasons.map(\.seasonNumber).filter({ $0 > season }).sorted().first {
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
                let preferred = saved?.season.flatMap { season in seasons.contains(where: { $0.seasonNumber == season }) ? season : nil }
                let first = preferred ?? seasons.first?.seasonNumber
                selectedSeason = first
                if let first { await loadEpisodes(season: first) }
            }
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    @MainActor
    private func loadEpisodes(season: Int) async {
        episodeLoading = true
        do { episodes = try await app.episodes(tmdbID: item.tmdbID, season: season) }
        catch { self.error = error.localizedDescription }
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
            .background(.white.opacity(0.065), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.07)))
            .foregroundStyle(.white.opacity(0.86))
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let current: Bool
    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .bottomLeading) {
                if let url = episode.stillURL() {
                    AsyncImage(url: url) { phase in
                        switch phase { case .success(let image): image.resizable().scaledToFill(); default: Color.white.opacity(0.055) }
                    }
                } else { Color.white.opacity(0.055) }
                LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                Text("E\(episode.episodeNumber)")
                    .font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.7), in: Capsule()).padding(8)
                Image(systemName: "play.fill")
                    .font(.caption.bold()).frame(width: 36, height: 36)
                    .background(.white, in: Circle()).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(width: 132, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(episode.name).font(.subheadline.bold()).lineLimit(1)
                    if current { Image(systemName: "clock.fill").foregroundStyle(.cyan).font(.caption) }
                }
                if !episode.overview.isEmpty {
                    Text(episode.overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else if let runtime = episode.runtime {
                    Text("\(runtime) min").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.white.opacity(current ? 0.085 : 0.045), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.06)))
        .foregroundStyle(.white)
    }
}
