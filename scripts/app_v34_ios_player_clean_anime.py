from pathlib import Path
import re

sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
tmdb_path = Path("FrameNative/Services/TMDBClient.swift")

sports = sports_path.read_text(encoding="utf-8")
tmdb = tmdb_path.read_text(encoding="utf-8")

# --- Sports player chrome: keep VLC decoding (the working backend) but make the
# controls feel like the compact native iOS video player instead of a custom IPTV UI.
start = sports.find("    private var playerChrome: some View {")
end_marker = "\n}\n\n@MainActor\nprivate final class XSSportsVLCPlayerModel"
end = sports.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("Could not locate XSSportsPlayerV33 chrome block")

native_chrome = r'''    private var playerChrome: some View {
        ZStack {
            // Center control mirrors the compact iOS system-player treatment.
            Button {
                model.togglePlayPause()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 66, height: 66)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.36), radius: 16, y: 5)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel(model.isPlaying ? "Pause live channel" : "Play live channel")

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .accessibilityLabel("Close player")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stream.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.70))
                        }
                    }

                    Spacer(minLength: 12)

                    if urls.count > 1 {
                        Menu {
                            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                Button {
                                    model.play(index: index)
                                } label: {
                                    Label(
                                        index == model.currentIndex ? "Source \(index + 1) · Active" : "Source \(index + 1) · \(url.pathExtension.uppercased())",
                                        systemImage: index == model.currentIndex ? "checkmark.circle.fill" : "play.circle"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 40)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.14)))
                        }
                        .accessibilityLabel("Playback sources")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Spacer()

                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Circle().fill(model.statusText == "Live" ? Color.red : Color.orange)
                            .frame(width: 7, height: 7)
                        Text(model.statusText == "Live" ? "LIVE" : model.statusText.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.90))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12)))

                    Spacer()

                    Button { model.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .accessibilityLabel("Reload live channel")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }
'''

sports = sports[:start] + native_chrome + sports[end:]
sports_path.write_text(sports, encoding="utf-8")

# --- Clean anime filter.
old_anime = re.search(r'''    func anime\(page: Int = 1\) async throws -> \[MediaItem\] \{.*?\n    \}\n\n    func popularMovies''', tmdb, re.S)
if not old_anime:
    raise SystemExit("Could not locate TMDB anime() method")

new_anime = r'''    func anime(page: Int = 1) async throws -> [MediaItem] {
        let response = try await request(path: "/discover/tv", query: [
            .init(name: "language", value: language),
            .init(name: "page", value: String(page)),
            .init(name: "sort_by", value: "popularity.desc"),
            .init(name: "with_genres", value: "16"),
            .init(name: "with_original_language", value: "ja"),
            .init(name: "include_adult", value: "false")
        ], as: ListResponse.self)

        let candidates = response.results.compactMap { result -> MediaItem? in
            guard let item = result.mediaItem(forcedKind: .anime) else { return nil }
            return MediaItem(
                tmdbID: item.tmdbID,
                kind: .anime,
                title: item.title,
                overview: item.overview,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                releaseDate: item.releaseDate,
                voteAverage: item.voteAverage,
                genreIDs: item.genreIDs
            )
        }
        return await filterSafeAnime(candidates)
    }

    func popularMovies'''

tmdb = tmdb[:old_anime.start()] + new_anime + tmdb[old_anime.end():]

old_search = re.search(r'''    func search\(_ query: String, page: Int = 1\) async throws -> \[MediaItem\] \{.*?\n    \}\n\n    func details''', tmdb, re.S)
if not old_search:
    raise SystemExit("Could not locate TMDB search() method")

new_search = r'''    func search(_ query: String, page: Int = 1) async throws -> [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let response = try await request(path: "/search/multi", query: [
            .init(name: "query", value: trimmed),
            .init(name: "language", value: language),
            .init(name: "page", value: String(page)),
            .init(name: "include_adult", value: "false")
        ], as: ListResponse.self)
        let items = response.results.compactMap { result -> MediaItem? in
            guard let type = result.mediaType else { return nil }
            switch type {
            case "movie": return result.mediaItem(forcedKind: .movie)
            case "tv": return result.mediaItem(forcedKind: result.isLikelyAnime ? .anime : .tv)
            default: return nil
            }
        }
        return await filterUnsafeAnimeFromMixedResults(items)
    }

    func details'''

tmdb = tmdb[:old_search.start()] + new_search + tmdb[old_search.end():]

