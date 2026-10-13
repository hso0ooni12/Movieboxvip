from pathlib import Path
import runpy

# V36/V37/V38/V39 are intentionally applied here after every earlier regression
# suite has validated the older generated source. The workflow then compiles
# and packages this final source while older QA remains a regression boundary.
runpy.run_path("scripts/app_v36_hardening.py", run_name="__main__")
runpy.run_path("scripts/app_v36_speed_fix.py", run_name="__main__")
runpy.run_path("scripts/app_v36_compile_compat.py", run_name="__main__")
runpy.run_path("scripts/app_v37_remove_anime.py", run_name="__main__")
runpy.run_path("scripts/app_v38_rotation_surface_rebuild.py", run_name="__main__")
runpy.run_path("scripts/app_v39_stable_vlc_surface.py", run_name="__main__")

sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")
iptv = Path("FrameNative/Services/IPTVService.swift").read_text(encoding="utf-8")
tmdb = Path("FrameNative/Services/TMDBClient.swift").read_text(encoding="utf-8")
project = Path("project-native.yml").read_text(encoding="utf-8")
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text(encoding="utf-8")
reference = Path("FrameNative/Views/ReferenceBrowseViews.swift").read_text(encoding="utf-8")
global_search = Path("FrameNative/Views/GlobalSearchView.swift").read_text(encoding="utf-8")
app_state = Path("FrameNative/Core/AppState.swift").read_text(encoding="utf-8")
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")

required_sports = [
    "V35_FINAL_POLISH",
    "V36_ROTATION_HARDENING",
    "V36_COMPILE_COMPAT",
    "V38_ROTATION_SURFACE_REBUILD",
    "V39_STABLE_VLC_SURFACE",
    "toggleControlsFromCanvas()",
    "private func toggleControlsFromCanvas()",
    "private func keepControlsVisible()",
    "togglePlaybackFromControls()",
    "recoverAfterSurfaceChange()",
    "UIDevice.orientationDidChangeNotification",
    "UIApplication.didBecomeActiveNotification",
    "XSVLCStableSurfaceView",
    "let videoView = UIView(frame: .zero)",
    "videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]",
    "UIView.performWithoutAnimation",
    "player.drawable = host.videoView",
    "player.scaleFactor = 0.0",
    "scheduleGeometryRefreshes()",
    "isDismissingPlayer",
    "interactiveDismissDisabled()",
    "closePlayer()",
    "GeometryReader { proxy in",
    ".frame(width: proxy.size.width, height: proxy.size.height)",
    ".clipped()",
    "guard let media = VLCMedia(url: urls[index])",
    "player.media = media",
    '":network-caching": 1100',
    '":live-caching": 1100',
    "4_500_000_000",
    "2_500_000_000",
    "scheduleFallback",
    "userPaused",
    "suppressStoppedUntil",
    "state == .stopped",
]
for marker in required_sports:
    assert marker in sports, f"missing final sports marker: {marker}"

# Canvas tap must hide immediately when visible, not only restart auto-hide.
assert "if controlsVisible {\n            withAnimation(.easeOut(duration: 0.14)) { controlsVisible = false }" in sports
assert ".onTapGesture {\n                    toggleControlsFromCanvas()" in sports
assert "3_200_000_000" in sports

# V39 supersedes V38's remount-on-rotation strategy. Device recording proved
# that recreating the drawable can leave decoding LIVE while the output turns
# black. Final source must keep a persistent inner drawable, explicitly resize
# it with the host, and reset VLC automatic scaling instead of swapping views.
recovery_start = sports.index("    func recoverAfterSurfaceChange()")
recovery_end = sports.index("    func stop()", recovery_start)
recovery = sports[recovery_start:recovery_end]
assert "self.reload()" not in recovery
assert "self.tryNextSource()" not in recovery
assert "self.player.state == .paused" in recovery
assert "player.scaleFactor = 0.0" in recovery
assert ".id(surfaceGeneration)" not in sports
assert "surfaceGeneration += 1" not in sports
assert "surfaceRepairTask" not in sports
assert "lastSurfaceSize" not in sports
assert "observeSurfaceSize(" not in sports
assert "XSVLCDrawableHostView" not in sports
assert "videoView.frame = bounds" in sports
assert "if player.drawable as AnyObject? !== drawable" in sports
assert "player.drawable = drawable" in sports
assert "for delay in [0.0, 0.05, 0.16, 0.34, 0.65]" in sports
assert "Do not clear player.drawable here" in sports
assert ".transaction { transaction in\n                transaction.animation = nil" in sports
assert "UIScreen.main.bounds" not in sports

