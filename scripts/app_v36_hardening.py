from pathlib import Path
import re

sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
tmdb_path = Path("FrameNative/Services/TMDBClient.swift")

sports = sports_path.read_text(encoding="utf-8")
tmdb = tmdb_path.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# V36 sports hardening
# - keep the VLC session alive during geometry/orientation transitions
# - force drawable detach/reattach when its bounds actually change
# - make tap chrome feel closer to the iOS player
# - shorten source failover without making live caching dangerously tiny
# ---------------------------------------------------------------------------

if "V36_ROTATION_HARDENING" not in sports:
    sports = "// V36_ROTATION_HARDENING: stable rotation lifecycle, forced VLC surface rebind, faster failover.\n" + sports

state_anchor = "    @State private var controlsHideTask: Task<Void, Never>?\n"
if state_anchor not in sports:
    raise SystemExit("V36: controls state anchor not found")
sports = sports.replace(
    state_anchor,
    state_anchor + "    @State private var isDismissingPlayer = false\n",
    1,
)

old_disappear = '''        .onDisappear {
            controlsHideTask?.cancel()
            model.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
'''
new_disappear = '''        .onDisappear {
            controlsHideTask?.cancel()
            // SwiftUI can transiently remount a full-screen hierarchy while the
            // device changes geometry. Only tear VLC down for a real close.
            if isDismissingPlayer {
                model.stop()
            }
        }
        .interactiveDismissDisabled()
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
'''
if old_disappear not in sports:
    raise SystemExit("V36: V35 lifecycle block not found")
sports = sports.replace(old_disappear, new_disappear, 1)

close_button = "                    Button { dismiss() } label: {"
if close_button not in sports:
    raise SystemExit("V36: sports close button anchor not found")
sports = sports.replace(close_button, "                    Button { closePlayer() } label: {", 1)

helper_anchor = "    private func toggleControlsFromCanvas() {\n"
if helper_anchor not in sports:
    raise SystemExit("V36: tap helper anchor not found")
close_helper = '''    private func closePlayer() {
        controlsHideTask?.cancel()
        isDismissingPlayer = true
        model.stop()
        dismiss()
    }

'''
sports = sports.replace(helper_anchor, close_helper + helper_anchor, 1)

# Standard player-like chrome: direct tap toggles it; while playing it fades
# sooner than before, while pausing keeps it visible.
sports = sports.replace(
    "            try? await Task.sleep(nanoseconds: 4_000_000_000)\n",
    "            try? await Task.sleep(nanoseconds: 3_200_000_000)\n",
    1,
)

# Rotation should never cause a source reload. The drawable bridge owns visual
# recovery; the player only resumes if VLC itself reports a non-user pause.
old_recovery = r'''    func recoverAfterSurfaceChange() {
        guard !userPaused, player.media != nil else { return }
        recoveryTask?.cancel()
        let myGeneration = generation
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                if !self.player.isPlaying {
                    self.player.play()
                }
            }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                if !self.player.isPlaying && self.player.state != .buffering {
                    self.reload()
                }
            }
        }
    }
'''
new_recovery = r'''    func recoverAfterSurfaceChange() {
        guard !userPaused, player.media != nil else { return }
        recoveryTask?.cancel()
        let myGeneration = generation
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                // Do not reload or change source during rotation. Re-loading a
                // healthy live stream is what caused some channels to vanish.
                if !self.player.isPlaying && self.player.state == .paused {
                    self.player.play()
                }
            }
        }
    }
'''
if old_recovery not in sports:
    raise SystemExit("V36: V35 recovery method not found")
sports = sports.replace(old_recovery, new_recovery, 1)

# Faster first picture/failover while retaining enough cache for normal mobile
# jitter. These are intentionally not ultra-low-latency values.
sports = sports.replace('            ":network-caching": 1400,\n            ":live-caching": 1400,',
                        '            ":network-caching": 1100,\n            ":live-caching": 1100,', 1)
sports = sports.replace(
    "        scheduleFallback(generation: myGeneration, delayNanoseconds: 7_000_000_000)\n",
    "        scheduleFallback(generation: myGeneration, delayNanoseconds: 4_500_000_000)\n",
    1,
)
sports = sports.replace(
    "            scheduleFallback(generation: generation, delayNanoseconds: 7_000_000_000)\n",
    "            scheduleFallback(generation: generation, delayNanoseconds: 4_500_000_000)\n",
    1,
)
sports = sports.replace(
    "                    self.scheduleFallback(generation: myGeneration, delayNanoseconds: 4_000_000_000)\n",
    "                    self.scheduleFallback(generation: myGeneration, delayNanoseconds: 2_500_000_000)\n",
    1,
)

