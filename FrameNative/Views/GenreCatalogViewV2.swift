import SwiftUI

struct GenreCatalogView: View {
    @EnvironmentObject private var app: AppState

    let kind: MediaKind
    let title: String

    @State private var selectedGenreID: Int?
    @State private var genreItems: [MediaItem] = []
    @State private var isLoadingGenre = false
    @State private var genreError: String?
    @State private var searchText = ""

    private var genres: [CatalogGenre] {
        switch kind {
        case .movie: return CatalogGenre.movieGenres
        case .tv: return CatalogGenre.tvGenres
        case .anime: return []
        }
    }

    private var selectedGenre: CatalogGenre? {
        guard let selectedGenreID else { return nil }
        return genres.first { $0.id == selectedGenreID }
    }

    private var sourceItems: [MediaItem] {
        selectedGenreID == nil ? app.list(for: kind) : genreItems
    }

    private var visibleItems: [MediaItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sourceItems }
        return sourceItems.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.subtitle.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            XSBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    genreSelector

                    if isLoadingGenre && genreItems.isEmpty {
                        genreLoading
                    } else if let genreError, selectedGenreID != nil, genreItems.isEmpty {
                        genreFailure(genreError)
                    } else if visibleItems.isEmpty {
                        EmptyStateView(
                            title: searchText.isEmpty ? "Nothing Here Yet" : "No Matches",
                            message: searchText.isEmpty ? "Try another genre or pull to refresh." : "Try another title or genre.",
                            systemImage: kind.symbol
                        )
                    } else {
                        resultsHeader

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 16)],
                            spacing: 24
                        ) {
                            ForEach(visibleItems) { item in
                                NavigationLink(value: item) {
                                    MediaCard(item: item, width: 154)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                if let genre = selectedGenre {
                    await load(genre: genre)
                } else {
                    await app.loadHome(force: true)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search \(title.lowercased())…")
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var heroHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.88), .pink.opacity(0.74), .orange.opacity(0.56)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: kind == .movie ? "film.stack.fill" : "play.tv.fill")
                    .font(.title2.weight(.bold))
            }
            .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text("BROWSE BY GENRE")
                    .font(.caption2.bold())
                    .tracking(1.8)
                    .foregroundStyle(.secondary)

                Text(selectedGenre?.name ?? "All \(title)")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)

                Text(selectedGenre == nil ? "Choose a genre below to explore the catalog" : "Popular \(selectedGenre?.name ?? "") \(kind == .movie ? "movies" : "series")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.075)))
        .padding(.horizontal, 16)
    }

    private var genreSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(kind == .movie ? "Movie Genres" : "Series Genres")
                    .font(.title3.bold())
                Spacer()
                if isLoadingGenre {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.82)
                }
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    genreButton(title: "All", systemImage: "square.grid.2x2.fill", id: nil)
                    ForEach(genres) { genre in
                        genreButton(title: genre.name, systemImage: genre.systemImage, id: genre.id)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func genreButton(title: String, systemImage: String, id: Int?) -> some View {
        let selected = selectedGenreID == id

        return Button {
            guard selectedGenreID != id else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedGenreID = id
                searchText = ""
                genreError = nil
            }

            if let id, let genre = genres.first(where: { $0.id == id }) {
                Task { await load(genre: genre) }
            } else {
                genreItems = []
                isLoadingGenre = false
            }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background {
                    if selected {
                        LinearGradient(
                            colors: [.purple.opacity(0.88), .pink.opacity(0.78), .orange.opacity(0.58)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color.white.opacity(0.065)
                    }
                }
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(selected ? 0.15 : 0.07), lineWidth: 1))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var resultsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedGenre?.name ?? "All \(title)")
                    .font(.title2.bold())
                Text("\(visibleItems.count) titles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
    }

    private var genreLoading: some View {
        VStack(spacing: 18) {
            ProgressView()
                .scaleEffect(1.15)
                .tint(.white)
            Text("Loading \(selectedGenre?.name ?? "genre")…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private func genreFailure(_ message: String) -> some View {
        VStack(spacing: 14) {
            EmptyStateView(title: "Couldn’t Load Genre", message: message, systemImage: "wifi.exclamationmark")
            if let genre = selectedGenre {
                Button {
                    Task { await load(genre: genre) }
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.white, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func load(genre: CatalogGenre) async {
        isLoadingGenre = true
        genreError = nil

        do {
            let client = app.client
            var loaded: [MediaItem] = []

            // The proxy currently permits the same catalog routes used by Home but rejects
            // /discover with 403. Build a much larger genre pool from the allowed popular +
            // trending pages, then filter using the real TMDB genre IDs carried by each item.
            for page in 1...4 {
                if kind == .movie {
                    async let popular = client.popularMovies(page: page)
                    async let trending = client.trendingMovies(page: page)
                    let pair = try await (popular, trending)
                    loaded.append(contentsOf: pair.0)
                    loaded.append(contentsOf: pair.1)
                } else {
                    async let popular = client.popularTV(page: page)
                    async let trending = client.trendingTV(page: page)
                    let pair = try await (popular, trending)
                    loaded.append(contentsOf: pair.0)
                    loaded.append(contentsOf: pair.1)
                }
            }

            guard selectedGenreID == genre.id else { return }

            var seen = Set<String>()
            let filtered = loaded
                .filter { $0.genreIDs.contains(genre.id) }
                .filter { seen.insert($0.id).inserted }

            if filtered.isEmpty {
                var fallbackSeen = Set<String>()
                genreItems = app.list(for: kind)
                    .filter { $0.genreIDs.contains(genre.id) }
                    .filter { fallbackSeen.insert($0.id).inserted }
            } else {
                genreItems = filtered
            }
        } catch {
            guard selectedGenreID == genre.id else { return }

            // Never leave the genre screen broken because one extra page failed. The Home
            // catalog is already loaded through known-good routes and still carries genre IDs.
            var seen = Set<String>()
            let fallback = app.list(for: kind)
                .filter { $0.genreIDs.contains(genre.id) }
                .filter { seen.insert($0.id).inserted }

            if fallback.isEmpty {
                genreItems = []
                genreError = error.localizedDescription
            } else {
                genreItems = fallback
                genreError = nil
            }
        }

        if selectedGenreID == genre.id {
            isLoadingGenre = false
        }
    }
}

private struct CatalogGenre: Identifiable, Hashable {
    let id: Int
    let name: String
    let systemImage: String

    static let movieGenres: [CatalogGenre] = [
        .init(id: 28, name: "Action", systemImage: "bolt.fill"),
        .init(id: 12, name: "Adventure", systemImage: "map.fill"),
        .init(id: 35, name: "Comedy", systemImage: "face.smiling"),
        .init(id: 10752, name: "War", systemImage: "shield.fill"),
        .init(id: 80, name: "Crime", systemImage: "lock.shield.fill"),
        .init(id: 18, name: "Drama", systemImage: "theatermasks.fill"),
        .init(id: 53, name: "Thriller", systemImage: "exclamationmark.triangle.fill"),
        .init(id: 27, name: "Horror", systemImage: "moon.stars.fill"),
        .init(id: 878, name: "Sci‑Fi", systemImage: "sparkles"),
        .init(id: 14, name: "Fantasy", systemImage: "wand.and.stars"),
        .init(id: 10749, name: "Romance", systemImage: "heart.fill"),
        .init(id: 9648, name: "Mystery", systemImage: "questionmark.circle.fill"),
        .init(id: 16, name: "Animation", systemImage: "paintpalette.fill"),
        .init(id: 10751, name: "Family", systemImage: "person.3.fill"),
        .init(id: 99, name: "Documentary", systemImage: "camera.fill"),
        .init(id: 36, name: "History", systemImage: "books.vertical.fill"),
        .init(id: 10402, name: "Music", systemImage: "music.note"),
        .init(id: 37, name: "Western", systemImage: "sun.max.fill")
    ]

    static let tvGenres: [CatalogGenre] = [
        .init(id: 10759, name: "Action & Adventure", systemImage: "bolt.fill"),
        .init(id: 35, name: "Comedy", systemImage: "face.smiling"),
        .init(id: 10768, name: "War & Politics", systemImage: "shield.fill"),
        .init(id: 80, name: "Crime", systemImage: "lock.shield.fill"),
        .init(id: 18, name: "Drama", systemImage: "theatermasks.fill"),
        .init(id: 9648, name: "Mystery", systemImage: "questionmark.circle.fill"),
        .init(id: 10765, name: "Sci‑Fi & Fantasy", systemImage: "sparkles"),
        .init(id: 16, name: "Animation", systemImage: "paintpalette.fill"),
        .init(id: 10751, name: "Family", systemImage: "person.3.fill"),
        .init(id: 10762, name: "Kids", systemImage: "figure.2.and.child.holdinghands"),
        .init(id: 99, name: "Documentary", systemImage: "camera.fill"),
        .init(id: 10764, name: "Reality", systemImage: "person.2.fill"),
        .init(id: 10766, name: "Soap", systemImage: "tv.fill"),
        .init(id: 10767, name: "Talk", systemImage: "bubble.left.and.bubble.right.fill"),
        .init(id: 37, name: "Western", systemImage: "sun.max.fill")
    ]
}
