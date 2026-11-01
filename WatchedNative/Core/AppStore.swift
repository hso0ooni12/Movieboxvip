import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var home: HomeSnapshot
    @Published var isRefreshing = false
    @Published var connectionMessage: String?
    @Published var saved: [MediaTitle] = []
    @Published var progress: [WatchProgress] = []
    @Published var language: String { didSet { UserDefaults.standard.set(language, forKey: "watched.language") } }
    @Published var subtitleLanguage: String { didSet { UserDefaults.standard.set(subtitleLanguage, forKey: "watched.subtitles") } }
    let isPreview: Bool
    private let defaults = UserDefaults.standard
    private let cacheURL: URL

    init() {
        language = UserDefaults.standard.string(forKey: "watched.language") ?? "ar"
        subtitleLanguage = UserDefaults.standard.string(forKey: "watched.subtitles") ?? "ar"
        isPreview = ProcessInfo.processInfo.arguments.contains("-ui-preview")
        cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("watched-home.json")
        if let data = try? Data(contentsOf: cacheURL), let snapshot = try? JSONDecoder().decode(HomeSnapshot.self, from: data) {
            home = snapshot
        } else if let url = Bundle.main.url(forResource: "home-snapshot", withExtension: "json"),
                  let data = try? Data(contentsOf: url), let snapshot = try? JSONDecoder().decode(HomeSnapshot.self, from: data) {
            home = snapshot
        } else { home = HomeSnapshot(featured: [], rails: [], providers: [], capturedAt: nil) }
        if let data = defaults.data(forKey: "watched.saved"), let values = try? JSONDecoder().decode([MediaTitle].self, from: data) { saved = values }
        if let data = defaults.data(forKey: "watched.progress"), let values = try? JSONDecoder().decode([WatchProgress].self, from: data) { progress = values }
        if isPreview { connectionMessage = t("نسخة تجريبية · بيانات محفوظة من الموقع", "Browsing preview · Saved site data") }
    }

    func t(_ arabic: String, _ english: String) -> String { language == "ar" ? arabic : english }

    func refresh() async {
        guard !isRefreshing, !isPreview else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            var fresh = try await WatchedClient.shared.home()
            fresh.capturedAt = ISO8601DateFormatter().string(from: Date())
            home = fresh; connectionMessage = nil
            if let data = try? JSONEncoder().encode(fresh) { try? data.write(to: cacheURL, options: .atomic) }
        } catch is CancellationError { }
        catch {
            connectionMessage = t("تعذّر التحديث · تعرض نسخة محفوظة من الموقع", "Couldn’t refresh · Showing a saved copy of the site")
        }
    }

    func isSaved(_ item: MediaTitle) -> Bool { saved.contains { $0.id == item.id } }

    func toggleSaved(_ item: MediaTitle) {
        if isSaved(item) { saved.removeAll { $0.id == item.id } }
        else { saved.insert(item, at: 0) }
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: "watched.saved") }
    }

    func updateProgress(title: MediaTitle, position: Double, duration: Double, season: Int?, episode: Int?) {
        guard position.isFinite, duration.isFinite, duration > 0, position > 3 else { return }
        progress.removeAll { $0.id == title.id }
        if position / duration < 0.96 {
            progress.insert(WatchProgress(title: title, position: position, duration: duration, season: season, episode: episode, updatedAt: Date()), at: 0)
        }
        progress = Array(progress.prefix(60))
        if let data = try? JSONEncoder().encode(progress) { defaults.set(data, forKey: "watched.progress") }
    }
}

