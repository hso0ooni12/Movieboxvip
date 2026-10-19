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
    "new cinematic home is routed": "XSFebboxPremiumHomeView(showSettings: $showSettings)" in root,
    "tab navigation is owned by TabView": "TabView(selection: $selectedTab)" in root and "tabControl(" not in root,
    "no floating root overlay": "ZStack(alignment: .bottom)" not in root and ".safeAreaInset(edge: .bottom" not in root,
    "native bar respects movie player": ".toolbar(.hidden, for: .tabBar)" in player,
    "native bar respects live player": ".toolbar(.hidden, for: .tabBar)" in sports,
    "edge-to-edge cinematic hero": ".ignoresSafeArea(edges: .top)" in home and "FEATURED TONIGHT" in home,
    "hero thumbnail filmstrip": "Featured title " in home and "featuredItems.indices" in home,
    "immersive home header is scoped to home": ".overlay(alignment: .top) { cinematicHeader }" in home and ".toolbar(.hidden, for: .navigationBar)" in home,
    "caption anchored to aspect-fit video": ("visibleVideoBottomPadding" in player and "lowerBlackBar" in player) or ("R5_ASPECTFIT_CAPTION" in player and "captionLetterboxAdjustment" in player),
    "player caption receives height": "captionOverlay(width: proxy.size.width, height: proxy.size.height)" in player or "captionLetterboxAdjustment(width: proxy.size.width, height: proxy.size.height)" in player,
    "hero artwork and watch action": "cinematicHero" in home and "FrameXTVPlayerScreen(item: item" in home,
    "new discovery cards": "exploreStrip" in home and "XSCinemaPosterTile" in home,
    "editorial selection": "THE EDITORIAL PICK" in home,
    "continue watching persisted": "library.continueWatching" in home and "startAt: entry.currentTime" in home,
    "no anime leak in new home": "app.anime" not in home and "kind: .anime" not in home,
    "catalog starts with poster grid (V8 user request)": "catalogSpotlight(" not in catalog and "posterCollection" in catalog,
    "adaptive catalog layout": "GridItem(.adaptive(minimum: 110" in catalog,
    "catalog sections and search functional": "collectionNavigation" in catalog and "searchAndSort" in catalog and "loadNextPage" in catalog,
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
