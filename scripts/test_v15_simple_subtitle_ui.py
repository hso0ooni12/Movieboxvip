"""V15 release guards — simplified subtitle timing + visible-video 1pt
caption baseline, bounded native opt-in AI and protected R5/V14 features.

Prior R5/V10..V14 tests execute BEFORE the V15 final patch.
"""
from pathlib import Path
p=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
engine=Path("FrameNative/Services/XSNativeSubtitleAI.swift").read_text()
source=Path("scripts/xs_source_subtitles.js").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
begin=p.find("    // V15_TWO_BUTTON_TIMING:")
end=p.find("    private func panelRow(",begin)
assert begin>=0 and end>begin, "V15 controls not rendered"
panel=p[begin:end]
checks={
 "only two large + and - buttons in the timing control":
     panel.count('Image(systemName: "minus")')==1 and
     panel.count('Image(systemName: "plus")')==1 and
     'subtitleOffsetButton' not in panel and
     'Slider(value: $subtitleDelay' not in panel,
 "simple fixed 0.25s per press with proper +/- polarity":
     'stepSubtitleTiming(-0.25)' in panel and
     'stepSubtitleTiming(0.25)' in panel and
     '(subtitleDelay + seconds) * 4' in panel,
 "timing value resets with one centered tap":
     'subtitleDelay = 0' in panel and
     'accessibilityLabel("التوقيت الحالي، اضغط للتصفير")' in panel,
 "large one-tap controls meet ergonomic targets":
     panel.count('.frame(maxWidth: .infinity, minHeight: 60)')==2,
 "low source/Swift captions preset ONE point":
     '@AppStorage("XSTV.subtitleBottomPadding.v15") private var subtitleBottom = 1.0' in p
     and "bottom: 1" in p,
 "appearance reset returns to lower position":
     'subtitleBottom = 1' in p,
 "position control physically allows ONE point":
     'Slider(value: $subtitleBottom, in: 1...220, step: 1)' in p
     and 'subtitleBottom = max(1, subtitleBottom - 8)' in p
     and 'min(CGFloat(subtitleBottom), 30)' not in p,
 "portrait remains aligned to visible VIDEO, not whole screen":
     ('R5_ASPECTFIT_CAPTION' in p or 'let visibleVideoBottomPadding' in p)
     and 'captionLetterboxAdjustment' in p or 'let lowerBlackBar' in p,
 "smart AI audio alignment still provided on device":
     'SNClassifySoundRequest(classifierIdentifier: .version1)' in engine
     and 'RPScreenRecorder.shared()' in engine
     and 'mediaTime: { [weak self] in self?.currentTime ?? mediaAtStart }' in p,
 "AI correlation now refuses ambiguous candidates":
     'V15_CONFIDENCE_GATE' in engine
     and 'best.1 - runnerUp >= 0.07' in engine,
 "no unbounded AI spinner when source refuses cue data":
     '20_000_000_000' in p
     and 'self.smartSyncStatus == "جارٍ تجهيز المزامنة الذكية…"' in p,
 "DOM-only sources collect actual cue events at ZERO initial offset":
     'if (active && v && !delay) captureSourceCaption(v);' in p,
 "source auto-sync waits for real cues, not invented timestamps":
     'Date.now()-began>14000' in p
     and 'cues.length>=5' in p
     and 'generation!==epoch' in p
     and 'xsSmartCueWindows(video,trackFor(active),sourceCaptionHistory,48)' in p,
 "native AI keeps mic/video private and temporary audio ephemeral":
     'recorder.isMicrophoneEnabled = false' in engine
     and 'type == .audioApp' in engine
     and 'defer { try? FileManager.default.removeItem(at: audio.url) }' in engine,
 "original source CC list/selection remains operational":
     'V11_ALL_SOURCE_SUBTITLES' in source
     and 'sourceSubtitles.select(payload);' in p
     and 'case "xs:subtitleSelected", "xs:subtitleSelectionFailed":' in p,
 "server/Backup and live VLC not touched":
     'const finishDispatchedSelection = () =>' in p
     and 'XSVLCStableSurfaceView' in sports
     and 'V39_R5_STABILITY_RESTORE' in sports,
 "new movie and next episode subtitle timing still resets":
     '@State private var subtitleDelay = 0.0' in p
     and 'subtitleDelay = 0\n        player.setSubtitleDelay(0)\n        activePlayback = next' in p,
}
for label,ok in checks.items():
    if not ok: raise SystemExit("V15 QA FAIL: "+label)
print(f"V15 subtitle simplicity/AI-safety R5 QA PASS: {len(checks)} checks")
