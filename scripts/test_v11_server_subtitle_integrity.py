"""V11 post-generation playback regression gates.

Run after V10/R5 protection and V11 final patch. Real source clicks, subtitle
cue success and provider latency remain subject to iPhone device testing.
"""
from pathlib import Path

player=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
source=Path("scripts/xs_source_subtitles.js").read_text()
tests=Path("scripts/test_source_subtitles.cjs").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()

checks={
 "all source CC rows exposed without Arabic/English restriction":
    "V11_ALL_SOURCE_SUBTITLES" in source
    and "return catalog.filter(item => item.label && item.label !== 'Off');" in source
    and "preferredLanguage(item)" not in source
    and "items: visibleCatalog().map" in source,
 "exact source row selection protected":
    "choice.row.click();" in source
    and "if (match && loaded)" in source
    and "frameID" in source
    and "requestID" in source,
 "subtitle variants and source languages tests":
    "SDH variant stays selectable" in tests
    and "duplicate language rows preserve distinct" in tests
    and "'Español'" in tests,
 "caption cue rendering efficient for long subtitles":
    "V11_BINARY_CUE_SYNC" in source
    and "while (low <= high)" in source
    and "lines.join" in source
    and "track.cues" in source,
 "subtitle readable within original player cue bounds":
    "max-width', '92%'" in source
    and "'text-shadow'" in source
    and "sourceCaptionNodes()" in source,
 "subtitle timing scoped to current content, not stored globally":
    "@State private var subtitleDelay = 0.0" in player
    and '@AppStorage("XSTV.subtitleDelay")' not in player,
 "every player open resets cue offset to zero":
    "subtitleDelay = 0\n            player.setSubtitleDelay(0)" in player,
 "auto-next episode also resets offset":
    "player.reset()\n        // The same screen" in player
    and "subtitleDelay = 0\n        player.setSubtitleDelay(0)\n        activePlayback = next" in player,
 "switching servers clears old subtitle owner state":
    "subtitleFrameID = nil\n        subtitleGeneration = -1\n        subtitleOptions = []" in player
    and 'selectedSubtitleID = nil\n        captionText = ""' in player,
 "source-owned server selection is still exact and single tap":
    'var payload: [String: Any] = ["action": "server", "name": server.name]' in player
    and 'if let provider = server.provider { payload["provider"] = provider }' in player
    and "function selectServerRow(name, quality)" in player
    and "const finishDispatchedSelection = () =>" in player,
 "server menu rendered faster without hiding Backup handoff":
    "}, 110);" in player,
 "source-subtitle ack source plus UI success guard preserved":
    "sourceSubtitles.select(payload);" in player
    and "player.pendingSubtitleID" in player
    and "player.selectedSubtitleID == expected" in player
    and "subtitleSelectionError == nil" in player,
 "off selection remains available":
    "waitingForSubtitleID = \"off\"" in player
    and "function finishFailure(request, message)" in source,
 "reset re-enables hidden timed cue":
    "timingTrack.mode = 'showing'" in source
    and "timingTrack = null;" in source,
 "R5 VLC surface preserved":
    "V39_R5_STABILITY_RESTORE" in sports
    and "XSVLCStableSurfaceView" in sports
    and "player.drawable = drawable" in sports
}
for label,passed in checks.items():
    if not passed:
        raise SystemExit("V11 regression FAIL: "+label)
print(f"V11 source subtitle & server integrity PASS: {len(checks)} source invariants")
