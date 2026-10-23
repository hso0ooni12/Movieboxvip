"""V27 Editorial: preserve stable original player, R5 sports, and actual metadata."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
home=Path("FrameNative/Views/XSCinemaNativeExperience.swift").read_text()
extra=Path("FrameNative/Views/XSEditorialCollectionsV27.swift").read_text()
player=Path("FrameNative/Views/XSETWatchNativeDetailPlayer.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
tests={
  "native Home/Movies/Series": all(x in root for x in (
    "XSCinemaNativeHomeView()", "XSCinemaNativeBrowseView(kind:.movie)",
    "XSCinemaNativeBrowseView(kind:.series)")),
  "original IPTV sports and player": "XSSportsLiveViewV33()" in root and "XSVLCStableSurfaceView" in sports,
  "no site-wide embedded browsing": "XSETWatchPortalView(section:" not in root,
  "grounded editorial collections": "XSEditorialCollectionsV27()" in home and all(x in extra for x in
      ("store.movies", "store.series", "$0.rating", "releaseYear($0.year)", "CINEMA CLASSICS")),
  "screenshots design cues": all(x in extra for x in
      ("XSAtmosphericCinemaBackdropV27", "RadialGradient", "XSEditorialPressStyleV27",
       "LazyHStack", "RoundedRectangle")),
  "native seasons selectable": "XSSeasonStripV27(seasons: seasons, selected: $selectedSeason)" in home and
       'Text("الموسم \\(season)")' in extra,
  "episode thumbnails grounded": "XSEpisodePosterRowV27(episode: ep)" in home and
       "episode.thumbnail" in extra and "S\\(episode.season)" in extra,
  "season/episode actually passed to player": "selectedWebsiteEpisode = ep" in home
       and "episode: selectedWebsiteEpisode?.number" in home,
  "caption-safe player preserved": "toggleTheater()" in player and "websiteDataStore = .default()" in player
       and "SFSafariViewController" in player,
  "catalog not pretending to own film streams": "player_api.php" not in home+extra
      and "get_vod_streams" not in home+extra,
}
for label,ok in tests.items():
    if not ok: raise SystemExit("V27 Editorial regression FAIL: "+label)
print("V27 Editorial improvements PASS",len(tests),"regression checks")
