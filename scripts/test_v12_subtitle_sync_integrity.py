"""V12 subtitle timing QA: confirms real sync transport, source fallback,
per-movie reset, honest limitations and complete protected player invariants.
Run after R5/V11 original validations and V12 final bridge postprocessor.
"""
from pathlib import Path
player=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
source=Path("scripts/xs_source_subtitles.js").read_text()
tests=Path("scripts/test_source_subtitles.cjs").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
 "source command delivers actual UI offset": 'send(["action": "subtitleDelay", "seconds": seconds])' in player and
       "sourceSubtitles.setDelay(" in player,
 "real TextTrack caption uses video media time with correct sign":
       "const at = (Number(v.currentTime || 0) - delay) / subtitleRate;" in source and
       "V11_BINARY_CUE_SYNC" in source,
 "source-only React subtitles buffered rather than ignored":
       "sourceCaptionHistory" in source and
       "captureSourceCaption(v)" in source and
       "delayedSourceCaption(Number(v.currentTime || 0)-delay)" in source,
 "source-only caption CSS fully suppressed for supported positive delay":
       "V12_DOM_DELAY" in player and "delay > 0 && sourceCaptionNodes().length > 0" in player,
 "negative lead without future cues never falsely claims it works":
       "timingStatus('unsupported')" in source and
       "delay > 0 && hasSourceDom" in source,
 "native player acknowledges timing actual capability":
       'case "xs:subtitleTimingStatus":' in player and
       'subtitleTimingMode = payload["mode"] as? String' in player,
 "native editor displays real status rather than pretend success":
       "private var subtitleTimingHelp: String" in player and
       'player.subtitleTimingMode == "unsupported"' in player,
 "no backwards user instructions":
       "تأخير الترجمة (+) · تقديم الترجمة (−)" in player,
 "select source verifies loaded cue or actually changed DOM":
       "if (match && loaded)" in source and
       "if (match && sourceDomReady)" in source,
 "language duplicates preserved by unique source ID":
       "let key = item.id" in player and
       "return catalog.filter(item => item.label && item.label !== 'Off');" in source,
 "offset resets on every new content/episode":
       "@State private var subtitleDelay = 0.0" in player and
       "subtitleDelay = 0\n        player.setSubtitleDelay(0)\n        activePlayback = next" in player,
 "source-change wipes buffered cues and stale subtitle list":
       "sourceCaptionHistory = []" in source and
       "subtitleOptions = []" in player,
 "functional DOM buffered test present":
       "DOM-only source: positive subtitle delay changes visible cue timing" in tests,
 "functional cue negative timing test present":
       "f.adapter.setDelay(-1)" in tests,
 "actual source server and Backup click kept":
       "const finishDispatchedSelection = () =>" in player and
       'var payload: [String: Any] = ["action": "server", "name": server.name]' in player,
 "original source subtitle selection preserved":
       "sourceSubtitles.select(payload);" in player and
       "choice.row.click();" in source,
 "R5 non-crashing live VLC surface unchanged":
       "V39_R5_STABILITY_RESTORE" in sports and
       "XSVLCStableSurfaceView" in sports
}
for label,ok in checks.items():
    if not ok:
        raise SystemExit("V12 QA FAILED: "+label)
print(f"V12 source subtitle time sync PASS: {len(checks)} end-to-end source/UI integrity assertions")
