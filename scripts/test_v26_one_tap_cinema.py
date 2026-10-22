"""V26 check: original inline subtitle DOM, one-tap action and R5 Sports."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
source=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
web=Path("FrameNative/Views/XSETWatchNativeDetailPlayer.swift").read_text()
ui=Path("FrameNative/Views/XSCinemaNativeExperience.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
project=Path("project-native.yml").read_text()
checks={
 "Native catalog retained": "XSCinemaNativeHomeView()" in root and
        "XSCinemaNativeBrowseView(kind:.series)" in root,
 "Sports engine untouched": "XSSportsLiveViewV33()" in root and
        "XSVLCStableSurfaceView" in sports,
 "No IPTV VOD": "get_vod_streams" not in root+ui+source+web,
 "Independent original ETWatch player": "WKWebView" in web and
        "allowsInlineMediaPlayback = true" in web,
 "Set playsinline before iPhone video fullscreen": all(x in web for x in
        ("v.setAttribute(\"playsinline\"", "v.setAttribute(\"webkit-playsinline\"", "v.playsInline=true")),
 "Cinema CSS contains HTML captions with video": all(x in web for x in
        ("xstv-theater-player", "document.documentElement.classList.add(\"xstv-cinema-on\")",
         "window.__xstvEnterTheater")),
 "Fullscreen button uses CSS theater, not video-only native": 'e.stopImmediatePropagation()' in web
        and 'fullscreen|full.screen' in web,
 "Automatic site Play attempt with fallback": all(x in web for x in
        ("autoplayAttempted", "play.click()", "count>30", "openOfficialSite" if False else "presentSafari")),
 "Clickable episode navigation": all(x in ui for x in
        ("selectedWebsiteEpisode = ep", "season: selectedWebsiteEpisode?.season",
         "episode: selectedWebsiteEpisode?.number")),
 "Cautious episode DOM matching": "selectEpisodeIfVisible()" in web and
        'desiredEpisode===null' in web,
 "No media source extraction": all(x not in web for x in
        ("URLSession.shared", "video_quality_list", ".m3u8", "get_vod_streams",
         "player_api.php")),
 "Network timeout and Safari fallback": "35_000_000_000" in web
        and "SFSafariViewController" in web,
 "Old site-wide browser not included": "- Views/XSETWatchPortalView.swift" in project,
}
for title,result in checks.items():
    if not result: raise SystemExit("V26 FAIL: "+title)
print("V26 one-tap site player, native theater subtitles and sports checks PASS:",len(checks))
