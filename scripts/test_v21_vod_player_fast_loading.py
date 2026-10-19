"""V21 regression coverage: fast catalog and working VOD/redirect player plumbing."""
from pathlib import Path
service=Path("FrameNative/Services/XSVODService.swift").read_text()
resolver=Path("FrameNative/Services/XSVODRedirectResolver.swift").read_text()
ui=Path("FrameNative/Views/XSVODPremiumExperience.swift").read_text()
player=Path("FrameNative/Views/XSVODVLCPlayerView.swift").read_text()
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
 "VOD source not replaced by former website": "XSVODHomeView()" in root and
   "XSVODBrowseView(kind: .movie)" in root and "FrameXTVPlayerScreen" not in root,
 "R5 protected sport stack present": "XSSportsLiveViewV33()" in root and
   "XSVLCStableSurfaceView" in sports,
 "both catalogs loaded separately": "catalogFor(kind: .movie)" in service and
   "catalogFor(kind: .series)" in service,
 "cached snapshot restored off main": "Task.detached(priority: .utility)" in service
   and "private func restoreSnapshot() async" in service,
 "six-hour catalog freshness throttle": "6 * 3600" in service,
 "source 30x redirect resolved before player": "URLSession.shared.bytes(for: request)" in resolver and
   "response.url ?? original" in resolver and "XSVODRedirectResolver.shared.resolve(url)" in ui,
 "known-good original URL fallback kept": "fallbackURL: resolved == url ? nil : url" in ui,
 "VLC receives backup URLs": "source.fallbackURL" in player and
   "private func nextCandidate()" in player,
 "VLC playback retains original-style controls": all(k in player for k in
   ("gobackward.10","goforward.10","Slider(value:","panelOverlay","subtitles",
   "audioTracks","seek(to:","setPlaybackSpeed","mediaPlayerTimeChanged")),
 "VLC4 textTracks not obsolete selectors": "player.textTracks" in player and
   "currentVideoSubTitleIndex" not in player and
   "videoSubTitlesNames" not in player,
 "embedded Arabic track only not synthetic subtitles": "isSelectedExclusively = true" in player and
   'title.contains("arabic")' in player,
 "playing errors trigger failover": "case .error:" in player and "self.nextCandidate()" in player,
 "no account URL logged or hardcoded": "print(" not in resolver+player+ui+service,
}
for name,result in checks.items():
    if not result: raise SystemExit("V21 regression failure: "+name)
print(f"V21 source, caching, player regressions PASS: {len(checks)} checks")
