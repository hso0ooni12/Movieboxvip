"""V27: prevent regression to forced cinema/fullscreen and cluttered Home."""
from pathlib import Path

home = Path("FrameNative/Views/XSCinemaNativeExperience.swift").read_text()
player = Path("FrameNative/Views/XSETWatchNativeDetailPlayer.swift").read_text()
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text()
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
project = Path("project-native.yml").read_text()

js_start = player.index('        let script = """')
js_end = player.index('        userContent.addUserScript(', js_start)
script = player[js_start:js_end]
playing_hook = script[script.index("function observeVideo()"):script.index("let autoClicked = false;")]

checks = {
 "Home is native SwiftUI": "XSCinemaNativeHomeView()" in root and "XSCinemaNativeBrowseView(kind:.movie)" in root,
 "Sports untouched": "XSSportsLiveViewV33()" in root and "XSVLCStableSurfaceView" in sports,
 "Home shows only streamlined editorial rails": all(t in home for t in (
   '"أفلام تستحق المشاهدة"', '"مسلسلات مختارة"', 'featuredHero(featured)',
   '"CINEMA"', '"البحث في السينما"')),
 "Removed cluttering duplicate nav cards": "navCard(" not in home and "مكتبة مستقلة عن IPTV" not in home,
 "Subtle premium reveal motion": 'withAnimation(.easeOut(duration: 0.42))' in home and
    '.offset(y: revealed ? 0 : 15)' in home,
 "Theater control is an explicit user choice": 'Button { state.toggleTheater() }' in player
    and 'Button {' in player and '"تصغير"' in player,
 "Theater never activated on player lifecycle": 'window.__xstvEnterTheater()' not in playing_hook
    and 'window.__xstvEnterTheater();' not in playing_hook,
 "Website fullscreen buttons untouched": 'stopImmediatePropagation' not in script and
    'document.addEventListener("click",function(e)' not in script,
 "Video playing event still tracked": "'playing','timeupdate','waiting'" in script
    and 'post(event,seconds)' in script,
 "No forced video attribute modifications": 'setAttribute("playsinline"' not in script
    and "v.playsInline=true" not in script,
 "Theater succeeds only when site container exists": 'const target = candidate();' in script
    and 'if (!target) return false;' in script
    and '(result as? Bool) == true' in player,
 "Subtitle/player controls remain website-owned": 'WKWebView' in player
    and 'websiteDataStore = .default()' in player,
 "Selected episode navigation preserved": 'selectedWebsiteEpisode = ep' in home
    and 'episode: selectedWebsiteEpisode?.number' in home,
 "No IPTV VOD or Febbox": "get_vod_streams" not in root+home+player
    and "XSFebboxPremiumHomeView" not in root,
 "Old website-wide browser excluded": "- Views/XSETWatchPortalView.swift" in project,
}
for name, passed in checks.items():
 if not passed: raise SystemExit("V27 regressions FAIL: " + name)
print("V27 premium home and opt-in caption-safe theater regressions PASS:", len(checks))
