import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Binding var showSettings: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if app.isLoading && !app.didLoad {
                PremiumLoadingView(message: "Building your catalog…")
            } else if let error = app.errorMessage, !app.didLoad {
                VStack(spacing: 20) {
                    EmptyStateView(title: "Couldn’t Load", message: error, systemImage: "wifi.exclamationmark")
                    Button {
                        Task { await app.loadHome(force: true) }
                    } label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if let hero = featuredItem {
                            HeroView(item: hero)
                        }

                        categoryStrip

                        if !library.continueWatching.isEmpty {
                            VStack(alignment: .leading, spacing: 13) {
                                SectionHeader(title: "Continue Watching", subtitle: "Pick up exactly where you left off")
                                ScrollView(.horizontal) {
                                    LazyHStack(spacing: 14) {
                                        ForEach(library.continueWatching, id: \.item.id) { entry in
                                            NavigationLink {
                                                DetailView(item: entry.item)
                                            } label: {
                                                ContinueWatchingCard(progress: entry)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 18)
                                }
                                .scrollIndicators(.hidden)
                            }
                        }

                        MediaRail(title: "Trending Movies", items: app.trendingMovies, subtitle: "Popular around the world this week")
                        MediaRail(title: "Series Everyone’s Watching", items: app.trendingTV, subtitle: "Fresh picks and fan favorites")
                        MediaRail(title: "Anime Spotlight", items: app.anime, subtitle: "Popular Japanese animation")

                        VStack(alignment: .leading, spacing: 10) {
                            Text("frameX")
                                .font(.system(size: 26, weight: .black, design: .rounded))
                            Text("Movies, series and anime in one clean native experience.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 4)
                    }
                    .padding(.bottom, 38)
                }
                .refreshable { await app.loadHome(force: true) }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("frameX")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.88), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    MyListView()
                } label: {
                    Image(systemName: "bookmark.fill")
                        .font(.body.weight(.semibold))
                }

                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var featuredItem: MediaItem? {
        let candidates = Array(app.trendingMovies.prefix(5)) + Array(app.trendingTV.prefix(5))
        return candidates.max(by: { $0.voteAverage < $1.voteAverage }) ?? app.trendingMovies.first ?? app.trendingTV.first
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                NavigationLink {
                    CatalogView(kind: .movie, title: "Movies")
                } label: {
                    CategoryChip(title: "Movies", systemImage: "film.fill")
                }
                NavigationLink {
                    CatalogView(kind: .tv, title: "Series")
                } label: {
                    CategoryChip(title: "Series", systemImage: "play.tv.fill")
                }
                NavigationLink {
                    CatalogView(kind: .anime, title: "Anime")
                } label: {
                    CategoryChip(title: "Anime", systemImage: "sparkles")
                }
                NavigationLink {
                    MyListView()
                } label: {
                    CategoryChip(title: "My List", systemImage: "bookmark.fill")
                }
            }
            .padding(.horizontal, 18)
        }
        .scrollIndicators(.hidden)
        .buttonStyle(.plain)
    }
}

private struct CategoryChip: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.white.opacity(0.075), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
            .foregroundStyle(.white)
    }
}

struct CatalogView: View {
    @EnvironmentObject private var app: AppState
    let kind: MediaKind
    let title: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if app.list(for: kind).isEmpty && app.isLoading {
                PremiumLoadingView(message: "Loading \(title.lowercased())…")
            } else if app.list(for: kind).isEmpty {
                EmptyStateView(title: "Nothing Here Yet", message: "Pull to refresh the catalog.", systemImage: kind.symbol)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        catalogHeader

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 172), spacing: 14)], spacing: 22) {
                            ForEach(app.list(for: kind)) { item in
                                NavigationLink(value: item) {
                                    MediaCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 32)
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
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text("CURATED FOR YOU")
                    .font(.caption2.bold())
                    .tracking(1.6)
                    .foregroundStyle(.secondary)
                Text("\(app.list(for: kind).count) titles ready to explore")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
            }
            Spacer()
            Image(systemName: kind.symbol)
                .font(.title2.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 18)
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
            Color.black.ignoresSafeArea()

            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                discoverContent
            } else if isSearching && results.isEmpty {
                PremiumLoadingView(message: "Searching…")
            } else if let error, results.isEmpty {
                EmptyStateView(title: "Search Failed", message: error, systemImage: "exclamationmark.magnifyingglass")
            } else if results.isEmpty {
                EmptyStateView(title: "No Results", message: "Try another title, spelling or language.", systemImage: "film")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 172), spacing: 14)], spacing: 22) {
                        ForEach(results) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Movies, series, anime…")
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 420_000_000)
                guard !Task.isCancelled else { return }
                await performSearch(newValue)
            }
        }
        .onDisappear { searchTask?.cancel() }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var discoverContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find your next watch")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                    Text("Search across movies, series and anime from one place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)

                MediaRail(title: "Trending Searches", items: Array(app.trendingMovies.prefix(10)))
                MediaRail(title: "Popular Series", items: Array(app.trendingTV.prefix(10)))
            }
            .padding(.bottom, 30)
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
            Color.black.ignoresSafeArea()

            if library.favoriteItems.isEmpty {
                EmptyStateView(title: "Your List Is Empty", message: "Save any title from its details page and it will appear here.", systemImage: "bookmark")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 172), spacing: 14)], spacing: 22) {
                        ForEach(library.favoriteItems) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("My List")
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }
}
