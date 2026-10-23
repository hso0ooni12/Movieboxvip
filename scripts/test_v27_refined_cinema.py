"""V27 premium UI regression tests executed after app_v27 layout script."""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
ui=Path("FrameNative/Views/XSExperienceV27.swift").read_text()
web=Path("FrameNative/Views/XSETWatchNativeDetailPlayer.swift").read_text()
native=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
  "Root has exactly four original tab categories": all(x in root for x in
      ("XSHomeV27()","XSBrowseV27(kind: .movie)",
       "XSBrowseV27(kind: .series)","XSSportsLiveViewV33()")),
  "Sports player remains same": "XSVLCStableSurfaceView" in sports,
  "App is native, not website home": "XSETWatchPortalView" not in root,
  "Cinematic sections and search": all(x in ui for x in
      ("struct XSHomeV27", "struct XSBrowseV27",
       "struct XSSearchV27","struct XSDetailV27")),
  "Poster carousels and full titles": all(x in ui for x in
      ("LazyHStack", "LazyVGrid", "XSThumbnail27", "XSSectionHeader27")),
  "Accessibility reduced motion honored": "accessibilityReduceMotion" in ui+root,
  "Source-neutral rating and streaming availability": "media.isPlayable" in ui,
  "Episodes remain selectable": all(x in ui for x in
      ("season: ep.season, episode: ep.number",
       "XSETWatchNativeDetailPlayer(url: selected.url")),
  "Native catalog independent of sports IPTV": all(x not in native for x in
      ("get_vod_streams", "player_api.php")),
  "No automatic video container relocation": all(x not in web for x in
      ('if(window.top===window)window.__xstvEnterTheater();',
       'e.stopImmediatePropagation();',
       'postMessage({type:"xstv-player-played"}')),
  "Optional theater still exists": "window.__xstvEnterTheater" in web and
      "func toggleTheater()" in web,
  "Original website captions not replaced or simulated": all(x not in web for x in
      ("addTextTrack(", "track.mode=", "currentVideoSubTitleIndex")),
  "Site player keeps stall reporting": "35_000_000_000" in web and
      "SFSafariViewController" in web,
}
for name,ok in checks.items():
    if not ok: raise SystemExit("V27 regression FAIL: "+name)
print("V27 premium UI and subtitle stability checks PASS:",len(checks))
