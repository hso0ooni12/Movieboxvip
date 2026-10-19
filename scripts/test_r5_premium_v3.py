"""Premium V3 visual transformation regression guards.

Verify visible screen composition, functional taps, and preservation of the
known-good R5 playback and subscription integration. This is not a device QA
replacement: compiled UI still needs physical iPhone visual inspection.
"""
from pathlib import Path

def load(path):
    return Path(path).read_text(encoding="utf-8")

home = load("FrameNative/Views/XSCinematicHomeView.swift")
kit = load("FrameNative/Views/XSPremiumV3Kit.swift")
root = load("FrameNative/Views/EnhancedRootView.swift")
catalog = load("FrameNative/Views/ReferenceBrowseViews.swift")
detail = load("FrameNative/Views/DetailView.swift")
sports = load("FrameNative/Views/SportsLiveViewV33.swift")
search = load("FrameNative/Views/GlobalSearchView.swift")
player = load("FrameNative/FrameXTVPlayerV6.swift")

checks = {
    "immersive home uses real artwork": "XSV3WorldCard(item: item" in home and "XSV3ProgressCard(entry: entry)" in home,
    "genuinely new ranked homepage section": "curatedRanking" in home and "XSV3RankingCard(item: item" in home,
    "home remains linkable to real playback": "FrameXTVPlayerScreen(item: item" in home,
    "continue watching retains precise resume": "startAt: entry.currentTime" in home,
    "cinematic reusable design system": all(s in kit for s in [
        "struct XSV3WorldCard", "struct XSV3RankingCard",
        "struct XSV3ProgressCard", "struct XSV3PressStyle", "struct XSV3ScreenBackdrop"
    ]),
    "reduced motion respected": "accessibilityReduceMotion" in kit,
    "movie and series collections still reachable": "XSReferenceCatalogView(kind: .movie" in root and "XSReferenceCatalogView(kind: .tv" in root,
    "no root overlay on player": "tabControl(" not in root and ".toolbar(.hidden, for: .tabBar)" in player,
    "V8 catalog replaces oversized hero with posters": "catalogSpotlight(" not in catalog and "posterCollection" in catalog,
    "catalog has real provider/genre navigation": "selectedCollection" in catalog and "collectionNavigation" in catalog and "discoverCollection" in catalog,
    "catalog still filters the source remotely": "loadNextPage" in catalog and "app.client.discoverCollection" in catalog,
    "series episodes still offer play": "EpisodeRow(" in detail and "nextPlayback(after:" in detail,
    "details have legible actions": "Read full story" in detail and "My List" in detail,
    "new search result grid": "XSCinemaPosterTile(item: item)" in search and "GridItem(.adaptive" in search,
    "search still debounced": "scheduleSearch(newValue)" in search and "searchTask?.cancel()" in search,
    "sports real favorites from IDs": "favoritesOnly" in sports and "favoriteIDs.contains(stream.streamID)" in sports,
    "sports real playable sources": "selectedStream = stream" in sports and "playbackURLs(for: stream)" in sports,
    "R5 VLC drawable protected": "V39_R5_STABILITY_RESTORE" in sports,
    "no anime leaked into premium home": "app.anime" not in home and "kind: .anime" not in home,
    "source subtitle bridge protected": "sourceSubtitles.select(payload)" in player,
    "portrait subtitle patch protected": "R5_ASPECTFIT_CAPTION" in player or "visibleVideoBottomPadding" in player,
}
for desc, passed in checks.items():
    if not passed:
        raise SystemExit("Premium V3 FAILED: " + desc)
print(f"Premium V3 PASS: {len(checks)} design & functional guards.")
