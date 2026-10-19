import Foundation
import SwiftUI

// Febbox alone decides which movies, folders, seasons and files exist.
// This model deliberately carries no IMDB/TMDB or legacy-player identifier.
struct XSFebboxIndexedItem: Codable, Hashable, Identifiable, Sendable {
    let shelf: XSFebboxShelf
    let fid: String
    let parentID: String
    let filename: String
    let isDirectory: Bool
    let fileExtension: String
    let sizeBytes: Int64
    let durationSeconds: Double
    let thumbnailString: String?
    let folderTrail: [String]
    let discoveryIndex: Int

    var id: String { shelf.rawValue + ":" + fid }
    var thumbnail: URL? { thumbnailString.flatMap(URL.init(string:)) }
    var entry: XSFebboxEntry {
        XSFebboxEntry(shelf: shelf, fid: fid, parentID: parentID,
                      filename: filename, isDirectory: isDirectory,
                      fileExtension: fileExtension, sizeBytes: sizeBytes,
                      durationSeconds: durationSeconds, thumbnail: thumbnail)
    }

    var displayTitle: String {
        let raw = entry.name
        let expanded = raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        return expanded.replacingOccurrences(of: #" + "#,
                     with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isPlayable: Bool { entry.playable }
    var isSubtitle: Bool { entry.subtitles }

    init(entry: XSFebboxEntry, trail: [String], index: Int) {
        shelf = entry.shelf
        fid = entry.fid
        parentID = entry.parentID
        filename = entry.filename
        isDirectory = entry.isDirectory
        fileExtension = entry.fileExtension
        sizeBytes = entry.sizeBytes
        durationSeconds = entry.durationSeconds
        thumbnailString = entry.thumbnail?.absoluteString
        folderTrail = trail
        discoveryIndex = index
    }
}

@MainActor
final class XSFebboxCatalogStore: ObservableObject {
    @Published private(set) var movies: [XSFebboxIndexedItem] = []
    @Published private(set) var series: [XSFebboxIndexedItem] = []
    @Published private(set) var scanning: Set<XSFebboxShelf> = []
    @Published private(set) var failed: [XSFebboxShelf: String] = [:]
    @Published private(set) var completed: Set<XSFebboxShelf> = []
    @Published private(set) var favoriteIDs = Set<String>()
    @Published private(set) var recent: [XSFebboxIndexedItem] = []

    private var started = Set<XSFebboxShelf>()
    private var scans: [XSFebboxShelf: Task<Void, Never>] = [:]
    private var index: [XSFebboxShelf: Set<String>] = [:]
    private let favoritesKey = "XSFebboxPrimary.favoriteIDs.v1"
    private let recentKey = "XSFebboxPrimary.recent.v1"

    init() {
        favoriteIDs = Set(UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [])
        if let data = UserDefaults.standard.data(forKey: recentKey),
           let entries = try? JSONDecoder().decode([XSFebboxIndexedItem].self, from: data) {
            recent = entries
        }
        for shelf in XSFebboxShelf.allCases {
            if let url = snapshotURL(for: shelf),
               let data = try? Data(contentsOf: url),
               let entries = try? JSONDecoder().decode([XSFebboxIndexedItem].self, from: data) {
                assign(entries, to: shelf)
                index[shelf] = Set(entries.map(\.id))
            }
        }
    }

    func items(for shelf: XSFebboxShelf) -> [XSFebboxIndexedItem] {
        shelf == .movies ? movies : series
    }

    func children(shelf: XSFebboxShelf, parentID: String) -> [XSFebboxIndexedItem] {
        items(for: shelf).filter { $0.parentID == parentID }
    }

    func root(shelf: XSFebboxShelf) -> [XSFebboxIndexedItem] {
        children(shelf: shelf, parentID: "0")
    }

    func find(id: String) -> XSFebboxIndexedItem? {
        (movies + series).first { $0.id == id }
    }

    func artwork(for item: XSFebboxIndexedItem) -> URL? {
        if let thumbnail = item.thumbnail { return thumbnail }
        guard item.isDirectory else { return nil }
        let all = items(for: item.shelf)
        var folderIDs = [item.fid]
        var visited = Set(folderIDs)
        var cursor = 0
        while cursor < folderIDs.count {
            let folder = folderIDs[cursor]
            for child in all where child.parentID == folder {
                if let thumb = child.thumbnail { return thumb }
                if child.isDirectory && visited.insert(child.fid).inserted {
                    folderIDs.append(child.fid)
                }
            }
            cursor += 1
            if cursor > 200 { break } // artwork optimization, not an indexing limit
        }
        return nil
    }

    func search(_ term: String, shelf: XSFebboxShelf? = nil) -> [XSFebboxIndexedItem] {
        let q = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let all = shelf.map(items(for:)) ?? (movies + series)
        return all.filter { $0.displayTitle.localizedStandardContains(q) }
            .sorted { $0.isDirectory && !$1.isDirectory }
    }

    func isFavorite(_ item: XSFebboxIndexedItem) -> Bool { favoriteIDs.contains(item.id) }

    func toggleFavorite(_ item: XSFebboxIndexedItem) {
        if !favoriteIDs.insert(item.id).inserted {
            favoriteIDs.remove(item.id)
        }
        UserDefaults.standard.set(Array(favoriteIDs), forKey: favoritesKey)
    }

    func opened(_ item: XSFebboxIndexedItem) {
        recent.removeAll { $0.id == item.id }
        recent.insert(item, at: 0)
        if recent.count > 50 { recent.removeLast(recent.count - 50) }
        if let encoded = try? JSONEncoder().encode(recent) {
            UserDefaults.standard.set(encoded, forKey: recentKey)
        }
    }

    func startIfNeeded() {
        for shelf in XSFebboxShelf.allCases where !started.contains(shelf) {
            refresh(shelf)
        }
    }

    func refresh(_ shelf: XSFebboxShelf) {
        scans[shelf]?.cancel()
        started.insert(shelf)
        completed.remove(shelf)
        failed[shelf] = nil
        scanning.insert(shelf)
        scans[shelf] = Task { [weak self] in
            guard let self else { return }
            await self.discover(shelf)
        }
    }

    private struct Folder {
        let fid: String
        let trail: [String]
    }

    // Scan all pages of every reachable shared folder; no fake title inventory,
    // no arbitrary "first 100" cutoff. Publish batches while loading so the UI
    // works immediately even for large catalogs.
    private func discover(_ shelf: XSFebboxShelf) async {
        var queue = [Folder(fid: "0", trail: [])]
        var visited = Set<String>()
        var all: [XSFebboxIndexedItem] = []
        var seen = Set<String>()
        var firstError: String?
        var cursor = 0
        while cursor < queue.count && !Task.isCancelled {
            let folder = queue[cursor]
            cursor += 1
            guard visited.insert(folder.fid).inserted else { continue }

            var number = 1
            while !Task.isCancelled {
                do {
                    let page = try await XSFebboxLibraryService.shared.page(
                        shelf: shelf, parent: folder.fid, number: number)
                    for entry in page.entries where seen.insert(entry.id).inserted {
                        let item = XSFebboxIndexedItem(entry: entry,
                                                       trail: folder.trail,
                                                       index: all.count)
                        all.append(item)
                        if entry.isDirectory {
                            queue.append(Folder(fid: entry.fid,
                                                trail: folder.trail + [entry.name]))
                        }
                    }
                    // Refresh a visible page without waiting for the entire scan.
                    if folder.fid == "0" || all.count % 50 == 0 || !page.hasNext {
                        assign(all, to: shelf)
                    }
                    guard page.hasNext && !page.entries.isEmpty else { break }
                    number += 1
                } catch {
                    if firstError == nil { firstError = error.localizedDescription }
                    break // One inaccessible folder never hides all other folders.
                }
            }
        }

        guard !Task.isCancelled else { return }
        assign(all, to: shelf)
        index[shelf] = seen
        if let error = firstError { failed[shelf] = error }
        else { completed.insert(shelf) }
        scanning.remove(shelf)
        saveSnapshot(all, shelf: shelf)
    }

    private func assign(_ list: [XSFebboxIndexedItem], to shelf: XSFebboxShelf) {
        if shelf == .movies { movies = list }
        else { series = list }
    }

    private func snapshotURL(for shelf: XSFebboxShelf) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("xs-febbox-" + shelf.rawValue + ".json")
    }

    private func saveSnapshot(_ list: [XSFebboxIndexedItem], shelf: XSFebboxShelf) {
        guard let url = snapshotURL(for: shelf),
              let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
