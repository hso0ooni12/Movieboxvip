import Foundation
import SwiftUI
import AVKit

// The app UI is native SwiftUI. FrameXTV is used only by FrameXTVPlayerScreen
// when an authorized catalog item supplies a TMDB-based FrameXTVPlayback descriptor.

enum MediaCategory: String, CaseIterable, Codable {
    case movie = "Movies"
    case series = "Series"
    case anime = "Anime"

    var symbol: String {
        switch self {
        case .movie: return "film.stack"
        case .series: return "tv"
        case .anime: return "sparkles.tv"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let overview: String
    let year: String
    let rating: String
    let category: MediaCategory
    let genres: [String]
    let posterURL: URL?
    let frameXTV: FrameXTVPlayback?
    let streamURL: URL?
    let downloadURL: URL?

    init(
        id: String,
        title: String,
        subtitle: String,
        overview: String,
        year: String,
        rating: String,
        category: MediaCategory,
        genres: [String],
        posterURL: URL? = nil,
        frameXTV: FrameXTVPlayback? = nil,
        streamURL: URL? = nil,
        downloadURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.overview = overview
        self.year = year
        self.rating = rating
        self.category = category
        self.genres = genres
        self.posterURL = posterURL
        self.frameXTV = frameXTV
        self.streamURL = streamURL
        self.downloadURL = downloadURL
    }
}

protocol ContentProvider {
    func featured() async throws -> [MediaItem]
    func catalog() async throws -> [MediaItem]
}

struct DemoContentProvider: ContentProvider {
    private let sampleStream = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8")

    private var items: [MediaItem] {
        [
            MediaItem(id: "m1", title: "Midnight Horizon", subtitle: "A cinematic demo feature", overview: "A polished sample title used to demonstrate the native interface, details page, playback flow, favorites and continue-watching UI.", year: "2026", rating: "8.7", category: .movie, genres: ["Drama", "Adventure"], streamURL: sampleStream),
            MediaItem(id: "m2", title: "Signal Zero", subtitle: "Tech thriller", overview: "A fast-paced demo movie inside the local sample catalog. Replace this item through your authorized metadata provider.", year: "2025", rating: "8.2", category: .movie, genres: ["Thriller", "Sci-Fi"], streamURL: sampleStream),
            MediaItem(id: "m3", title: "Blue District", subtitle: "Crime drama", overview: "Native SwiftUI detail presentation with rich metadata, actions and a real iOS player flow.", year: "2024", rating: "7.9", category: .movie, genres: ["Crime", "Drama"], streamURL: sampleStream),
            MediaItem(id: "s1", title: "Northern Line", subtitle: "Season 1", overview: "A demonstration series item prepared for an API-backed episode model in the provider layer.", year: "2026", rating: "9.0", category: .series, genres: ["Mystery", "Drama"], streamURL: sampleStream),
            MediaItem(id: "s2", title: "Afterlight", subtitle: "Season 2", overview: "Continue watching, watchlist and playback are designed as native app flows.", year: "2025", rating: "8.5", category: .series, genres: ["Drama", "Sci-Fi"], streamURL: sampleStream),
            MediaItem(id: "s3", title: "The Last Station", subtitle: "Season 1", overview: "Sample episodic content for testing the browse and search experience.", year: "2026", rating: "8.1", category: .series, genres: ["Mystery", "Adventure"], streamURL: sampleStream),
            MediaItem(id: "a1", title: "Neon Ronin", subtitle: "Episode collection", overview: "Anime-style sample entry for the dedicated category experience.", year: "2026", rating: "8.8", category: .anime, genres: ["Action", "Fantasy"], streamURL: sampleStream),
            MediaItem(id: "a2", title: "Sky Archive", subtitle: "Season 1", overview: "A clean native sample item showing how anime can live beside movies and series without wrapping the whole website.", year: "2025", rating: "8.4", category: .anime, genres: ["Fantasy", "Adventure"], streamURL: sampleStream),
            MediaItem(id: "a3", title: "Pixel Hearts", subtitle: "Season 1", overview: "Connect a metadata provider that supplies TMDB IDs to activate the FrameXTV player bridge.", year: "2024", rating: "7.8", category: .anime, genres: ["Comedy", "Romance"], streamURL: sampleStream)
        ]
    }

    func featured() async throws -> [MediaItem] { Array(items.prefix(4)) }
    func catalog() async throws -> [MediaItem] { items }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var featured: [MediaItem] = []
    @Published var all: [MediaItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let provider: any ContentProvider

    init(provider: any ContentProvider) {
        self.provider = provider
    }

    func load(force: Bool = false) async {
        if !force && !all.isEmpty { return }
        isLoading = true
        errorMessage = nil
        do {
            async let featuredRequest = provider.featured()
            async let catalogRequest = provider.catalog()
            featured = try await featuredRequest
            all = try await catalogRequest
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func items(in category: MediaCategory) -> [MediaItem] {
        all.filter { $0.category == category }
    }
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String> = [] {
        didSet { save() }
    }

    private let key = "FrameNative.favoriteIDs"

    init() {
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    func contains(_ item: MediaItem) -> Bool { favoriteIDs.contains(item.id) }

    func toggle(_ item: MediaItem) {
        if favoriteIDs.contains(item.id) {
            favoriteIDs.remove(item.id)
        } else {
            favoriteIDs.insert(item.id)
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(favoriteIDs), forKey: key)
    }
}

@MainActor
final class ProgressStore: ObservableObject {
    @Published private(set) var watchedIDs: [String] = []
    private let key = "FrameNative.watchedIDs"

    init() {
        watchedIDs = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func markStarted(_ item: MediaItem) {
        watchedIDs.removeAll { $0 == item.id }
        watchedIDs.insert(item.id, at: 0)
        if watchedIDs.count > 12 { watchedIDs = Array(watchedIDs.prefix(12)) }
        UserDefaults.standard.set(watchedIDs, forKey: key)
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading
        case finished(URL)
        case failed(String)
    }

    @Published private(set) var states: [String: State] = [:]

    func state(for item: MediaItem) -> State { states[item.id] ?? .idle }
    func canDownload(_ item: MediaItem) -> Bool { item.downloadURL != nil }

    func download(_ item: MediaItem) {
        guard let url = item.downloadURL else { return }
        states[item.id] = .downloading

        Task {
            do {
                let (temporaryURL, response) = try await URLSession.shared.download(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard status < 400 else { throw URLError(.badServerResponse) }

                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
                let destination = documents.appendingPathComponent("\(item.id).\(ext)")
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                states[item.id] = .finished(destination)
            } catch {
                states[item.id] = .failed(error.localizedDescription)
            }
        }
    }
}

@main
struct FrameNativeApp: App {
    @StateObject private var model = AppModel(provider: DemoContentProvider())
    @StateObject private var library = LibraryStore()
    @StateObject private var progress = ProgressStore()
    @StateObject private var downloads = DownloadManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(library)
                .environmentObject(progress)
                .environmentObject(downloads)
                .preferredColorScheme(.dark)
                .task { await model.load() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { CategoryView(category: .movie) }
                .tabItem { Label("Movies", systemImage: "film.fill") }

            NavigationStack { CategoryView(category: .series) }
                .tabItem { Label("TV", systemImage: "tv.fill") }

            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack { LibraryView() }
                .tabItem { Label("My List", systemImage: "bookmark.fill") }
        }
        .tint(.white)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var progress: ProgressStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if model.isLoading {
                ProgressView("Loading catalog…")
            } else if let error = model.errorMessage {
                EmptyStateView(title: "Couldn’t Load", message: error, systemImage: "wifi.exclamationmark")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        hero

                        if !continueWatching.isEmpty {
                            MediaRail(title: "Continue Watching", items: continueWatching)
                        }

                        MediaRail(title: "Trending Movies", items: model.items(in: .movie))
                        MediaRail(title: "Popular Series", items: model.items(in: .series))
                        MediaRail(title: "Anime", items: model.items(in: .anime))
                    }
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle("frameXTV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.92), for: .navigationBar)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var continueWatching: [MediaItem] {
        progress.watchedIDs.compactMap { id in model.all.first { $0.id == id } }
    }

    @ViewBuilder
    private var hero: some View {
        if let item = model.featured.first {
            NavigationLink(value: item) {
                ZStack(alignment: .bottomLeading) {
                    PosterArt(item: item, compact: false)
                        .frame(height: 470)
                    LinearGradient(colors: [.clear, .black.opacity(0.98)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("FEATURED")
                            .font(.caption.bold())
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.72))
                        Text(item.title)
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text("\(item.year)  •  ★ \(item.rating)  •  \(item.genres.joined(separator: " · "))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(2)
                        HStack(spacing: 12) {
                            Label("Play", systemImage: "play.fill")
                                .font(.headline)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 12)
                                .background(.white, in: Capsule())
                                .foregroundStyle(.black)
                            Label("Details", systemImage: "info.circle")
                                .font(.headline)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(22)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
        }
    }
}

struct CategoryView: View {
    @EnvironmentObject private var model: AppModel
    let category: MediaCategory

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                ForEach(model.items(in: category)) { item in
                    NavigationLink(value: item) { MediaCard(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle(category.rawValue)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }
}

struct MediaRail: View {
    let title: String
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .padding(.horizontal, 16)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { MediaCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct MediaCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterArt(item: item, compact: true)
                .frame(width: 152, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Text("★ \(item.rating)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(8)
                }
            Text(item.title)
                .font(.subheadline.bold())
                .lineLimit(1)
                .foregroundStyle(.white)
            Text(item.year)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 152, alignment: .leading)
    }
}

struct PosterArt: View {
    let item: MediaItem
    let compact: Bool

    private var gradient: [Color] {
        switch item.category {
        case .movie: return [Color(red: 0.30, green: 0.04, blue: 0.12), Color(red: 0.03, green: 0.04, blue: 0.09)]
        case .series: return [Color(red: 0.04, green: 0.18, blue: 0.28), Color(red: 0.02, green: 0.03, blue: 0.08)]
        case .anime: return [Color(red: 0.25, green: 0.06, blue: 0.38), Color(red: 0.03, green: 0.02, blue: 0.09)]
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)

            if let url = item.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }

            if !compact {
                LinearGradient(colors: [.clear, .black.opacity(0.3)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipped()
    }

    private var fallback: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.08))
                .frame(width: compact ? 100 : 240)
                .offset(x: compact ? 38 : 100, y: compact ? -60 : -120)
            Image(systemName: item.category.symbol)
                .font(.system(size: compact ? 42 : 92, weight: .thin))
                .foregroundStyle(.white.opacity(0.26))
            VStack {
                Spacer()
                HStack {
                    Text(item.category.rawValue.uppercased())
                        .font(.caption2.bold())
                        .tracking(1.2)
                    Spacer()
                }
                .foregroundStyle(.white.opacity(0.72))
                .padding(compact ? 12 : 20)
            }
        }
    }
}

struct DetailView: View {
    let item: MediaItem
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var progress: ProgressStore
    @EnvironmentObject private var downloads: DownloadManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PosterArt(item: item, compact: false)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                    Text(item.subtitle)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("\(item.year)  •  ★ \(item.rating)  •  \(item.category.rawValue)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(item.genres.joined(separator: "  •  "))
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.72))
                }

                playButton

                HStack(spacing: 12) {
                    Button { library.toggle(item) } label: {
                        Label(library.contains(item) ? "In My List" : "My List", systemImage: library.contains(item) ? "checkmark" : "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button { downloads.download(item) } label: {
                        downloadLabel.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!downloads.canDownload(item) || isDownloading)
                }

                Text(item.overview)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.84))
                    .lineSpacing(5)

                if item.frameXTV != nil {
                    Label("Playback uses the documented FrameXTV embed SDK. The rest of this screen is native SwiftUI.", systemImage: "iphone.gen3")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }

                if !downloads.canDownload(item) {
                    Label("Offline download remains disabled unless your authorized provider supplies a downloadable media URL.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var playButton: some View {
        if let playback = item.frameXTV {
            NavigationLink {
                FrameXTVPlayerScreen(item: item, playback: playback)
                    .onAppear { progress.markStarted(item) }
            } label: {
                Label("Play Now", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        } else if let stream = item.streamURL {
            NavigationLink {
                NativePlayerView(item: item, url: stream)
                    .onAppear { progress.markStarted(item) }
            } label: {
                Label("Play Demo", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
        } else {
            Label("Playback source unavailable", systemImage: "play.slash")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.secondary)
        }
    }

    private var isDownloading: Bool {
        if case .downloading = downloads.state(for: item) { return true }
        return false
    }

    @ViewBuilder
    private var downloadLabel: some View {
        switch downloads.state(for: item) {
        case .idle: Label("Download", systemImage: "arrow.down")
        case .downloading: Label("Downloading", systemImage: "arrow.down.circle")
        case .finished: Label("Downloaded", systemImage: "checkmark.circle.fill")
        case .failed: Label("Retry", systemImage: "exclamationmark.arrow.circlepath")
        }
    }
}

struct NativePlayerView: View {
    let item: MediaItem
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            player.play()
        }
        .onDisappear { player.pause() }
    }
}

struct SearchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""

    private var results: [MediaItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return model.all }
        return model.all.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.genres.contains(where: { $0.localizedCaseInsensitiveContains(query) }) ||
            $0.category.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                ForEach(results) { item in
                    NavigationLink(value: item) { MediaCard(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Movies, series, anime…")
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore

    private var items: [MediaItem] {
        model.all.filter { library.favoriteIDs.contains($0.id) }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(title: "Your List Is Empty", message: "Add titles from any details page.", systemImage: "bookmark")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 22) {
                        ForEach(items) { item in
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

struct DownloadsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var downloads: DownloadManager

    private var finishedItems: [MediaItem] {
        model.all.filter {
            if case .finished = downloads.state(for: $0) { return true }
            return false
        }
    }

    var body: some View {
        Group {
            if finishedItems.isEmpty {
                EmptyStateView(title: "No Downloads", message: "Authorized downloadable media will appear here.", systemImage: "arrow.down.circle")
            } else {
                List(finishedItems) { item in
                    if case .finished(let url) = downloads.state(for: item) {
                        NavigationLink {
                            NativePlayerView(item: item, url: url)
                        } label: {
                            HStack(spacing: 14) {
                                PosterArt(item: item, compact: true)
                                    .frame(width: 58, height: 82)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading) {
                                    Text(item.title).font(.headline)
                                    Text("Available offline").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Color.black)
        .navigationTitle("Downloads")
    }
}
