import Foundation
import SwiftUI

// Only streams from Internet Archive items with explicit CC-BY, CC-BY-SA,
// CC0 licenses are indexed. Metadata alone cannot prove copyright ownership;
// every title links to the item's rights page for attribution and review.
// There are NO third-party subscription / IPTV VOD / pirate-torrent requests.

enum XSOpenShelf: String, Codable, CaseIterable, Identifiable, Sendable {
    case movies = "movies"
    case series = "series"
    var id: String { rawValue }
    var title: String { self == .movies ? "الأفلام" : "المسلسلات" }
}

struct XSOpenTitle: Codable, Hashable, Identifiable, Sendable {
    let identifier: String
    let name: String
    let details: String
    let shelf: XSOpenShelf
    let licenseURL: String
    let movieFilename: String
    let thumbnailURLString: String?
    let subtitleFilename: String?
    var id: String { identifier }
    var thumbnail: URL? { thumbnailURLString.flatMap(URL.init(string:)) }
    var playableURL: URL? {
        guard let encoded = movieFilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://archive.org/download/\(identifier)/\(encoded)")
    }
    var sourceURL: URL? { URL(string: "https://archive.org/details/\(identifier)") }
    var hasArabicSubtitleFile: Bool { subtitleFilename != nil }
}

enum XSOpenSourceError: LocalizedError {
    case network, format
    var errorDescription: String? {
        switch self {
        case .network: return "تعذر الاتصال بمكتبة الأفلام المفتوحة. حاول مرة ثانية."
        case .format: return "المصدر لم يرجع بيانات فيديو صالحة."
        }
    }
}

