"""V22 verification runs on GitHub before signing iOS app."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
project=Path("project-native.yml").read_text()
source=Path("FrameNative/Services/XSOpenCinemaSource.swift").read_text()
ui=Path("FrameNative/Views/XSOpenCinemaExperience.swift").read_text()
player=Path("FrameNative/Views/XSVODVLCPlayerView.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
    "No Xtream catalog active": "XSVODHomeView()" not in root and
        "XSVODBrowseView" not in root and "XSOpenCinemaHomeView()" in root,
    "Legacy and Febbox sources disconnected": "FrameXTVPlayerScreen" not in root and
        "XSFebboxPremium" not in root,
    "Only live Sports uses Xtream": "XSSportsLiveViewV33()" in root and
        "XSVLCStableSurfaceView" in sports,
    "VOD services excluded from app binary": all(x in project for x in
        ("- Views/XSVODPremiumExperience.swift",
         "- Services/XSVODService.swift",
         "- Services/XSVODRedirectResolver.swift")),
    "Public license filter in source": all(x in source for x in
        ("creativecommons.org/licenses/by/", "creativecommons.org/licenses/by-sa/",
         "creativecommons.org/publicdomain/zero/")),
    "No Xtream / torrents scraped by open source": all(x not in source+ui for x in
        ("player_api.php", "get_vod_streams", "febbox.com", "framextv.xyz",
         "torrentio", "magnet:", "thepiratebay")),
    "Archive titles use official metadata": "archive.org/metadata/" in source and
        "archive.org/advancedsearch.php" in source,
    "No invented movies or streams": "bestVideoFile(in: files)" in source and
        "allowedLicense(license)" in source,
    "Premium original-style VLC controls retained": all(x in player for x in
        ("gobackward.10","goforward.10","Slider(value:","panelOverlay")),
    "No fabricated Arabic subtitle": "لم يُتحقق من وجود ترجمة عربية" in ui,
    "Captions only from real source": "subtitleFile(for: video, files: files)" in source,
    "No empty non-playable titles": "guard allowedLicense(license), let video" in source,
    "No blank placeholder stream": "item.playableURL" in ui,
    "No account secrets in open library": "XSIPTVEmbeddedConfig" not in source+ui,
}
for name, passed in checks.items():
    if not passed: raise SystemExit("V22 FAIL: " + name)
print("V22 free open cinema, sports-only account, original chrome PASS",len(checks),"checks")