# Surface callbacks for every geometry path that can change the drawable.
host_anchor = '''    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onNeedsRebind?() }
    }
'''
host_replacement = '''    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onNeedsRebind?() }
    }

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if superview != nil { onNeedsRebind?() }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onNeedsRebind?()
    }
'''
if host_anchor not in sports:
    raise SystemExit("V36: drawable host anchor not found")
sports = sports.replace(host_anchor, host_replacement, 1)

old_bind = '''        private func bind(_ view: XSVLCDrawableHostView) {
            guard view.window != nil || view.bounds.width > 0 else { return }
            let sizeChanged = view.bounds.size != lastBoundSize
            if player.drawable as AnyObject? !== view || sizeChanged {
                player.drawable = view
                lastBoundSize = view.bounds.size
            }
        }
'''
new_bind = '''        private func bind(_ view: XSVLCDrawableHostView) {
            guard view.bounds.width > 0, view.bounds.height > 0 else { return }
            let sizeChanged = view.bounds.size != lastBoundSize

            // MobileVLCKit may keep the old drawable geometry if the UIView
            // pointer stays identical. A real bounds change therefore gets a
            // deliberate detach/reattach without touching the media session.
            if sizeChanged, player.drawable as AnyObject? === view {
                player.drawable = nil
            }
            if player.drawable as AnyObject? !== view || sizeChanged {
                player.drawable = view
                lastBoundSize = view.bounds.size
            }
        }
'''
if old_bind not in sports:
    raise SystemExit("V36: drawable bind method not found")
sports = sports.replace(old_bind, new_bind, 1)

sports = sports.replace(
'''                self?.rebind(after: 0.05)
                self?.rebind(after: 0.28)
''',
'''                self?.rebind(after: 0.03)
                self?.rebind(after: 0.16)
                self?.rebind(after: 0.42)
''',
1,
)

# Fill the presentation hierarchy instead of inheriting a stale intrinsic size.
surface_call = '''            XSVLCVideoSurface(player: model.player)
                .ignoresSafeArea()
                .allowsHitTesting(false)
'''
surface_fill = '''            XSVLCVideoSurface(player: model.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
'''
if surface_call not in sports:
    raise SystemExit("V36: player surface call not found")
sports = sports.replace(surface_call, surface_fill, 1)

sports_path.write_text(sports, encoding="utf-8")

# ---------------------------------------------------------------------------
# V36 content safety
# - globally drop TMDB adult=true results, not just Anime browse
# - reject adult detail payloads
# - strict anime safety gate in browse, search and detail
# - cache verdicts and cap list concurrency to keep browsing responsive
# ---------------------------------------------------------------------------

if "case explicitContent" not in tmdb:
    tmdb = tmdb.replace("        case decoding\n", "        case decoding\n        case explicitContent\n", 1)
    tmdb = tmdb.replace(
        '            case .decoding: return "Couldn’t read the catalog response."\n',
        '            case .decoding: return "Couldn’t read the catalog response."\n            case .explicitContent: return "This title is hidden by the content safety filter."\n',
        1,
    )

# List payloads carry an explicit adult flag. Filtering here protects trending,
# popular, Anime, search and any future list method that maps through mediaItem.
list_field_anchor = "    let originalLanguage: String?\n"
if list_field_anchor not in tmdb:
    raise SystemExit("V36: ListResult field anchor not found")
tmdb = tmdb.replace(list_field_anchor, list_field_anchor + "    let adult: Bool?\n", 1)

tmdb = tmdb.replace(
    '        case originalLanguage = "original_language"\n',
    '        case originalLanguage = "original_language"\n        case adult\n',
    1,
)

media_item_anchor = '''    func mediaItem(forcedKind: MediaKind) -> MediaItem? {
        let resolvedTitle = (title ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
'''
media_item_replacement = '''    func mediaItem(forcedKind: MediaKind) -> MediaItem? {
        guard adult != true else { return nil }
        let resolvedTitle = (title ?? name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
'''
if media_item_anchor not in tmdb:
    raise SystemExit("V36: ListResult mediaItem anchor not found")
tmdb = tmdb.replace(media_item_anchor, media_item_replacement, 1)

