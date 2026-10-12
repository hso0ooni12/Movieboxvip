import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Binding var showSettings: Bool

    var body: some View {
        ZStack {
            XSBackground()

            if app.isLoading && !app.didLoad {
                PremiumLoadingView(message: "Preparing XS TV…")
            } else if let error = app.errorMessage, !app.didLoad {
                VStack(spacing: 20) {
                    EmptyStateView(title: "Couldn’t Load", message: error, systemImage: "wifi.exclamationmark")
                    Button {
                        Task { await app.loadHome(force: true) }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 32) {
                        HeroCarousel(items: app.spotlight)

                        categoryStrip

                        continueWatchingSection

                        TopTenRail(items: app.topTen)

                        MediaRail(
                            title: "Trending Movies",
                            items: app.trendingMovies,
                            subtitle: "The movies everyone is talking about"
                        )

                        MediaRail(
                            title: "Popular Movies",
                            items: app.popularMovies,
                            subtitle: "Big-screen favorites picked for XS TV"
                        )

                        MediaRail(
                            title: "Series Everyone’s Watching",
                            items: app.trendingTV,
                            subtitle: "Binge-worthy stories trending worldwide"
                        )

                        MediaRail(
                            title: "Popular Series",
                            items: app.popularTV,
                            subtitle: "More shows worth adding to your list"
                        )

                        MediaRail(
                            title: "Anime Spotlight",
                            items: app.anime,
                            subtitle: "Popular Japanese animation"
                        )

                        xsFooter
                    }
                    .padding(.bottom, 44)
                }
                .refreshable { await app.loadHome(force: true) }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.84), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                XSWordmark(compact: true)
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    MyListView()
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
            }
        }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        if !library.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Continue Watching", subtitle: "Resume instantly from where you stopped")

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(library.continueWatching, id: \.item.id) { entry in
                            NavigationLink {
                                FrameXTVPlayerScreen(
                                    item: entry.item,
                                    playback: FrameXTVPlayback(
                                        tmdbID: entry.item.tmdbID,
                                        season: entry.season,
                                        episode: entry.episode,
                                        startAt: entry.currentTime
                                    )
                                )
                            } label: {
                                ContinueWatchingCard(progress: entry)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    library.removeProgress(for: entry.item)
                                } label: {
                                    Label("Remove from Continue Watching", systemImage: "xmark.circle")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 11) {
                NavigationLink {
                    CatalogView(kind: .movie, title: "Movies")
                } label: {
                    PremiumCategoryChip(title: "Movies", subtitle: "Cinema", systemImage: "film.fill")
                }

                NavigationLink {
                    CatalogView(kind: .tv, title: "Series")
                } label: {
                    PremiumCategoryChip(title: "Series", subtitle: "Binge", systemImage: "play.tv.fill")
                }

                NavigationLink {
                    CatalogView(kind: .anime, title: "Anime")
                } label: {
                    PremiumCategoryChip(title: "Anime", subtitle: "Discover", systemImage: "sparkles")
                }

                NavigationLink {
                    MyListView()
                } label: {
                    PremiumCategoryChip(title: "My List", subtitle: "Saved", systemImage: "bookmark.fill")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .buttonStyle(.plain)
    }

    private var xsFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                XSBrandMark(size: 42, showGlow: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text("XS TV")
                        .font(.title2.black())
                    Text("Entertainment, refined for iPhone and iPad")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 1)

            Text("Your favorites and watch progress stay on this device.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(18)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.06)))
        .padding(.horizontal, 18)
        .padding(.top, 4)
    }
}

private struct PremiumCategoryChip: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 36, height: 36)
                .background(
                    LinearGradient(
                        colors: [.purple.opacity(0.8), .pink.opacity(0.72), .orange.opacity(0.58)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.white.opacity(0.09)))
        .foregroundStyle(.white)
    }
}

struct CatalogView: View {
    @EnvironmentObject private var app: AppState
    let kind: MediaKind
    let title: String

    var body: some View {
        ZStack {
            XSBackground()

            if app.list(for: kind).isEmpty && app.isLoading {
                PremiumLoadingView(message: "Loading \(title.lowercased())…")
            } else if app.list(for: kind).isEmpty {
                EmptyStateView(title: "Nothing Here Yet", message: "Pull to refresh the catalog.", systemImage: kind.symbol)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        catalogHeader

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                            spacing: 24
                        ) {
                            ForEach(app.list(for: kind)) { item in
                                NavigationLink(value: item) {
                                    MediaCard(item: item, width: 154)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 38)
                }
                .refreshable { await app.loadHome(force: true) }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var catalogHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.72), .pink.opacity(0.62), .orange.opacity(0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: kind.symbol)
                    .font(.title2.weight(.semibold))
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text("XS TV COLLECTION")
                    .font(.caption2.bold())
                    .tracking(1.7)
                    .foregroundStyle(.secondary)
                Text("\(app.list(for: kind).count) titles ready to explore")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.92))
            }
            Spacer()
        }
        .padding(16)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.07)))
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}

struct SearchView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            XSBackground()

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                discoverContent
            } else if isSearching && results.isEmpty {
                PremiumLoadingView(message: "Searching XS TV…")
            } else if let error, results.isEmpty {
                EmptyStateView(title: "Search Failed", message: error, systemImage: "exclamationmark.magnifyingglass")
            } else if results.isEmpty {
                EmptyStateView(title: "No Results", message: "Try another title, spelling or language.", systemImage: "film")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("\(results.count) results")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 17)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                            spacing: 24
                        ) {
                            ForEach(results) { item in
                                NavigationLink(value: item) {
                                    MediaCard(item: item, width: 154)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Movies, series, anime…")
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 380_000_000)
                guard !Task.isCancelled else { return }
                await performSearch(newValue)
            }
        }
        .onDisappear { searchTask?.cancel() }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var discoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Find your next favorite")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    Text("Search movies, series and anime from one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                TopTenRail(items: Array(app.topTen.prefix(10)))
                MediaRail(title: "Popular Movies", items: Array(app.popularMovies.prefix(12)))
                MediaRail(title: "Popular Series", items: Array(app.popularTV.prefix(12)))
            }
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
    }

    @MainActor
    private func performSearch(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            error = nil
            return
        }

        isSearching = true
        error = nil
        do {
            results = try await app.search(trimmed)
        } catch {
            self.error = error.localizedDescription
            results = []
        }
        isSearching = false
    }
}

struct MyListView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ZStack {
            XSBackground()

            if library.favoriteItems.isEmpty {
                EmptyStateView(
                    title: "Your List Is Empty",
                    message: "Save any movie or series and build your own XS TV collection.",
                    systemImage: "bookmark"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 14) {
                            XSBrandMark(size: 44, showGlow: false)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your Collection")
                                    .font(.title2.bold())
                                Text("\(library.favoriteItems.count) saved titles")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                            spacing: 24
                        ) {
                            ForEach(library.favoriteItems) { item in
                                NavigationLink(value: item) {
                                    MediaCard(item: item, width: 154)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("My List")
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }
}