actor XSOpenCinemaAPI {
    static let shared = XSOpenCinemaAPI()

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 28
        config.httpMaximumConnectionsPerHost = 5
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    private func get(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue("XS-TV-OpenCinema/1.0", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode), !bytes.isEmpty else {
            throw XSOpenSourceError.network
        }
        guard let json = try JSONSerialization.jsonObject(with: bytes)
                as? [String: Any] else { throw XSOpenSourceError.format }
        return json
    }

    private func searchIDs(shelf: XSOpenShelf, page: Int) async throws -> [String] {
        var url = URLComponents(string: "https://archive.org/advancedsearch.php")!
        // Archive documents explicit licenseurl search; accept only open
        // derivatives/redistribution licenses after fetching metadata.
        let folderFilter = shelf == .series
           ? " AND (collection:classic_tv OR subject:episodes OR title:episode)"
           : " AND NOT collection:classic_tv"
        url.queryItems = [
            URLQueryItem(name: "q", value: "mediatype:movies AND licenseurl:http*" + folderFilter),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "rows", value: "34"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "sort[]", value: "downloads desc"),
            URLQueryItem(name: "output", value: "json")
        ]
        guard let endpoint = url.url else { throw XSOpenSourceError.format }
        let body = try await get(endpoint)
        let response = body["response"] as? [String: Any] ?? [:]
        let docs = response["docs"] as? [[String: Any]] ?? []
        return docs.compactMap { $0["identifier"] as? String }
            .filter { !$0.isEmpty && $0.range(of: #"^[a-zA-Z0-9._-]+$"#,
                                                  options: .regularExpression) != nil }
    }

    private func allowedLicense(_ raw: String) -> Bool {
        let text = raw.lowercased().replacingOccurrences(of: "https://", with: "http://")
        return text.contains("creativecommons.org/licenses/by/") ||
            text.contains("creativecommons.org/licenses/by-sa/") ||
            text.contains("creativecommons.org/publicdomain/zero/")
    }

    private func bestVideoFile(in files: [[String: Any]]) -> String? {
        let choices = files.compactMap { file -> (String, Int)? in
            guard let name = file["name"] as? String else { return nil }
            let lower = name.lowercased()
            guard [".mp4", ".m4v", ".webm", ".mkv"].contains(where: lower.hasSuffix) else {
                return nil
            }
            // Prefer streams around 720p, not multi-GB masters.
            let size = Int(file["size"] as? String ?? "") ?? 0
            guard size > 5_000_000, size < 3_000_000_000 else { return nil }
            let nameScore = lower.contains("720") ? 5 : (lower.contains("480") ? 3 : 0)
            let mp4Score = lower.hasSuffix(".mp4") ? 20 : 0
            let derivedPenalty = lower.contains("thumb") || lower.contains("sample") ? -20 : 0
            let sizePenalty = size > 1_200_000_000 ? -5 : 0
            return (name, nameScore + mp4Score + derivedPenalty + sizePenalty)
        }
        return choices.max(by: { $0.1 < $1.1 })?.0
    }

    private func subtitleFile(for filename: String, files: [[String: Any]]) -> String? {
        let basename = (filename as NSString).deletingPathExtension.lowercased()
        return files.compactMap { $0["name"] as? String }
            .first { file in
                let f = file.lowercased()
                guard f.hasSuffix(".srt") || f.hasSuffix(".vtt") else { return false }
                return (f.contains(".ar.") || f.contains(".ara.") ||
                        f.contains("_arabic") || f.contains(".arabic.")) &&
                       f.hasPrefix(basename.prefix(12).lowercased())
            }
    }

    private func item(_ identifier: String, shelf: XSOpenShelf) async -> XSOpenTitle? {
        guard let escaped = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://archive.org/metadata/\(escaped)"),
              let body = try? await get(url),
              let metadata = body["metadata"] as? [String: Any],
              let files = body["files"] as? [[String: Any]] else { return nil }
        let license = metadata["licenseurl"] as? String ?? ""
        guard allowedLicense(license), let video = bestVideoFile(in: files) else { return nil }
        let title = (metadata["title"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? identifier
        guard !title.isEmpty else { return nil }
        var desc = ""
        if let raw = metadata["description"] as? String {
            desc = raw.replacingOccurrences(of: "<[^>]+>", with: " ",
                                            options: .regularExpression)
        }
        let thumb = files.compactMap { $0["name"] as? String }.first {
            let lower = $0.lowercased()
            return lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png")
        }.flatMap { filename -> String? in
            guard let escapedFile = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            else { return nil }
            return "https://archive.org/download/\(identifier)/\(escapedFile)"
        }
        return XSOpenTitle(identifier: identifier, name: title, details: String(desc.prefix(1200)),
                           shelf: shelf, licenseURL: license, movieFilename: video,
                           thumbnailURLString: thumb,
                           subtitleFilename: subtitleFile(for: video, files: files))
    }

    func discover(shelf: XSOpenShelf, page: Int = 1) async throws -> [XSOpenTitle] {
        let ids = try await searchIDs(shelf: shelf, page: page)
        guard !ids.isEmpty else { return [] }
        var gathered: [XSOpenTitle] = []
        // Bound metadata requests to 4 at once to avoid provider throttling.
        for start in stride(from: 0, to: ids.count, by: 4) {
            let end = min(start + 4, ids.count)
            let chunk = Array(ids[start..<end])
            let titles = await withTaskGroup(of: XSOpenTitle?.self,
                                            returning: [XSOpenTitle].self) { group in
                for id in chunk {
                    group.addTask { await self.item(id, shelf: shelf) }
                }
                var result: [XSOpenTitle] = []
                for await item in group { if let item { result.append(item) } }
                return result
            }
            gathered.append(contentsOf: titles)
        }
        return gathered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class XSOpenCinemaStore: ObservableObject {
    @Published private(set) var movies: [XSOpenTitle] = []
    @Published private(set) var series: [XSOpenTitle] = []
    @Published private(set) var loading: Set<XSOpenShelf> = []
    @Published private(set) var messages: [XSOpenShelf: String] = [:]
    @Published private(set) var favorites = Set<String>()
    private var restored = false
    private let favoriteKey = "XSTV.OpenCinema.favorites"
    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? [])
    }

    func items(_ shelf: XSOpenShelf) -> [XSOpenTitle] {
        shelf == .movies ? movies : series
    }

    func isFavorite(_ item: XSOpenTitle) -> Bool { favorites.contains(item.id) }

    func toggle(_ item: XSOpenTitle) {
        if !favorites.insert(item.id).inserted { favorites.remove(item.id) }
        UserDefaults.standard.set(Array(favorites), forKey: favoriteKey)
    }

    private func snapshotURL(_ shelf: XSOpenShelf) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("xs-open-cinema-\(shelf.rawValue).json")
    }

    func start() async {
        if !restored {
            restored = true
            for shelf in XSOpenShelf.allCases {
                guard let path = snapshotURL(shelf) else { continue }
                let cached = await Task.detached(priority: .utility) { () -> [XSOpenTitle] in
                    guard let data = try? Data(contentsOf: path),
                          let list = try? JSONDecoder().decode([XSOpenTitle].self, from: data)
                    else { return [] }
                    return list
                }.value
                if !cached.isEmpty { assign(cached, shelf: shelf) }
            }
        }
        for shelf in XSOpenShelf.allCases where items(shelf).isEmpty {
            Task { await refresh(shelf) }
        }
    }

    func refresh(_ shelf: XSOpenShelf) async {
        guard !loading.contains(shelf) else { return }
        loading.insert(shelf)
        messages[shelf] = nil
        defer { loading.remove(shelf) }
        do {
            let list = try await XSOpenCinemaAPI.shared.discover(shelf: shelf)
            if !list.isEmpty {
                assign(list, shelf: shelf)
                if let path = snapshotURL(shelf) {
                    Task.detached(priority: .utility) {
                        if let data = try? JSONEncoder().encode(list) {
                            try? data.write(to: path, options: .atomic)
                        }
                    }
                }
            } else if items(shelf).isEmpty {
                messages[shelf] = "ما ظهرت أعمال مرخّصة قابلة للتشغيل بهذا القسم حالياً."
            }
        } catch {
            messages[shelf] = XSOpenSourceError.network.localizedDescription
        }
    }

    func search(_ phrase: String, shelf: XSOpenShelf? = nil) -> [XSOpenTitle] {
        guard !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let source = shelf.map(items) ?? (movies + series)
        return source.filter { $0.name.localizedStandardContains(phrase) }
    }

    private func assign(_ list: [XSOpenTitle], shelf: XSOpenShelf) {
        if shelf == .movies { movies = list }
        else { series = list }
    }
}
