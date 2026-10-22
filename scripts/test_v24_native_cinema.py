"""V24 native UX + sports-only IPTV regressions."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
service=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
ui=Path("FrameNative/Views/XSCinemaNativeExperience.swift").read_text()
project=Path("project-native.yml").read_text()
sport=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
player=Path("FrameNative/Views/XSVODVLCPlayerView.swift").read_text()
checks={
 "Four native main tabs":all(v in root for v in (
    "XSCinemaNativeHomeView()","XSCinemaNativeBrowseView(kind:.movie)",
    "XSCinemaNativeBrowseView(kind:.series)","XSSportsLiveViewV33()")),
 "No site webview runtime":"WKWebView" not in root+ui+service
     and "XSETWatchPortalView" not in root,
 "No ETWatch browser source compiled":"- Views/XSETWatchPortalView.swift" in project,
 "IPTV VOD removed from app binary":all(v in project for v in (
    "- Views/XSVODPremiumExperience.swift","- Services/XSVODService.swift",
    "- Services/XSVODRedirectResolver.swift")),
 "Sports player untouched":"XSSportsLiveViewV33()" in root and "XSVLCStableSurfaceView" in sport,
 "Native metadata catalog real not invented":all(v in service for v in (
    "v3-cinemeta.strem.io","JSONDecoder().decode","/catalog/","/meta/")),
 "Only explicit open licensed movies playable": all(v in service for v in (
    "creativecommons.org/licenses/by/","creativecommons.org/publicdomain/zero/",
    "playableURL: nil","openFilms()")),
 "Player only for verified direct URL":"if let url=item.streamURL, item.isPlayable" in ui,
 "No fake play button":"ما توفر له رابط تشغيل مصرح به" in ui,
 "R5-style video chrome":"gobackward.10" in player
    and "player.textTracks" in player,
 "Native artwork rails search seasons":all(v in ui for v in (
    "LazyHStack","LazyVGrid","XSCinemaNativeSearchView","selectedSeason","ForEach")),
 "No iframe media extraction":all(v not in service+ui for v in
    ("iframe","etwatch.net","get_vod_streams","player_api.php","FebBox")),
}
for label,p in checks.items():
    if not p: raise SystemExit("V24 FAIL: "+label)
print("V24 native catalog + unchanged IPTV Sports checks passed:",len(checks))
