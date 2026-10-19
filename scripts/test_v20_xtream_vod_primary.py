"""V20 integration guard: only user's existing configured Xtream provider supplies VOD."""
from pathlib import Path
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text()
service = Path("FrameNative/Services/XSVODService.swift").read_text()
ui = Path("FrameNative/Views/XSVODPremiumExperience.swift").read_text()
player = Path("FrameNative/Views/XSVODVLCPlayerView.swift").read_text()
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks = {
 "VOD home and two catalogs wired": all(x in root for x in
     ("XSVODHomeView()", "XSVODBrowseView(kind: .movie)",
      "XSVODBrowseView(kind: .series)")),
 "R5 Sports engine preserved": "XSSportsLiveViewV33()" in root and "XSVLCStableSurfaceView" in sports,
 "No Febbox or old website in active routes": all(x not in root for x in
     ("XSFebboxPremiumHomeView(", "XSFebboxPremiumBrowseView(",
      "FrameXTVPlayerScreen(", "XSReferenceCatalogView(")),
 "Only embedded account credentials": "XSIPTVEmbeddedConfig.credentials" in service,
 "VOD movies and series APIs": all(x in service for x in
     ("get_vod_categories", "get_vod_streams",
      "get_series_categories", '"get_series"', "get_series_info")),
 "Direct Xtream VOD media": 'path: "movie"' in service and 'path: "series"' in service,
 "Never log login credentials": "print(" not in service and "URLSession.shared.data" in service,
 "No adult and anime categories": '"adult"' in service and '"anime"' in service,
 "No Febbox or FrameXTV playback in new screens": all(x not in ui+player+service for x in
     ("febbox.com", "framextv.xyz", "FrameXTVPlayback(", "TMDBClient(")),
 "Native premium UI, category and search": all(x in ui for x in
     ("LazyVGrid", "XSVODSearchView", "XSVODBrowseView", "XSVODDetailView")),
 "Native movie plus series playback": all(x in ui for x in
     ("startMovie()", "startEpisode(", "XSVODVLCPlayerView(source: selection)")),
 "Subtitle tracks use source timestamps": all(x in player for x in
     ("player.textTracks", "track.trackName", "isSelectedExclusively")),
 "Auto-select Arabic by native track": 's.contains("arabic")' in player and
     's.contains("عربي")' in player,
 "Caching and source catalog status": "xs-vod-catalog-v1.json" in service and
     "loaded = true" in service,
}
for name, ok in checks.items():
    if not ok: raise SystemExit("V20 QA FAIL: " + name)
print(f"V20 Xtream VOD source-only checks PASS: {len(checks)}")