# Detail responses are a second safety boundary for saved/deep-linked titles.
detail_field_anchor = "    let seasons: [SeasonListResponse]?\n"
if detail_field_anchor not in tmdb:
    raise SystemExit("V36: DetailsResponse field anchor not found")
tmdb = tmdb.replace(detail_field_anchor, detail_field_anchor + "    let adult: Bool?\n", 1)
tmdb = tmdb.replace(
    "        case id, title, name, overview, runtime, status, tagline, genres, seasons\n",
    "        case id, title, name, overview, runtime, status, tagline, genres, seasons, adult\n",
    1,
)

old_details = r'''    func details(for item: MediaItem) async throws -> MediaDetails {
        switch item.kind {
        case .movie:
            let r = try await request(path: "/movie/\(item.tmdbID)", query: [
                .init(name: "language", value: language)
            ], as: DetailsResponse.self)
            return r.mediaDetails(fallback: item, kind: .movie)
        case .tv, .anime:
            let r = try await request(path: "/tv/\(item.tmdbID)", query: [
                .init(name: "language", value: language)
            ], as: DetailsResponse.self)
            return r.mediaDetails(fallback: item, kind: item.kind)
        }
    }
'''
new_details = r'''    func details(for item: MediaItem) async throws -> MediaDetails {
        if item.kind == .anime {
            guard await animeSafetyAllows(item) else { throw APIError.explicitContent }
        }
        switch item.kind {
        case .movie:
            let r = try await request(path: "/movie/\(item.tmdbID)", query: [
                .init(name: "language", value: language)
            ], as: DetailsResponse.self)
            guard r.adult != true else { throw APIError.explicitContent }
            return r.mediaDetails(fallback: item, kind: .movie)
        case .tv, .anime:
            let r = try await request(path: "/tv/\(item.tmdbID)", query: [
                .init(name: "language", value: language)
            ], as: DetailsResponse.self)
            guard r.adult != true else { throw APIError.explicitContent }
            return r.mediaDetails(fallback: item, kind: item.kind)
        }
    }
'''
if old_details not in tmdb:
    raise SystemExit("V36: details() method not found")
tmdb = tmdb.replace(old_details, new_details, 1)

# Replace V34's unlimited group + fail-open metadata checks with bounded batches,
# an in-memory verdict cache, and strict fail-closed Anime classification.
helpers_start = tmdb.find("    private func filterSafeAnime(_ items: [MediaItem]) async -> [MediaItem] {")
request_start = tmdb.find("    private func request<T: Decodable>", helpers_start)
if helpers_start < 0 or request_start < 0:
    raise SystemExit("V36: V34 anime helper block not found")

hardened_helpers = r'''    private func filterSafeAnime(_ items: [MediaItem]) async -> [MediaItem] {
        var accepted: [(Int, MediaItem)] = []
        let chunkSize = 6
        for start in stride(from: 0, to: items.count, by: chunkSize) {
            let end = min(start + chunkSize, items.count)
            let batch = Array(items[start..<end])
            let checked = await withTaskGroup(of: (Int, MediaItem?).self) { group in
                for (offset, item) in batch.enumerated() {
                    group.addTask {
                        let allowed = await animeSafetyAllows(item)
                        return (start + offset, allowed ? item : nil)
                    }
                }
                var results: [(Int, MediaItem)] = []
                for await (index, item) in group {
                    if let item { results.append((index, item)) }
                }
                return results
            }
            accepted.append(contentsOf: checked)
        }
        return accepted.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func filterUnsafeAnimeFromMixedResults(_ items: [MediaItem]) async -> [MediaItem] {
        var accepted: [(Int, MediaItem)] = []
        let chunkSize = 6
        for start in stride(from: 0, to: items.count, by: chunkSize) {
            let end = min(start + chunkSize, items.count)
            let batch = Array(items[start..<end])
            let checked = await withTaskGroup(of: (Int, MediaItem?).self) { group in
                for (offset, item) in batch.enumerated() {
                    group.addTask {
                        guard item.kind == .anime else { return (start + offset, item) }
                        let allowed = await animeSafetyAllows(item)
                        return (start + offset, allowed ? item : nil)
                    }
                }
                var results: [(Int, MediaItem)] = []
                for await (index, item) in group {
                    if let item { results.append((index, item)) }
                }
                return results
            }
            accepted.append(contentsOf: checked)
        }
        return accepted.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private func animeSafetyAllows(_ item: MediaItem) async -> Bool {
        if let cached = await AnimeSafetyVerdictCache.shared.value(for: item.tmdbID) {
            return cached
        }

        let localText = "\(item.title) \(item.overview)".lowercased()
        if AnimeSafetyPolicy.containsExplicitSexualMarker(localText) {
            await AnimeSafetyVerdictCache.shared.set(false, for: item.tmdbID)
            return false
        }

        do {
            async let keywordsRequest: TVKeywordsResponse = request(
                path: "/tv/\(item.tmdbID)/keywords",
                query: [],
                as: TVKeywordsResponse.self
            )
            async let ratingsRequest: TVContentRatingsResponse = request(
                path: "/tv/\(item.tmdbID)/content_ratings",
                query: [],
                as: TVContentRatingsResponse.self
            )
            let (keywords, ratings) = try await (keywordsRequest, ratingsRequest)
            let keywordText = keywords.results.map(\.name).joined(separator: " ").lowercased()
            let allowed = !AnimeSafetyPolicy.containsExplicitSexualMarker(keywordText)
                && !ratings.results.contains(where: AnimeSafetyPolicy.isExplicitAdultRating)
            await AnimeSafetyVerdictCache.shared.set(allowed, for: item.tmdbID)
            return allowed
        } catch {
            // Strict mode: if an Anime title cannot be classified, hide it rather
            // than risk surfacing 18+/nudity content. Cached known-good titles stay fast.
            await AnimeSafetyVerdictCache.shared.set(false, for: item.tmdbID)
            return false
        }
    }

'''
tmdb = tmdb[:helpers_start] + hardened_helpers + tmdb[request_start:]

