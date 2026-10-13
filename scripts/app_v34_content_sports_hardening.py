from pathlib import Path
import re

# V34: strict anime safety + live sports playback hardening.
# This runs in CI after the stable player patches and before XcodeGen.

# -----------------------------------------------------------------------------
# 1) Strict anime safety filtering
# -----------------------------------------------------------------------------
tmdb_path = Path("FrameNative/Services/TMDBClient.swift")
text = tmdb_path.read_text(encoding="utf-8")

anime_pattern = re.compile(r'''    func anime\(page: Int = 1\) async throws -> \[MediaItem\] \{.*?\n    \}\n\n    func popularMovies''', re.S)
anime_replacement = r'''    func anime(page: Int = 1) async throws -> [MediaItem] {
        let response = try await request(path: "/discover/tv", query: [
            .init(name: "language", value: language),
            .init(name: "page", value: String(page)),
            .init(name: "sort_by", value: "popularity.desc"),
            .init(name: "with_genres", value: "16"),
            .init(name: "with_original_language", value: "ja"),
            .init(name: "include_adult", value: "false")
        ], as: ListResponse.self)

        let candidates: [(Int, MediaItem)] = response.results.enumerated().compactMap { index, result in
            guard result.adult != true else { return nil }
            let summary = [result.title, result.name, result.overview].compactMap { $0 }.joined(separator: " ")
            guard !AnimeSafety.containsBlockedTerms(summary) else { return nil }
            guard let item = result.mediaItem(forcedKind: .anime) else { return nil }
            return (index, MediaItem(
                tmdbID: item.tmdbID,
                kind: .anime,
                title: item.title,
                overview: item.overview,
                posterPath: item.posterPath,
                backdropPath: item.backdropPath,
                releaseDate: item.releaseDate,
                voteAverage: item.voteAverage,
                genreIDs: item.genreIDs
            ))
        }

        return await withTaskGroup(of: (Int, MediaItem?).self, returning: [MediaItem].self) { group in
            for (index, item) in candidates {
                group.addTask {
                    let isAllowed = (try? await animeSafetyAllows(id: item.tmdbID)) ?? false
                    return (index, isAllowed ? item : nil)
                }
            }

            var accepted: [(Int, MediaItem)] = []
            for await (index, item) in group {
                if let item { accepted.append((index, item)) }
            }
            return accepted.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    func popularMovies'''
text, count = anime_pattern.subn(anime_replacement, text, count=1)
if count != 1:
    raise SystemExit("V34: could not replace anime() implementation")

request_anchor = '''    private func request<T: Decodable>(path: String, query: [URLQueryItem], as type: T.Type) async throws -> T {'''
if request_anchor not in text:
    raise SystemExit("V34: TMDB request anchor missing")
helper = r'''    private func animeSafetyAllows(id: Int) async throws -> Bool {
        let response = try await request(path: "/tv/\(id)", query: [
            .init(name: "language", value: "en-US"),
            .init(name: "append_to_response", value: "content_ratings,keywords")
        ], as: AnimeSafetyResponse.self)

        guard response.adult != true else { return false }

        let descriptiveText = [response.name, response.overview]
            .compactMap { $0 }
            .joined(separator: " ")
        guard !AnimeSafety.containsBlockedTerms(descriptiveText) else { return false }

        let keywordText = (response.keywords?.results ?? [])
            .map(\.name)
            .joined(separator: " ")
        guard !AnimeSafety.containsBlockedTerms(keywordText) else { return false }

        let ratings = response.contentRatings?.results ?? []
        guard !ratings.contains(where: { AnimeSafety.isMatureRating($0.rating) }) else { return false }
        guard response.contentRatings != nil || response.keywords != nil else { return false }
        return true
    }

'''
text = text.replace(request_anchor, helper + request_anchor, 1)

old_fields = '''    let mediaType: String?\n    let originalLanguage: String?\n'''.replace('\\n', '\n')
new_fields = '''    let mediaType: String?\n    let originalLanguage: String?\n    let adult: Bool?\n'''.replace('\\n', '\n')
if old_fields not in text:
    raise SystemExit("V34: ListResult field anchor missing")
text = text.replace(old_fields, new_fields, 1)

old_coding = '''        case mediaType = "media_type"\n        case originalLanguage = "original_language"\n'''.replace('\\n', '\n')
new_coding = '''        case mediaType = "media_type"\n        case originalLanguage = "original_language"\n        case adult\n'''.replace('\\n', '\n')
if old_coding not in text:
    raise SystemExit("V34: ListResult CodingKeys anchor missing")
text = text.replace(old_coding, new_coding, 1)

old_media_item = '''    func mediaItem(forcedKind: MediaKind) -> MediaItem? {\n        let resolvedTitle = (title ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)\n'''.replace('\\n', '\n')
new_media_item = '''    func mediaItem(forcedKind: MediaKind) -> MediaItem? {\n        guard adult != true else { return nil }\n        let resolvedTitle = (title ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)\n'''.replace('\\n', '\n')
if old_media_item not in text:
    raise SystemExit("V34: mediaItem anchor missing")
text = text.replace(old_media_item, new_media_item, 1)

