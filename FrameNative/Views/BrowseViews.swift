import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Binding var showSettings: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if app.isLoading && !app.didLoad {
                ProgressView("Loading catalog…")
            } else if let error = app.errorMessage, !app.didLoad {
                EmptyStateView(title: "Couldn’t Load", message: error, systemImage: "wifi.exclamationmark")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        if let hero = app.trendingMovies.first ?? app.trendingTV.first {
                            HeroView(item: hero)
                        }

                        if !library.continueWatching.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Continue Watching")
                                    .font(.title3.bold())
                                    .padding(.horizontal, 16)
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
                                    .padding(.horizontal, 16)
                                }
                                .scrollIndicators(.hidden)
                            }
                        }

                        MediaRail(title: "Trending Movies", items: app.trendingMovies)
                        MediaRail(title: "Popular TV", items: app.trendingTV)
                        MediaRail(title: "Anime", items: app.anime)
                    }
                    .padding(.bottom, 34)
                }
                .refreshable { await app.loadHome(force: true) }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("frameX")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.92), for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    MyListView()
                } label: {
                    Image(systemName: "bookmark.fill")
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
        }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }
}

struct CatalogView: View {
    @EnvironmentObject private var app: AppState
    let kind: MediaKind
    let title: String

    var body: some View {
        Group {
            if app.list(for: kind).isEmpty && app.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 16)], spacing: 22) {
                        ForEach(app.list(for: kind)) { item in
                            NavigationLink(value: item) { MediaCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await app.loadHome(force: true) }
            }
        }
        .background(Color.black)
        .navigationTitle(title)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
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
        Group {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                EmptyStateView(title: "Search", message: "Find movies, series and anime by title.", systemImage: "magnifyingglass")
            } else if isSearching && results.isEmpty {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error, results.isEmpty {
                EmptyStateView(title: "Search Failed", message: error, systemImage: "exclamationmark.magnifyingglass")
            } else if results.isEmpty {
                EmptyStateView(title: "No Results", message: "Try another title or spelling.", systemImage: "film")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 16)], spacing: 22) {
                        ForEach(results) { item in
                            NavigationLink(value: item) { MediaCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Movies, series, anime…")
        .onChange(of: query) { newValue in
            searchTask?.cancel()
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                guard !Task.isCancelled else { return }
                await performSearch(newValue)
            }
        }
        .onDisappear { searchTask?.cancel() }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
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
        Group {
            if library.favoriteItems.isEmpty {
                EmptyStateView(title: "Your List Is Empty", message: "Save any title from its details page.", systemImage: "bookmark")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 16)], spacing: 22) {
                        ForEach(library.favoriteItems) { item in
                            NavigationLink(value: item) { MediaCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.black)
        .navigationTitle("My List")
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }
}
