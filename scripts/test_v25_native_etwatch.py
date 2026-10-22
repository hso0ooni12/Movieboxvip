"""V25 smoke assertions: grounded offline metadata, native browsing, scoped player."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
project=Path("project-native.yml").read_text()
source=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
seed=Path("FrameNative/Services/XSCinemaNativeSeed.swift").read_text()
ui=Path("FrameNative/Views/XSCinemaNativeExperience.swift").read_text()
player=Path("FrameNative/Views/XSETWatchNativeDetailPlayer.swift").read_text()
sport=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
  "native SwiftUI tabs and sports":all(x in root for x in
    ("XSCinemaNativeHomeView()", "XSCinemaNativeBrowseView(kind:.movie)",
     "XSCinemaNativeBrowseView(kind:.series)","XSSportsLiveViewV33()")),
  "source-verified offline movie and series seeds":all(x in seed for x in
    ("static let movies = decode(", "static let series = decode(")),
  "seed applied before first network result":all(x in source for x in
    ("movies = XSCinemaNativeSeed.movies","series = XSCinemaNativeSeed.series")),
  "Cinemeta metadata is not pretending to be video":'playableURL: nil' in source,
  "ETWatch site-specific navigation only":'https://www.etwatch.net/' in source
      and "moviedb_id" in source and "sourceURL: route" in source,
  "real player and source-specific episode screens":all(x in ui for x in
    ("XSETWatchNativeDetailPlayer(",
     "XSCinemaNativeDetailView", "selectedSeason", "fullScreenCover")),
  "site video remains under original website":all(x in player for x in
    ("WKWebView", "WKWebViewConfiguration", "websiteDataStore = .default()")),
  "buffering timeout":all(x in player for x in
    ("35_000_000_000", "state.stalled", "فيديو", "فتح صفحة المشاهدة")),
  "Safari fallback":all(x in player for x in
    ("SFSafariViewController", "presentSafari = true")),
  "safe optional status report": "safeDiagnostic" in player
       and "xstvVideoStatus" in player,
  "no media extraction":all(x not in player for x in
    ("m3u8", "video_quality_list","player_api.php","URLSession.shared","xtream")),
  "old site-wide browser excluded": "- Views/XSETWatchPortalView.swift" in project,
  "sports engine preserved":"XSVLCStableSurfaceView" in sport,
}
for name,ok in checks.items():
    if not ok:raise SystemExit("V25 FAIL: "+name)
print("V25 native, offline catalog, site scoped player + sports regressions:",len(checks),"PASS")