old_search_case = '''            case "movie": return result.mediaItem(forcedKind: .movie)\n            case "tv": return result.mediaItem(forcedKind: result.isLikelyAnime ? .anime : .tv)\n            default: return nil\n'''.replace('\\n', '\n')
new_search_case = '''            case "movie": return result.mediaItem(forcedKind: .movie)\n            case "tv":\n                if result.isLikelyAnime {\n                    let summary = [result.title, result.name, result.overview].compactMap { $0 }.joined(separator: " ")\n                    guard !AnimeSafety.containsBlockedTerms(summary) else { return nil }\n                    return result.mediaItem(forcedKind: .anime)\n                }\n                return result.mediaItem(forcedKind: .tv)\n            default: return nil\n'''.replace('\\n', '\n')
if old_search_case not in text:
    raise SystemExit("V34: search anime branch anchor missing")
text = text.replace(old_search_case, new_search_case, 1)

safety_anchor = '''private struct DetailsResponse: Decodable {'''
if safety_anchor not in text:
    raise SystemExit("V34: DetailsResponse anchor missing")
safety_models = r'''private struct AnimeSafetyResponse: Decodable {
    let adult: Bool?
    let name: String?
    let overview: String?
    let contentRatings: AnimeContentRatings?
    let keywords: AnimeKeywords?

    enum CodingKeys: String, CodingKey {
        case adult, name, overview, keywords
        case contentRatings = "content_ratings"
    }
}

private struct AnimeContentRatings: Decodable {
    let results: [AnimeContentRating]
}

private struct AnimeContentRating: Decodable {
    let rating: String
}

private struct AnimeKeywords: Decodable {
    let results: [AnimeKeyword]
}

private struct AnimeKeyword: Decodable {
    let name: String
}

private enum AnimeSafety {
    private static let blockedTerms = [
        "hentai", "ecchi", "erotic", "erotica", "adult animation",
        "fanservice", "fan service", "nudity", "nude", "naked",
        "sexual content", "sexual humor", "sexual relationship", "sex scene",
        "pornography", "pornographic", "softcore", "uncensored",
        "lingerie", "panties", "underwear fetish", "bikini model",
        "harem", "incest", "brothel", "prostitution", "stripper", "fetish",
        "female nudity", "male nudity", "breasts", "boobs",
        "عري", "عارية", "عارٍ", "إباحي", "اباحي", "إباحية", "اباحية",
        "محتوى جنسي", "علاقة جنسية", "للكبار فقط", "إغراء"
    ]

    static func containsBlockedTerms(_ value: String) -> Bool {
        let normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return blockedTerms.contains { normalized.contains($0) }
    }

    static func isMatureRating(_ value: String) -> Bool {
        let rating = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if rating.isEmpty { return false }
        if rating.contains("18") || rating.contains("R21") || rating.contains("21+") { return true }
        return ["TV-MA", "NC-17", "X", "R18", "R18+", "MA15+", "M18"].contains(rating)
    }
}

'''
text = text.replace(safety_anchor, safety_models + safety_anchor, 1)

tmdb_path.write_text(text, encoding="utf-8")
print("V34 anime safety hardening applied")

# -----------------------------------------------------------------------------
# 2) Sports playback: robust VLC clocking + auto-hiding chrome
# -----------------------------------------------------------------------------
sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
sports = sports_path.read_text(encoding="utf-8")

old_extensions = '''        var extensions: [String] = []\n        if let providerExt = stream.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !providerExt.isEmpty {\n            extensions.append(providerExt)\n        }\n        for ext in ["ts", "m3u8"] where !extensions.contains(ext) {\n            extensions.append(ext)\n        }\n'''.replace('\\n', '\n')
new_extensions = '''        var extensions: [String] = ["ts"]\n        if let providerExt = stream.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !providerExt.isEmpty, !extensions.contains(providerExt) {\n            extensions.append(providerExt)\n        }\n        if !extensions.contains("m3u8") { extensions.append("m3u8") }\n'''.replace('\\n', '\n')
if old_extensions not in sports:
    raise SystemExit("V34: sports extension order anchor missing")
sports = sports.replace(old_extensions, new_extensions, 1)

old_controls_state = '''    @StateObject private var model: XSSportsVLCPlayerModel\n    @State private var controlsVisible = true\n'''.replace('\\n', '\n')
new_controls_state = '''    @StateObject private var model: XSSportsVLCPlayerModel\n    @State private var controlsVisible = true\n    @State private var controlsHideTask: Task<Void, Never>?\n'''.replace('\\n', '\n')
if old_controls_state not in sports:
    raise SystemExit("V34: sports controls state anchor missing")
sports = sports.replace(old_controls_state, new_controls_state, 1)

old_tap = '''                .onTapGesture {\n                    withAnimation(.easeOut(duration: 0.15)) { controlsVisible.toggle() }\n                }\n'''.replace('\\n', '\n')
new_tap = '''                .onTapGesture {\n                    withAnimation(.easeOut(duration: 0.15)) { controlsVisible.toggle() }\n                    if controlsVisible { scheduleControlsHide() } else { controlsHideTask?.cancel() }\n                }\n'''.replace('\\n', '\n')
if old_tap not in sports:
    raise SystemExit("V34: sports tap anchor missing")
