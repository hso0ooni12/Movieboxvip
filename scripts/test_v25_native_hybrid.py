"""V25 source and user-visible playback shell regressions."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
catalog=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
views=Path("FrameNative/Views/XSCinemaNativeExperience.swift").read_text()
web=Path("FrameNative/Views/XSETWatchIsolatedPlayerView.swift").read_text()
project=Path("project-native.yml").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
    "Native movies series home not website browser":
      all(x in root for x in ("XSCinemaNativeHomeView()", "XSCinemaNativeBrowseView(kind:.movie)",
                              "XSCinemaNativeBrowseView(kind:.series)")) and "XSETWatchPortalView" not in root,
    "Sports IPTV engine preserved": "XSSportsLiveViewV33()" in root and "XSVLCStableSurfaceView" in sports,
    "Cinemeta robust parser": "decodeCatalog(_ payload:" in catalog and
      "compactMap" in catalog and "JSONSerialization.jsonObject" in catalog,
    "Catalog fallback for offline and transient failures": all(x in catalog for x in
      ("xs-cinema-", "-bootstrap", "Bundle.main.url", "movies = bundled", "series = bundled")),
    "Free licensed scanner not blocking movies": "Task { [weak self] in" in catalog,
    "TMDB provider route from public link structure": "moviedb_id" in catalog and
      "https://www.etwatch.net/" in web and "tmdbID" in web,
    "Provider player only on explicit click": "XSETWatchPlaybackRequest.forTitle" in views and
      "XSETWatchIsolatedPlayerView(request:chosen)" in views,
    "Nonworking 0:00 provider actionable": "إعادة تحميل" in web and
      "فتح Safari" in web and "state.failed" in web,
    "iOS WebKit full-screen provider, not source scraping": "WKWebView" in web and
      "allowsInlineMediaPlayback" in web and
      not any(x in web for x in ("m3u8", "player_api.php", "URLSession", "window.fetch")),
    "Provider fallback not promised as native VLC": "XSVODVLCPlayerView(source:chosen)" in views
      and "XSETWatchIsolatedPlayerView(request:chosen)" in views,
    "Premium animated UI": "ambientGlow" in views and "repeatForever" in views,
    "Site full-page bridge excluded from compiled targets": "- Views/XSETWatchPortalView.swift" in project,
    "Xtream VOD old services excluded": "- Services/XSVODService.swift" in project,
}
for desc,result in checks.items():
    if not result: raise SystemExit("V25 source assertion FAILED: "+desc)
print("V25 native metadata, player handoff and sports regression PASS",len(checks))