@MainActor
final class CatalogStore: ObservableObject {
    @Published private(set) var items: [MediaTitle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var usingSavedCopy = false
    private var nextPage = 1
    private var hasMore = true
    private var requestID = UUID()

    func load(kind: MediaKind, filters: CatalogFilters, fallback: [MediaTitle], preview: Bool) async {
        let identity = UUID(); requestID = identity
        isLoading = true; error = nil; usingSavedCopy = false; nextPage = 1; hasMore = true
        defer { if requestID == identity { isLoading = false } }
        if preview {
            items = local(kind: kind, filters: filters, items: fallback); hasMore = false; return
        }
        do {
            let page = try await WatchedClient.shared.catalog(kind: kind, filters: filters, page: 1)
            guard identity == requestID else { return }
            items = page.items; nextPage = page.page + 1; hasMore = page.page < page.totalPages
        } catch is CancellationError { }
        catch {
            guard identity == requestID else { return }
            items = local(kind: kind, filters: filters, items: fallback)
            usingSavedCopy = true; hasMore = false
            self.error = error.localizedDescription
        }
    }

    func more(kind: MediaKind, filters: CatalogFilters) async {
        guard !isLoading, hasMore else { return }
        let identity = requestID
        isLoading = true
        defer { if identity == requestID { isLoading = false } }
        do {
            let page = try await WatchedClient.shared.catalog(kind: kind, filters: filters, page: nextPage)
            guard identity == requestID else { return }
            var seen = Set(items.map(\.id))
            items += page.items.filter { seen.insert($0.id).inserted }
            nextPage = page.page + 1; hasMore = page.page < page.totalPages
        } catch is CancellationError { }
        catch { if identity == requestID { self.error = error.localizedDescription } }
    }

    private func local(kind: MediaKind, filters: CatalogFilters, items: [MediaTitle]) -> [MediaTitle] {
        var result = items.filter { $0.kind == kind }
        if !filters.query.isEmpty {
            result = result.filter { $0.name.localizedStandardContains(filters.query) || $0.overview.localizedStandardContains(filters.query) }
        }
        if let id = filters.genreID, let genre = (kind == .movie ? GenreOption.all : GenreOption.shows).first(where: { $0.id == id }) {
            result = result.filter { $0.genres.contains(genre.english) }
        }
        if filters.providerID != nil { result = [] } // Provider membership cannot be inferred from a saved homepage.
        if filters.sort == "vote_average.desc" { result.sort { $0.rating > $1.rating } }
        else if filters.sort.hasSuffix(".desc"), filters.sort != "popularity.desc" { result.sort { ($0.releaseDate ?? "") > ($1.releaseDate ?? "") } }
        return result
    }
}

struct GenreOption: Identifiable {
    let id: Int
    let arabic: String
    let english: String
    static let all: [GenreOption] = [
        .init(id: 28, arabic: "أكشن", english: "Action"), .init(id: 12, arabic: "مغامرات", english: "Adventure"),
        .init(id: 16, arabic: "أنيميشن", english: "Animation"), .init(id: 35, arabic: "كوميديا", english: "Comedy"),
        .init(id: 80, arabic: "جريمة", english: "Crime"), .init(id: 18, arabic: "دراما", english: "Drama"),
        .init(id: 27, arabic: "رعب", english: "Horror"), .init(id: 9648, arabic: "غموض", english: "Mystery"),
        .init(id: 10749, arabic: "رومانسي", english: "Romance"), .init(id: 878, arabic: "خيال علمي", english: "Science Fiction"),
        .init(id: 53, arabic: "إثارة", english: "Thriller")
    ]
    static let shows: [GenreOption] = [
        .init(id: 10759, arabic: "أكشن ومغامرات", english: "Action & Adventure"),
        .init(id: 16, arabic: "أنيميشن", english: "Animation"), .init(id: 35, arabic: "كوميديا", english: "Comedy"),
        .init(id: 80, arabic: "جريمة", english: "Crime"), .init(id: 18, arabic: "دراما", english: "Drama"),
        .init(id: 9648, arabic: "غموض", english: "Mystery"), .init(id: 10765, arabic: "خيال علمي وفانتازيا", english: "Sci-Fi & Fantasy")
    ]
}
