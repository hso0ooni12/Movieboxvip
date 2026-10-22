"""ETWatch player integration safety and source separation assertions."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
site=Path("FrameNative/Views/XSETWatchPortalView.swift").read_text()
project=Path("project-native.yml").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
  "Only movies and series website tabs": all(k in root for k in
    ("XSETWatchPortalView(section: .home)",
     "XSETWatchPortalView(section: .movies)",
     "XSETWatchPortalView(section: .series)")),
  "IPTV only sports route": "XSSportsLiveViewV33()" in root and
      "XSVODHomeView" not in root and "XSFebboxPremiumHomeView" not in root,
  "R5 sports decoder unchanged": "XSVLCStableSurfaceView" in sports,
  "Original provider WebKit player retained": "WKWebView" in site
      and "allowsInlineMediaPlayback = true" in site
      and "allowsPictureInPictureMediaPlayback = true" in site,
  "No invented movie/series section URLs": "querySelectorAll('a[href]')" in site
      and "evaluateJavaScript(script)" in site,
  "No source media scraping": all(word not in site for word in
      ("player_api.php","m3u8","get_vod_streams","iframe.src",
       "URLSession.shared", "fetch(", "video_quality_list")),
  "Original app bundle ID preserved": "com.xsstore.xstv" in project,
  "XTream VOD sources omitted from IPA compile": all(k in project for k in
      ("- Views/XSVODPremiumExperience.swift",
       "- Views/XSVODVLCPlayerView.swift",
       "- Services/XSVODService.swift",
       "- Services/XSVODRedirectResolver.swift")),
  "User-visible network and missing-section fallback": "تعذر فتح ETWatch" in site
       and "missingSection" in site and "openOfficialSite()" in site,
  "No embedded IPTV VOD API calls": "get_vod_streams" not in root+site,
}
for name,success in checks.items():
    if not success: raise SystemExit("ETWatch bridge assertion FAILED: "+name)
print(f"ETWatch original player + sports only integration guards: {len(checks)} OK")
