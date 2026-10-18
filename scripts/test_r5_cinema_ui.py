"""R5 Cinematic presentation guards. Protect working player internals while requiring real UI work."""
from pathlib import Path

def read(path):
    return Path(path).read_text(encoding="utf-8")

root = read("FrameNative/Views/EnhancedRootView.swift")
home = read("FrameNative/Views/XSCinematicHomeView.swift")
catalog = read("FrameNative/Views/ReferenceBrowseViews.swift")
detail = read("FrameNative/Views/DetailView.swift")
sports = read("FrameNative/Views/SportsLiveViewV33.swift")
search = read("FrameNative/Views/GlobalSearchView.swift")
player = read("FrameNative/FrameXTVPlayerV6.swift")
checks = {
    "new cinematic home is routed": "XSCinematicHomeView(showSettings: $showSettings)" in root,
    "tab navigation is owned by TabView": "TabView(selection: $selectedTab)" in root and "tabControl(" not in root,
    "no floating root overlay": "ZStack(alignment: .bottom)" not in root and ".safeAreaInset(edge: .bottom" not in root,
    "native bar respects movie player": ".toolbar(.hidden, for: .tabBar)" in player,
    "native bar respects live player": ".toolbar(.hidden, for: .tabBar)" in sports,
    "edge-to-edge cinematic hero": ".ignoresSafeArea(edges: .top)" in home and "FEATURED TONIGHT" in home,
    "hero thumbnail filmstrip": "Featured title " in home and "featuredItems.indices" in home,
    "hero artwork and watch action": "cinematicHero" in home and "FrameXTVPlayerScreen(item: item" in home,
    "new discovery cards": "exploreStrip" in home and "XSCinemaPosterTile" in home,
    "editorial selection": "THE EDITORIAL PICK" in home,
    "continue watching persisted": "library.continueWatching" in home and "startAt: entry.currentTime" in home,
    "no anime leak in new home": "app.anime" not in home and "kind: .anime" not in home,
    "catalog spotlight": "catalogSpotlight(spotlight)" in catalog,
    "adaptive catalog layout": "GridItem(.adaptive(minimum: 110" in catalog,
    "functional filtering preserved": "private var filtered:" in catalog and "isFiltering" in catalog,
    "details retain episode playback": "episodeSection" in detail and "FrameXTVPlayerScreen(" in detail,
    "cinematic details": "NOW STREAMING  /  XS TV" in detail,
    "sports redesigned outside player": "LIVE ARENA" in sports and "ON AIR" in sports,
    "sports still selects streams": "selectedStream = stream" in sports,
    "search retains functional debounce": "scheduleSearch(newValue)" in search,
    "server switching integration intact": "sourceSubtitles.select(payload)" in player and "func selectServer(_ server: XSServerOption)" in player,
    "R5 live decoder stable": "V39_R5_STABILITY_RESTORE" in sports and "XSVLCStableSurfaceView" in sports,
}
for label, ok in checks.items():
    if not ok:
        raise SystemExit("R5 Cinematic UI guard failed: " + label)
print("R5 Cinematic UI guards PASS: new screens, preserved navigation/playback, content boundary")
