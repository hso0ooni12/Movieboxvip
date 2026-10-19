"""Verify Febbox is the exclusive runtime catalog for V19 while sports stays intact."""
from pathlib import Path
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text(encoding="utf8")
store = Path("FrameNative/Services/XSFebboxCatalogStore.swift").read_text(encoding="utf8")
view = Path("FrameNative/Views/XSFebboxPremiumExperience.swift").read_text(encoding="utf8")
service = Path("FrameNative/Services/XSFebboxLibraryService.swift").read_text(encoding="utf8")
sport = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf8")
checks = {
    "home uses Febbox exclusively": "XSFebboxPremiumHomeView()" in root and
      "XSCinematicHomeView(" not in root,
    "movies uses Febbox exclusively": "XSFebboxPremiumBrowseView(shelf: .movies)" in root and
      "XSReferenceCatalogView(" not in root,
    "series uses Febbox exclusively": "XSFebboxPremiumBrowseView(shelf: .series)" in root,
    "sports engine unchanged": "XSSportsLiveViewV33()" in root and
      "XSVLCStableSurfaceView" in sport,
    "no duplicate Febbox tab": 'Label("Febbox"' not in root,
    "no source website or TMDB used by primary screens": all(
      forbidden not in root + store + view for forbidden in
      ("FrameXTVPlayerScreen", "FrameXTVPlayback(", "framextv.xyz",
       "streamimdb.ru", "TMDBClient(", "app.client", "image.tmdb.org")),
    "native home card and browse grid": "XSFebboxPosterTile(" in view and
      "LazyVGrid" in view and "FEATURED FROM FEBBOX" in view,
    "native all-shelf search": "catalog.search(text" in view,
    "native series folder and episode browser": "catalog.children(shelf: item.shelf" in view,
    "source navigation preserved": "XSFebboxPremiumEntryView(item:" in view,
    "source playback with VLC": "XSFebboxVLCPlaybackView(quality:" in view,
    "source-account fallback": "XSFebboxAccountView()" in view and
      "hasAccountSession" in service,
    "read-only recursive all-folder index": "while cursor < queue.count" in store and
      "while !Task.isCancelled" in store and "queue.append(Folder(" in store,
    "all pages via Febbox API": "page.hasNext" in store and
      "number += 1" in store and "/file/file_share_list" in service,
    "resume cached discovery snapshots": "saveSnapshot(" in store and
      "Data(contentsOf: url)" in store,
    "no files or credentials embedded": not any(
      x in store+view for x in ("Cookie:", "PHPSESSID", "client_secret",
                               "auth_token", "FEBBOX_UI_COOKIE")),
    "source-only media id": "shelf.rawValue + \":\" + fid" in store,
    "source-only artwork": "catalog.artwork(for:" in view and
      "thumbnailString" in store,
    "iOS16 support": "ContentUnavailableView" not in root+view,
}
for name, result in checks.items():
    if not result: raise SystemExit("V19 FAILED: " + name)
print(f"V19 Febbox exclusive runtime QA PASSED: {len(checks)} checks")