sports = sports.replace(old_tap, new_tap, 1)

old_lifecycle = '''        .onAppear { model.start() }\n        .onDisappear { model.stop() }\n    }\n\n    private var playerChrome: some View {\n'''.replace('\\n', '\n')
new_lifecycle = '''        .onAppear {\n            model.start()\n            controlsVisible = true\n            scheduleControlsHide()\n        }\n        .onDisappear {\n            controlsHideTask?.cancel()\n            model.stop()\n        }\n        .onChange(of: controlsVisible) { visible in\n            if visible { scheduleControlsHide() } else { controlsHideTask?.cancel() }\n        }\n    }\n\n    private func scheduleControlsHide() {\n        controlsHideTask?.cancel()\n        controlsHideTask = Task { @MainActor in\n            try? await Task.sleep(nanoseconds: 2_700_000_000)\n            guard !Task.isCancelled else { return }\n            withAnimation(.easeOut(duration: 0.18)) { controlsVisible = false }\n        }\n    }\n\n    private var playerChrome: some View {\n'''.replace('\\n', '\n')
if old_lifecycle not in sports:
    raise SystemExit("V34: sports lifecycle anchor missing")
sports = sports.replace(old_lifecycle, new_lifecycle, 1)

sports = sports.replace('''Button { model.reload() } label: {''', '''Button { model.reload(); scheduleControlsHide() } label: {''', 1)
sports = sports.replace('''                                    model.play(index: index)''', '''                                    model.play(index: index)\n                                    scheduleControlsHide()'''.replace('\\n', '\n'), 1)
sports = sports.replace('''Button { model.togglePlayPause() } label: {''', '''Button { model.togglePlayPause(); scheduleControlsHide() } label: {''', 1)

old_player_decl = '''    let player = VLCMediaPlayer()\n    let urls: [URL]\n'''.replace('\\n', '\n')
new_player_decl = '''    let player: VLCMediaPlayer\n    let urls: [URL]\n'''.replace('\\n', '\n')
if old_player_decl not in sports:
    raise SystemExit("V34: VLC player declaration anchor missing")
sports = sports.replace(old_player_decl, new_player_decl, 1)

old_init = '''    init(urls: [URL]) {\n        self.urls = urls\n        super.init()\n        player.delegate = self\n    }\n'''.replace('\\n', '\n')
new_init = '''    init(urls: [URL]) {\n        self.urls = urls\n        self.player = VLCMediaPlayer(options: [\n            "--network-caching=1400",\n            "--live-caching=1400",\n            "--clock-jitter=0",\n            "--clock-synchro=0",\n            "--drop-late-frames",\n            "--skip-frames",\n            "--avcodec-hw=any"\n        ])\n        super.init()\n        player.delegate = self\n        player.rate = 1.0\n    }\n'''.replace('\\n', '\n')
if old_init not in sports:
    raise SystemExit("V34: VLC model init anchor missing")
sports = sports.replace(old_init, new_init, 1)

old_media = '''        player.stop()\n        player.media = VLCMedia(url: urls[index])\n        player.play()\n'''.replace('\\n', '\n')
new_media = '''        player.stop()\n        let media = VLCMedia(url: urls[index])\n        media.addOptions([\n            "network-caching": 1400 as NSNumber,\n            "live-caching": 1400 as NSNumber,\n            "clock-jitter": 0 as NSNumber,\n            "clock-synchro": 0 as NSNumber\n        ])\n        player.media = media\n        player.rate = 1.0\n        player.play()\n'''.replace('\\n', '\n')
if old_media not in sports:
    raise SystemExit("V34: VLC media assignment anchor missing")
sports = sports.replace(old_media, new_media, 1)

old_time_update = '''            if self.player.isPlaying {\n                self.statusText = "Live"\n                self.isPlaying = true\n                self.fallbackTask?.cancel()\n            }\n'''.replace('\\n', '\n')
new_time_update = '''            if self.player.isPlaying {\n                if abs(self.player.rate - 1.0) > 0.01 { self.player.rate = 1.0 }\n                self.statusText = "Live"\n                self.isPlaying = true\n                self.fallbackTask?.cancel()\n            }\n'''.replace('\\n', '\n')
if old_time_update not in sports:
    raise SystemExit("V34: VLC time update anchor missing")
sports = sports.replace(old_time_update, new_time_update, 1)

old_playing_state = '''        if state == .playing {\n            statusText = "Live"\n            isPlaying = true\n            fallbackTask?.cancel()\n'''.replace('\\n', '\n')
new_playing_state = '''        if state == .playing {\n            player.rate = 1.0\n            statusText = "Live"\n            isPlaying = true\n            fallbackTask?.cancel()\n'''.replace('\\n', '\n')
if old_playing_state not in sports:
    raise SystemExit("V34: VLC playing state anchor missing")
sports = sports.replace(old_playing_state, new_playing_state, 1)

sports_path.write_text(sports, encoding="utf-8")
print("V34 sports playback hardening applied")
