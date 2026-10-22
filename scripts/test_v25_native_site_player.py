"""V25 native library and site-owned playback assertions."""
from pathlib import Path
base=Path("FrameNative")
service=(base/"Services/XSCinemaNativeSource.swift").read_text()
client=(base/"Services/XSCinemaV25FlexibleCatalog.swift").read_text()
seed=(base/"Services/XSCinemaV25Seed.swift").read_text()
ui=(base/"Views/XSCinemaNativeExperience.swift").read_text()
player=(base/"Views/XSCinemaV25SitePlayerView.swift").read_text()
root=(base/"Views/EnhancedRootView.swift").read_text()
sport=(base/"Views/SportsLiveViewV33.swift").read_text()
project=Path("project-native.yml").read_text()
checks={
 "Bundled actual film catalog":seed.count("kind:.movie")>=10,
 "Bundled actual series catalog":seed.count("kind:.series")>=10,
 "Native movie/series homepage":all(key in root for key in (
     "XSCinemaNativeHomeView()","XSCinemaNativeBrowseView(kind:.movie)",
     "XSCinemaNativeBrowseView(kind:.series)")),
 "Sports remains original R5": "XSSportsLiveViewV33()" in root and
     "XSVLCStableSurfaceView" in sport,
 "Tolerant catalog parse":all(key in client for key in (
     "JSONSerialization.jsonObject","compactMap",
     "moviedb_id","imdbRating","/catalog/","/meta/")),
 "Cinemeta fallback used in first frame":all(key in service for key in (
     "movies = XSCinemaV25Seed.movies","series = XSCinemaV25Seed.series")),
 "Internet Archive secondary no startup block":
     "freeMovies = await c" not in service and "Task { [weak self]" in service,
 "Real native search": "XSCinemaV25FlexibleCatalog.shared.search" in ui,
 "All episodes site-watch actionable":all(key in ui for key in (
     "etwatchPlayer = XSCinemaV25PlayerSelection",
     "season:ep.season,episode:ep.number")),
 "Site player only in details":all(key in player for key in (
     "WKWebViewConfiguration","watch/movie/","watch/tv/",
     "websiteDataStore = .default()")) and
     "WKWebView" not in root+ui,
 "User has failure fallback":all(key in player for key in (
     "تعذر فتح صفحة المشاهدة","جرب في Safari","didFailProvisionalNavigation")),
 "App is not browser wrapper": "XSETWatchPortalView" not in root
    and "- Views/XSETWatchPortalView.swift" in project,
 "No movie IPTV VOD": "get_vod_streams" not in root+ui+player,
 "No media stream extraction":all(key not in player for key in (
     "m3u8","player_api.php","/sources","DRM","fetch(")),
}
for name,ok in checks.items():
    if not ok:raise SystemExit("V25 FAILED: "+name)
print("V25 source regression assertions PASS:",len(checks),
      "snapshot movie titles:",seed.count("kind:.movie"),
      "snapshot series titles:",seed.count("kind:.series"))
