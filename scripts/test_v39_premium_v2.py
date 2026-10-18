"""Static guards for V39 V2 enhancements and critical playback isolation."""
from pathlib import Path
import subprocess

def text(path):
    return Path(path).read_text(encoding="utf-8")

detail = text("FrameNative/Views/DetailView.swift")
root = text("FrameNative/Views/EnhancedRootView.swift")
browse = text("FrameNative/Views/ReferenceBrowseViews.swift")
state = text("FrameNative/Core/AppState.swift")

assert "episodesTask?.cancel()" in detail
assert "try Task.checkCancellation()" in detail
assert "guard selectedSeason == season else { return }" in detail
assert "defer { if selectedSeason == season { episodeLoading = false } }" in detail
assert 'Button("Try Again")' in detail
assert "try await app.episodes(tmdbID: item.tmdbID, season: season)" in detail
assert "try? await Task.sleep(nanoseconds: 1_250_000_000)" not in root
assert "GridItem(.adaptive(minimum: 128, maximum: 185)" in browse
assert browse.count("UISelectionFeedbackGenerator().selectionChanged()") == 2
assert 'FrameNative.favoriteItems.v2' in state
assert 'FrameNative.watchProgress.v2' in state

# Protected playback contracts continue to be audited by the original V39 test.
subprocess.run(["python3", "scripts/test_v39_premium_safety.py"], check=True)
print("V39 Premium V2 navigation, season concurrency and persistence checks PASSED")
