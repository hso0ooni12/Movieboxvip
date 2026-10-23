"""V27 premium rebuild checks performed after UI isolation before xcodegen."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
project=Path("project-native.yml").read_text()
ui=Path("FrameNative/Views/XSPremiumCinemaV27.swift").read_text()
store=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
player=Path("FrameNative/Views/XSETWatchNativeDetailPlayer.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
seed=Path("FrameNative/Services/XSCinemaNativeSeed.swift").read_text()
checks={
 "Native 4-tab production shell":all(x in root for x in
  ("XSPremiumCinemaHome()", "XSPremiumBrowse(kind: .movie)",
   "XSPremiumBrowse(kind: .series)", "XSSportsLiveViewV33()")),
 "No obsolete movie web browser routed from home":"XSETWatchPortalView(" not in root+ui,
 "Premium hero and tap-swipe carousel":all(x in ui for x in
  ("THE SPOTLIGHT", "featurePicker", "DragGesture(minimumDistance: 60)")),
 "Editorial collections and ranked carousel":all(x in ui for x in
  ("HANDPICKED FOR TONIGHT", "YOUR NEXT OBSESSION", "rankedRail", "XSPremiumPoster")),
 "Native discovery and detail navigation":all(x in ui for x in
  ("XSPremiumCinemaDetail","XSPremiumSearch","XSPremiumWatchlist")),
 "Real seasons and episode list":all(x in ui for x in
  ("XSCinemaCatalogAPI.shared.detail(media)", "item.episodes.filter{$0.season==season}")),
 "Cinemeta seed avoids blank home":all(x in store+seed for x in
  ("XSCinemaNativeSeed.movies","XSCinemaNativeSeed.series","static let movies")),
 "Navigation route retains original player's subtitles":all(x in ui+player for x in
  ("XSETWatchNativeDetailPlayer(", "xstv-theater-player")),
 "No claim that metadata proves playable links":'playableURL: nil' in store and
  "قد يتعذر تشغيل بعض الأعمال" in ui,
 "Protected sports engine unchanged":'XSSportsLiveViewV33()' in root
  and "XSVLCStableSurfaceView" in sports,
 "No IPTV VOD in UI or media feed":all(x not in ui+store+root for x in
  ("player_api.php","get_vod_streams","get_series_info")),
 "Old movie browsing and IPTV VOD code excluded":all(x in project for x in
  ("- Views/XSCinemaNativeExperience.swift","- Views/XSETWatchPortalView.swift",
   "- Views/XSVODPremiumExperience.swift","- Services/XSVODService.swift")),
 "New cinema UI and VLC remain in build":all(x not in project for x in
  ("- Views/XSPremiumCinemaV27.swift","- Views/XSVODVLCPlayerView.swift",
   "- Views/XSETWatchNativeDetailPlayer.swift")),
}
for name,result in checks.items():
 if not result: raise SystemExit("V27 FAIL: "+name)
print("V27 premium UI source guards PASS:",len(checks))
