import SwiftUI

struct DetailScreen: View {
    let item: MediaTitle
    @EnvironmentObject private var store: AppStore
    @State private var refreshed: MediaTitle?
    @State private var season = 1
    @State private var seasons: [ShowSeason] = []
    @State private var episodes: [MediaEpisode] = []
    @State private var episodesLoading = false
    @State private var episodeError: String?
    @State private var playback: SitePlaybackRequest?
    @State private var detailsLoaded = false
    private var title: MediaTitle { refreshed ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: title.backdropURL).frame(height: 290)
                    LinearGradient(colors: [.clear, WatchedTheme.background], startPoint: .center, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 16) {
                        RemoteImage(url: title.posterURL).frame(width: 100, height: 150).clipShape(RoundedRectangle(cornerRadius: 13))
                            .shadow(color: .black.opacity(0.5), radius: 14, y: 7)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.t(title.kind == .movie ? "فيلم" : "مسلسل", title.kind == .movie ? "MOVIE" : "SERIES"))
                                .font(.system(size: 10, weight: .bold)).tracking(1.5).foregroundStyle(WatchedTheme.accent)
                            Text(title.name).font(.system(size: 26, weight: .bold)).lineLimit(3).minimumScaleFactor(0.8)
                                .environment(\.layoutDirection, .leftToRight).accessibilityIdentifier("detail-title")
                            HStack(spacing: 9) {
                                Text(title.year)
                                if title.rating > 0 { Label(String(format: "%.1f", title.rating), systemImage: "star.fill").foregroundStyle(.yellow) }
                            }.font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 20)
                }
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 10) {
                        Button { play() } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "play.fill")
                                Text(store.t("مشاهدة الآن", "Play now"))
                            }
                        }.buttonStyle(PrimaryAction()).accessibilityIdentifier("play-title")
                        Button { store.toggleSaved(title) } label: {
                            Image(systemName: store.isSaved(title) ? "checkmark" : "plus")
                                .font(.system(size: 20)).frame(width: 49, height: 49)
                                .foregroundStyle(.white).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                        }.accessibilityLabel(store.isSaved(title) ? store.t("إزالة من قائمتي", "Remove from My List") : store.t("إضافة إلى قائمتي", "Add to My List"))
                    }
                    if !title.genres.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 7) { ForEach(title.genres, id: \.self) { genre in
                                Text(genre).font(.system(size: 11, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7)
                                    .foregroundStyle(.white.opacity(0.65)).background(.white.opacity(0.045), in: Capsule())
                            } }
                        }.scrollIndicators(.hidden)
                    }
                    VStack(alignment: .leading, spacing: 11) {
                        Text(store.t("القصة", "Story")).font(.system(size: 18, weight: .bold))
                        Text(title.overview.isEmpty ? store.t("لا يتوفر وصف لهذا العنوان حالياً", "A synopsis isn’t available for this title yet") : title.overview)
                            .font(.system(size: 14)).lineSpacing(6).foregroundStyle(.white.opacity(0.6))
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    if title.kind == .tv { episodeList }
                    let related = store.home.allTitles.filter { $0.kind == title.kind && $0.id != title.id }
                    if !related.isEmpty { TitleRail(rail: .init(id: "related", title: store.t("اكتشف أكثر", "Keep exploring"), items: Array(related.prefix(14)))).padding(.horizontal, -20) }
                }.padding(.horizontal, 20)
            }.padding(.bottom, 35)
        }
        .background(WatchedTheme.background).scrollIndicators(.hidden)
        .toolbarBackground(WatchedTheme.background, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(SafariPlayerPresenter(request: $playback, preview: store.isPreview).frame(width: 0, height: 0))
        .task {
            guard !detailsLoaded else { return }
            if store.isPreview {
                #if DEBUG
                if item.kind == .tv {
                    let testEpisodes = (1...2).map { MediaEpisode(id: $0, name: "Episode \($0) · Navigation test", episode_number: $0) }
                    seasons = [ShowSeason(number: 1, name: "Season 1", episodeCount: 2, episodes: testEpisodes)]
                    episodes = testEpisodes
                }
                #endif
                detailsLoaded = true
                return
            }
            if item.kind == .tv { episodesLoading = true }
            do {
                let details = try await WatchedClient.shared.detail(item)
                refreshed = details.title; seasons = details.seasons; detailsLoaded = true
                let first = details.seasons.first(where: { $0.number > 0 }) ?? details.seasons.first
                season = details.activeSeason ?? first?.number ?? 1
                await loadEpisodes()
            } catch is CancellationError { }
            catch { episodeError = error.localizedDescription; episodesLoading = false }
        }
        .task(id: season) { await loadEpisodes() }
    }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(store.t("الحلقات", "Episodes")).font(.system(size: 18, weight: .bold))
                Spacer()
                if !seasons.isEmpty {
                    Menu {
                        ForEach(seasons) { option in
                            Button(store.t("الموسم \(option.number) · \(option.episodeCount) حلقة", "Season \(option.number) · \(option.episodeCount) episodes")) { season = option.number }
                        }
                    } label: {
                        Label(store.t("الموسم \(season)", "Season \(season)"), systemImage: "chevron.down").font(.system(size: 13, weight: .medium))
                    }
                }
            }
            if episodesLoading { ProgressView().frame(maxWidth: .infinity).padding() }
            else if let episodeError { Text(episodeError).font(.caption).foregroundStyle(.secondary) }
            else if episodes.isEmpty { Text(store.t("لا توجد حلقات متاحة لهذا الموسم", "No episodes available for this season")).font(.caption).foregroundStyle(.secondary) }
            ForEach(episodes) { episode in
                Button { play(episode: episode) } label: {
                    HStack(spacing: 13) {
                        RemoteImage(url: title.imageURL(episode.still_path, size: "w500")).frame(width: 116, height: 65).clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay { Image(systemName: "play.fill").font(.system(size: 17)).shadow(radius: 5) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(episode.episode_number). \(episode.name)").font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            if let overview = episode.overview, !overview.isEmpty { Text(overview).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("play-episode-\(season)-\(episode.episode_number)")
            }
        }
    }
    private func loadEpisodes() async {
        guard title.kind == .tv, !store.isPreview, let selected = seasons.first(where: { $0.number == season }) else { return }
        if !selected.episodes.isEmpty { episodes = selected.episodes; episodesLoading = false; episodeError = nil; return }
        let requestedSeason = season
        episodesLoading = true; episodeError = nil
        do {
            let values = try await WatchedClient.shared.episodes(tmdbID: title.tmdbID, season: requestedSeason)
            guard season == requestedSeason else { return }
            episodes = values; episodesLoading = false
        } catch is CancellationError { }
        catch {
            guard season == requestedSeason else { return }
            episodeError = error.localizedDescription; episodes = []; episodesLoading = false
        }
    }

    private func play(episode selectedEpisode: MediaEpisode? = nil) {
        guard playback == nil else { return }
        let saved = store.progress.first(where: { $0.id == title.id })
        let selectedSeason: Int? = title.kind == .tv ? (selectedEpisode != nil ? season : saved?.season ?? season) : nil
        let number: Int? = title.kind == .tv ? (selectedEpisode?.episode_number ?? saved?.episode ?? episodes.first?.episode_number ?? 1) : nil
        // System Safari owns the live session and resume timing; do not inject stale native progress.
        playback = SitePlaybackRequest(title: title, season: selectedSeason, episode: number)
    }
}

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(store.t("اللغة", "Language")) {
                    Picker(store.t("لغة التطبيق", "App language"), selection: $store.language) {
                        Text("العربية").tag("ar")
                        Text("English").tag("en")
                    }
                }
                Section(store.t("المشاهدة", "Watching")) {
                    Text(store.t("تقدر تغيّر الجودة والترجمة من إعدادات مشغّل الموقع أثناء المشاهدة.", "Change quality and subtitles in the website player while watching."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    HStack { Wordmark(); Spacer(); Text("v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")").font(.caption).foregroundStyle(.secondary) }
                    Text(store.t("المشاهدة تفتح بنافذة سفاري داخل التطبيق. اضغط زر إغلاق سفاري للرجوع للحلقات.", "Playback opens in system Safari inside the app. Use Safari’s Close button to return to episodes."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden).background(WatchedTheme.background)
            .navigationTitle(store.t("الإعدادات", "Settings"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("تم", "Done")) { dismiss() } } }
        }
    }
}
