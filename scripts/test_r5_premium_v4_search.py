"""Premium V4 navigation regression: searched movies/series must open details.

Exercises source-level navigation invariants for all three search entry paths.
SwiftUI stack transition still requires a device/simulator check separately.
"""
from pathlib import Path

search = Path("FrameNative/Views/GlobalSearchView.swift").read_text()
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text()
home = Path("FrameNative/Views/XSCinematicHomeView.swift").read_text()
detail = Path("FrameNative/Views/DetailView.swift").read_text()
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()

checks = {
    "no duplicate MediaItem navigation registry inside search": ".navigationDestination(for: MediaItem.self)" not in search,
    "no value route in search that can hit parent home destinations": "NavigationLink(value:" not in search,
    "search has three explicit detail links": search.count("DetailView(item: item)") == 2 and "DetailView(item: featured)" in search,
    "search results link to the selected item": "ForEach(scopedResults) { item in" in search and "DetailView(item: item)" in search,
    "search suggestions link directly to details": "private func searchRail" in search and "DetailView(item: item)" in search,
    "scopes filter real search results": "case .movies: return results.filter { $0.kind == .movie }" in search and "case .series: return results.filter { $0.kind == .tv }" in search,
    "search still reaches app search service": "try await app.search(text)" in search,
    "search cancellation remains active": "searchTask?.cancel()" in search,
    "no navigation layer over full screen player": "tabControl(" not in root and ".toolbar(.hidden, for: .tabBar)" in player,
    "home personalized rail uses existing related engine": "app.related(to: recent" in home and "library.continueWatching.first" in home,
    "saved watchlist uses stored favorites": "library.favoriteItems" in home,
    "swipe hero guarded from vertical drag": "abs(dx) > abs(dy) * 1.4" in home,
    "reduced motion support": "accessibilityReduceMotion" in home,
    "detail still loads selected item": "let item: MediaItem" in detail and ".task { await load() }" in detail,
    "R5 subtitle bridge remains connected": "sourceSubtitles.select(payload)" in player,
    "R5 VLC surface patch remains available": "V39_R5_STABILITY_RESTORE" in sports,
}

for name, ok in checks.items():
    if not ok:
        raise SystemExit("Premium V4 search navigation regression: " + name)
print(f"Premium V4 PASS: {len(checks)} search, navigation, personalization and playback guards")