policy_start = tmdb.find("private enum AnimeSafetyPolicy {")
keywords_start = tmdb.find("private struct TVKeywordsResponse", policy_start)
if policy_start < 0 or keywords_start < 0:
    raise SystemExit("V36: AnimeSafetyPolicy block not found")

hardened_policy = r'''private actor AnimeSafetyVerdictCache {
    static let shared = AnimeSafetyVerdictCache()
    private var values: [Int: (allowed: Bool, savedAt: Date)] = [:]
    private let ttl: TimeInterval = 6 * 60 * 60

    func value(for id: Int) -> Bool? {
        guard let entry = values[id] else { return nil }
        guard Date().timeIntervalSince(entry.savedAt) < ttl else {
            values[id] = nil
            return nil
        }
        return entry.allowed
    }

    func set(_ allowed: Bool, for id: Int) {
        values[id] = (allowed, Date())
    }
}

private enum AnimeSafetyPolicy {
    private static let blockedMarkers = [
        "hentai", "ecchi", "erotic", "erotica", "nudity", "nude scene",
        "female nudity", "male nudity", "full frontal", "explicit sex",
        "sex scene", "sexual content", "sexuality", "sex comedy",
        "sexual humor", "sexualised", "sexualized", "fan service", "fanservice",
        "pornographic", "pornography", "adult animation", "uncensored sex",
        "incest", "sexual violence", "rape", "هنتاي", "عري", "إباحية",
        "اباحي", "إباحي", "مشاهد جنسية", "محتوى جنسي"
    ]

    static func containsExplicitSexualMarker(_ text: String) -> Bool {
        let normalized = text.lowercased()
        return blockedMarkers.contains { normalized.contains($0) }
    }

    static func isExplicitAdultRating(_ item: TVContentRating) -> Bool {
        let value = item.rating.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let globallyAdult = ["X", "XXX", "NC-17", "TV-MA", "18", "18+", "R18", "R18+", "X18+"]
        if globallyAdult.contains(value) { return true }
        switch item.iso31661.uppercased() {
        case "JP": return ["R18+", "R18", "18+"].contains(value)
        case "DE": return ["18", "FSK 18"].contains(value)
        case "GB": return ["18", "R18"].contains(value)
        case "AU": return ["R18+", "X18+"].contains(value)
        default: return false
        }
    }
}

'''
tmdb = tmdb[:policy_start] + hardened_policy + tmdb[keywords_start:]

if "V36_CONTENT_SAFETY" not in tmdb:
    tmdb = "// V36_CONTENT_SAFETY: global adult flag rejection + strict cached Anime gate.\n" + tmdb

tmdb_path.write_text(tmdb, encoding="utf-8")

print("Applied V36 hardening: rotation-safe live player, faster failover, strict adult/anime safety.")
