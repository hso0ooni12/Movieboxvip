from pathlib import Path
import runpy

# V36 is intentionally applied here after every earlier regression suite has
# validated the V34/V35 generated source. The workflow then compiles/packages
# this hardened source, while older QA remains a clean regression boundary.
runpy.run_path("scripts/app_v36_hardening.py", run_name="__main__")
runpy.run_path("scripts/app_v36_speed_fix.py", run_name="__main__")
runpy.run_path("scripts/app_v36_compile_compat.py", run_name="__main__")

sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")
iptv = Path("FrameNative/Services/IPTVService.swift").read_text(encoding="utf-8")
tmdb = Path("FrameNative/Services/TMDBClient.swift").read_text(encoding="utf-8")
project = Path("project-native.yml").read_text(encoding="utf-8")
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text(encoding="utf-8")
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")

required_sports = [
    "V35_FINAL_POLISH",
    "V36_ROTATION_HARDENING",
    "V36_COMPILE_COMPAT",
    "toggleControlsFromCanvas()",
    "private func toggleControlsFromCanvas()",
    "private func keepControlsVisible()",
    "togglePlaybackFromControls()",
    "recoverAfterSurfaceChange()",
    "UIDevice.orientationDidChangeNotification",
    "UIApplication.didBecomeActiveNotification",
    "XSVLCDrawableHostView",
    "onNeedsRebind",
    "player.drawable = view",
    "player.drawable = nil",
    "safeAreaInsetsDidChange",
    "didMoveToSuperview",
    "isDismissingPlayer",
    "interactiveDismissDisabled()",
    "closePlayer()",
    ".frame(maxWidth: .infinity, maxHeight: .infinity)",
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

# Rotation must not reload/switch a healthy live source. The drawable itself is
# forcibly detached/rebound when its bounds change, while VLC media stays alive.
recovery_start = sports.index("    func recoverAfterSurfaceChange()")
recovery_end = sports.index("    func stop()", recovery_start)
recovery = sports[recovery_start:recovery_end]
assert "self.reload()" not in recovery
assert "self.tryNextSource()" not in recovery
assert "self.player.state == .paused" in recovery
assert "if sizeChanged, player.drawable as AnyObject? === view" in sports
assert "player.drawable = nil\n            }\n            if player.drawable as AnyObject? !== view || sizeChanged" in sports
assert "UIScreen.main.bounds" not in sports

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

# Global adult-content boundary + strict Anime safety gate.
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

# Strict Anime mode must fail closed when classification metadata is unavailable.
assert "Keep normal anime available if keyword metadata is temporarily unavailable" not in tmdb
assert "Ratings are an extra safety signal" not in tmdb
assert "if item.kind == .anime" in tmdb
assert "guard await animeSafetyAllows(item) else { throw APIError.explicitContent }" in tmdb

# The TMDB adult flag must participate in decoding for lists and details.
assert tmdb.count("let adult: Bool?") >= 2
assert "case adult" in tmdb

# Build reproducibility and ProMotion settings.
assert "revision: aa0082dd94e4c91450dc3b9cbadb2b385f1e995e" in project
assert "CADisableMinimumFrameDuration: true" in project
assert 'SWIFT_OPTIMIZATION_LEVEL: "-O"' in project
assert 'SWIFT_COMPILATION_MODE: "wholemodule"' in project

# Global search stays available from every main tab.
assert root.count(".xsGlobalSearchToolbar()") >= 5

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

print("V35 + V36 final hardening integrity PASS")