# The stable surface bridge must never detach/re-attach VLC simply because the
# drawable size changed. Real teardown remains model.stop(), where drawable=nil
# is intentional after the live player is actually closed.
surface_start = sports.index("private final class XSVLCStableSurfaceView")
surface = sports[surface_start:]
assert "player.drawable = nil" not in surface
assert "videoView.transform = .identity" in surface
assert "player.scaleFactor = 0.0" in surface

# Pinned VLCKit compatibility: no force unwraps and no unsupported `.ended`
# state. Explicit stop events are suppressed so closing/replacing a source does
# not accidentally start a backup stream.
assert "VLCMedia(url: urls[index])!" not in sports
assert "state == .ended" not in sports
assert "guard Date() >= suppressStoppedUntil else { return }" in sports
assert "userPaused = true\n        suppressStoppedUntil = Date().addingTimeInterval(0.75)\n        player.stop()" in sports

# Sports credentials remain hidden; only server override is exposed.
assert "xs.iptv.serverOverride" in sports
assert "Server Address" in sports
assert "Username" not in sports
assert "Password" not in sports

required_cache = [
    "V35_SPORTS_CACHE",
    "SportsCacheEnvelope",
    "cachedSports(credentials:",
    "persistSportsCache",
    "restoreCachedSports()",
    "guard let credentials, !isLoading else { return }",
]
for marker in required_cache:
    assert marker in iptv, f"missing sports cache marker: {marker}"

# Global adult-content boundary remains in place even though Anime is no longer
# part of the user-facing product.
required_safety = [
    "V36_CONTENT_SAFETY",
    "case explicitContent",
    "guard adult != true else { return nil }",
    "guard r.adult != true else { throw APIError.explicitContent }",
    "AnimeSafetyVerdictCache",
    "let chunkSize = 6",
    "async let keywordsRequest",
    "async let ratingsRequest",
    "AnimeSafetyVerdictCache.shared.set(false",
    '"hentai"',
    '"ecchi"',
    '"nudity"',
    '"female nudity"',
    '"full frontal"',
    '"pornography"',
    '"هنتاي"',
    '"عري"',
    '"مشاهد جنسية"',
    '"TV-MA"',
    '"R18+"',
    '"18+"',
]
for marker in required_safety:
    assert marker in tmdb, f"missing content-safety marker: {marker}"

# Strict Anime safety helpers are retained internally for backward compatibility
# with old saved data, but V37 must prevent Anime from entering visible surfaces.
assert "Keep normal anime available if keyword metadata is temporarily unavailable" not in tmdb
assert "Ratings are an extra safety signal" not in tmdb
assert "if item.kind == .anime" in tmdb
assert "guard await animeSafetyAllows(item) else { throw APIError.explicitContent }" in tmdb

# The TMDB adult flag must participate in decoding for lists and details.
assert tmdb.count("let adult: Bool?") >= 2
assert "case adult" in tmdb

# V37: Anime is completely removed from visible navigation, Home, discovery,
# global search, favorites/history, and network-backed search results.
assert "V37_ANIME_REMOVED" in root
assert 'XSReferenceCatalogView(kind: .anime, title: "Anime")' not in root
assert '.tabItem { Label("Anime"' not in root
assert root.count(".xsGlobalSearchToolbar()") >= 4
assert 'title: "Anime Spotlight"' not in reference
assert "Movies, series and anime in one place" not in global_search
assert "Movies and series in one place" in global_search
assert "results = found.filter { $0.kind != .anime }" in global_search
assert "async let animeItems = client.anime()" not in app_state
assert "anime = result.4" not in app_state
assert "case .anime: return []" in app_state
assert "try await client.search(query).filter { $0.kind != .anime }" in app_state
assert ".filter { $0.kind != .anime }" in app_state
assert ".filter { $0.item.kind != .anime }" in app_state
assert "guard !result.isLikelyAnime else { return nil }" in tmdb
assert "return items.filter { $0.kind != .anime }" in tmdb
assert 'case "tv": return result.mediaItem(forcedKind: result.isLikelyAnime ? .anime : .tv)' not in tmdb

# Build reproducibility and ProMotion settings.
assert "revision: aa0082dd94e4c91450dc3b9cbadb2b385f1e995e" in project
assert "CADisableMinimumFrameDuration: true" in project
assert 'SWIFT_OPTIMIZATION_LEVEL: "-O"' in project
assert 'SWIFT_COMPILATION_MODE: "wholemodule"' in project

# Preserve the proven movie/series subtitle and server engine.
movie_markers = [
    "sourceSubtitles.select(payload)",
    "sourceSubtitles.reset()",
    "private func clearSubtitleRequest()",
    "subtitleFrameID",
    "xs:subtitleSelected",
]
for marker in movie_markers:
    assert marker in player, f"movie player regression: missing {marker}"

print("V35 + V36 + V37 + V38 + V39 final hardening integrity PASS")