insert_anchor = "    private func request<T: Decodable>(path: String, query: [URLQueryItem], as type: T.Type) async throws -> T {"
if insert_anchor not in tmdb:
    raise SystemExit("Could not locate TMDB request() anchor")

safety_helpers = r'''    private func filterSafeAnime(_ items: [MediaItem]) async -> [MediaItem] {
        await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    let allowed = await animeSafetyAllows(item)
                    return (index, allowed ? item : nil)
                }
            }
            var accepted: [(Int, MediaItem)] = []
            for await (index, item) in group {
                if let item { accepted.append((index, item)) }
            }
            return accepted.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func filterUnsafeAnimeFromMixedResults(_ items: [MediaItem]) async -> [MediaItem] {
        await withTaskGroup(of: (Int, MediaItem?).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    guard item.kind == .anime else { return (index, item) }
                    let allowed = await animeSafetyAllows(item)
                    return (index, allowed ? item : nil)
                }
            }
            var accepted: [(Int, MediaItem)] = []
            for await (index, item) in group {
                if let item { accepted.append((index, item)) }
            }
            return accepted.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    private func animeSafetyAllows(_ item: MediaItem) async -> Bool {
        let localText = "\(item.title) \(item.overview)".lowercased()
        if AnimeSafetyPolicy.containsExplicitSexualMarker(localText) { return false }

        do {
            let response = try await request(
                path: "/tv/\(item.tmdbID)/keywords",
                query: [],
                as: TVKeywordsResponse.self
            )
            let keywordText = response.results.map(\.name).joined(separator: " ").lowercased()
            if AnimeSafetyPolicy.containsExplicitSexualMarker(keywordText) { return false }
        } catch {
            // Keep normal anime available if keyword metadata is temporarily unavailable.
        }

        do {
            let ratings = try await request(
                path: "/tv/\(item.tmdbID)/content_ratings",
                query: [],
                as: TVContentRatingsResponse.self
            )
            // Only block explicitly adult-only ratings. We intentionally do not block
            // every mature rating because the request is to remove sexual/nudity-heavy
            // anime while retaining otherwise normal titles.
            if ratings.results.contains(where: AnimeSafetyPolicy.isExplicitAdultRating) {
                return false
            }
        } catch {
            // Ratings are an extra safety signal, not a reason to break the catalog.
        }

        return true
    }

'''
tmdb = tmdb.replace(insert_anchor, safety_helpers + insert_anchor, 1)

append_anchor = "private struct ConfigurationResponse: Decodable {"
if append_anchor not in tmdb:
    raise SystemExit("Could not locate TMDB response structs anchor")

support_types = r'''private enum AnimeSafetyPolicy {
    // Deliberately narrow sexual/nudity terms: do not remove ordinary action,
    // horror, romance, or mature anime simply because of age rating alone.
    private static let blockedMarkers = [
        "hentai", "ecchi", "erotic", "erotica", "nudity", "nude scene",
        "sexual content", "sexuality", "sex comedy", "sexual humor",
        "sexualised", "sexualized", "fan service", "fanservice",
        "pornographic", "pornography", "adult animation"
    ]

    static func containsExplicitSexualMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return blockedMarkers.contains { normalized.contains($0) }
    }

    static func isExplicitAdultRating(_ item: TVContentRating) -> Bool {
        let value = item.rating.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch item.iso31661.uppercased() {
        case "JP": return ["R18+", "R18", "18+"].contains(value)
        case "DE": return ["18", "FSK 18"].contains(value)
        case "GB": return ["18", "R18"].contains(value)
        case "AU": return ["R18+", "X18+"].contains(value)
        default: return ["NC-17", "R18+", "X18+"].contains(value)
        }
    }
}

private struct TVKeywordsResponse: Decodable {
    let results: [TVKeyword]
}

private struct TVKeyword: Decodable {
    let id: Int
    let name: String
}

private struct TVContentRatingsResponse: Decodable {
    let results: [TVContentRating]
}

private struct TVContentRating: Decodable {
    let iso31661: String
    let rating: String
    enum CodingKeys: String, CodingKey {
        case iso31661 = "iso_3166_1"
        case rating
    }
}

'''
tmdb = tmdb.replace(append_anchor, support_types + append_anchor, 1)

tmdb_path.write_text(tmdb, encoding="utf-8")

print("V34 patch applied: iOS-style sports player chrome + clean anime safety filter")
