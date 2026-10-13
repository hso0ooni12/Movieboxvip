from pathlib import Path

sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")
iptv = Path("FrameNative/Services/IPTVService.swift").read_text(encoding="utf-8")
project = Path("project-native.yml").read_text(encoding="utf-8")
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text(encoding="utf-8")
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")

required_sports = [
    "V35_FINAL_POLISH",
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
    "network-caching",
    "live-caching",
    "http-reconnect",
    "scheduleFallback",
    "userPaused",
    "player.drawable = nil",
]
for marker in required_sports:
    assert marker in sports, f"missing V35 sports marker: {marker}"

# Canvas tap must hide immediately when visible, not only restart the auto-hide timer.
assert "if controlsVisible {\n            withAnimation(.easeOut(duration: 0.14)) { controlsVisible = false }" in sports
assert ".onTapGesture {\n                    toggleControlsFromCanvas()" in sports

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

print("V35 final polish integrity PASS")
