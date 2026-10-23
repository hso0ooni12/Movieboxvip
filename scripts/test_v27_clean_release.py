"""V27 release gates for the actually compiled IPA, not obsolete R5 source."""
from pathlib import Path
import re
p=Path("project-native.yml").read_text()
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
app=Path("FrameNative/FrameNativeApp.swift").read_text()
world=Path("FrameNative/Views/XSWorldCinemaUI.swift").read_text()
browse=Path("FrameNative/Views/XSWorldCinemaBrowse.swift").read_text()
player=Path("FrameNative/Views/XSWorldSitePlayer.swift").read_text()
source=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
sport=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
seed=Path("FrameNative/Services/XSCinemaNativeSeed.swift").read_text()
allow = {
"FrameNativeApp.swift","Core/IPTVEmbeddedConfig.swift",
"Services/IPTVService.swift","Services/XSIPTVCatalogDiskCache.swift",
"Services/XSCinemaNativeSource.swift","Services/XSCinemaNativeSeed.swift",
"Views/EnhancedRootView.swift","Views/Branding.swift",
"Views/SportsLiveViewV33.swift","Views/XSWorldCinemaUI.swift",
"Views/XSWorldCinemaBrowse.swift","Views/XSWorldSitePlayer.swift",
}
allfiles={x.relative_to(Path("FrameNative")).as_posix()
 for x in Path("FrameNative").rglob("*.swift")}
excluded=set(re.findall(r"^          - (.+\.swift)$",p,re.M))
actual=allfiles-excluded
assert actual==allow,(sorted(actual-allow),sorted(allow-actual))
checks={
 "Only 12 active Swift files":len(actual)==12,
 "R5 sports fully preserved":"XSSportsLiveViewV33()" in root and
      "struct XSSportsPlayerV33: View" in sport and
      "VLCMediaPlayer" in sport,
 "Sport credentials are live-only":"get_live_streams" in
      Path("FrameNative/Services/IPTVService.swift").read_text(),
 "No VOD streaming from Xtream":all(word not in root+world+browse+player for word in
      ("get_vod_streams","get_series_info","XSFebbox","Febbox")),
 "Three native pages and sports":all(v in root for v in
      ("XSWorldHome()","XSWorldBrowse(kind: .movie)",
       "XSWorldBrowse(kind: .series)","XSSportsLiveViewV33()")),
 "Premium cinema features":all(v in world for v in
      ("XSWorldHero","THE SPOTLIGHT","XSCinemaStyle.lavender",
       "XSWorldRail","ranking = false","YOUR CINEMA. YOUR WORLD." if False else "Trending Movies")),
 "Detailed movie series search and seasons":all(v in browse for v in
      ("XSWorldDetail","XSWorldSearch","XSWorldWatchlist",
       "XSCinemaCatalogAPI.shared.search","selectedEpisode","XSWorldOpenVideo")),
 "Playable media URLs are not fabricated":"playableURL: nil" in source and
      "media.isPlayable" in browse,
 "Offline catalog guaranteed initial titles":all(v in seed for v in
      ("static let movies = decode","static let series = decode")),
 "WebKit subtitle and player architecture":all(v in player for v in
      ("allowsInlineMediaPlayback = true","textTracks","mode='showing'",
       "xstv-cinema-container","forMainFrameOnly: false")),
 "Do not hijack site Play buttons":"Deliberately do not synthesize clicks" in player and
       "play.click()" not in player,
 "No video CDN scraping":all(v not in player for v in
      ("player_api.php","video_quality_list",".m3u8","URLSession.shared")),
 "Playback timeout and Safari fallback":all(v in player for v in
      ("38_000_000_000","XSWorldSafariFallback","unavailable")),
 "Old app/dead player views excluded":all(v in excluded for v in
      ("Views/XSETWatchNativeDetailPlayer.swift",
       "Views/XSCinemaNativeExperience.swift",
       "Views/XSCinematicHomeView.swift",
       "Views/XSVODPremiumExperience.swift",
       "FrameXTVPlayerV6.swift")),
 "App state no longer creates old source app engine":
       "AppState()" not in app and "XSCinemaNativeStore()" in app,
}
for label,passed in checks.items():
    if not passed:raise SystemExit("V27 FAIL: "+label)
print("V27 CLEAN RELEASE PASS",len(checks),"checks;",
      len(actual),"active Swift sources;",
      len(excluded),"unused Swift sources excluded.")
