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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZStack(alignment: .bottomLeading) {
                    RemotePoster(item: details?.item ?? item, backdrop: true, cornerRadius: 0)
                        .frame(height: 330)
                    LinearGradient(colors: [.clear, .black], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 8) {
                        Text((details?.item ?? item).title)
                            .font(.system(size: 34, weight: .black, design: .rounded))
                        Text(metaLine)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                }

                HStack(spacing: 12) {
                    if item.kind == .movie {
                        NavigationLink {
                            FrameXTVPlayerScreen(item: details?.item ?? item, playback: moviePlayback)
                        } label: {
                            Label(resumeText, systemImage: "play.fill")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                    }

                    Button { library.toggleFavorite(details?.item ?? item) } label: {
                        Label(library.isFavorite(details?.item ?? item) ? "Saved" : "My List",
                              systemImage: library.isFavorite(details?.item ?? item) ? "checkmark" : "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)

                if let tagline = details?.tagline, !tagline.isEmpty {
                    Text(tagline).font(.headline).italic().foregroundStyle(.secondary).padding(.horizontal, 16)
                }

                Text((details?.item ?? item).overview.isEmpty ? "No overview available." : (details?.item ?? item).overview)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.86))
                    .lineSpacing(5)
                    .padding(.horizontal, 16)

                if item.kind != .movie {
                    episodeSection
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                        .padding(16)
                }
            }
            .padding(.bottom, 34)
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var currentItem: MediaItem { details?.item ?? item }

    private var metaLine: String {
        var values = [currentItem.year, "★ \(currentItem.ratingText)"]
        if let runtime = details?.runtimeText { values.append(runtime) }
        let genres = details?.genres.isEmpty == false ? details!.genres.prefix(3).joined(separator: " • ") : currentItem.subtitle
        if !genres.isEmpty { values.append(genres) }
        return values.joined(separator: "  •  ")
    }

    private var saved: WatchProgress? { library.progress(for: item) }
    private var resumeText: String { (saved?.currentTime ?? 0) > 5 ? "Resume" : "Play" }
    private var moviePlayback: FrameXTVPlayback {
        FrameXTVPlayback(tmdbID: item.tmdbID, startAt: saved?.currentTime ?? 0)
    }

    @ViewBuilder
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Episodes").font(.title2.bold())
                Spacer()
                if !seasons.isEmpty {
                    Picker("Season", selection: Binding(get: { selectedSeason ?? seasons.first?.seasonNumber ?? 1 }, set: { value in
                        selectedSeason = value
                        Task { await loadEpisodes(season: value) }
                    })) {
                        ForEach(seasons) { season in
                            Text(season.name).tag(season.seasonNumber)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.horizontal, 16)

            if episodeLoading {
                ProgressView("Loading episodes…").padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(episodes) { episode in
                        NavigationLink {
                            FrameXTVPlayerScreen(item: currentItem, playback: episodePlayback(episode))
                        } label: {
                            EpisodeRow(episode: episode, current: isCurrent(episode))
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(.white.opacity(0.08)).padding(.leading, 132)
                    }
                }
            }
        }
    }

    private func episodePlayback(_ episode: Episode) -> FrameXTVPlayback {
        let season = selectedSeason ?? 1
        let resume = (saved?.season == season && saved?.episode == episode.episodeNumber) ? (saved?.currentTime ?? 0) : 0
        return FrameXTVPlayback(tmdbID: item.tmdbID, season: season, episode: episode.episodeNumber, startAt: resume)
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
                let preferred = saved?.season.flatMap { s in seasons.contains(where: { $0.seasonNumber == s }) ? s : nil }
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
        do { episodes = try await app.episodes(tmdbID: item.tmdbID, season: season) }
        catch { self.error = error.localizedDescription }
        episodeLoading = false
    }
}

struct EpisodeRow: View {
    let episode: Episode
    let current: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let url = episode.stillURL() {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.white.opacity(0.06) }
                } else { Color.white.opacity(0.06) }
                Image(systemName: "play.fill")
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.62), in: Circle())
            }
            .frame(width: 116, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("E\(episode.episodeNumber)  \(episode.name)").font(.subheadline.bold()).lineLimit(1)
                    if current { Image(systemName: "clock.fill").foregroundStyle(.cyan).font(.caption) }
                }
                if !episode.overview.isEmpty {
                    Text(episode.overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else if let runtime = episode.runtime {
                    Text("\(runtime) min").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .foregroundStyle(.white)
    }
}
