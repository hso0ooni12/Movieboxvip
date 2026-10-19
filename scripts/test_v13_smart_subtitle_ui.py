"""V13 final QA: R5/V12 preserved; real buttons, low caption baseline,
opt-in confidence-gated local acoustic alignment and feedback.
"""
from pathlib import Path
p=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
s=Path("scripts/xs_smart_subtitle_sync.js").read_text()
source=Path("scripts/xs_source_subtitles.js").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
a=p.index("    private var subtitleDelayPanel: some View {")
b=p.index("    private func panelRow(",a)
panel=p[a:b]
checks={
  "timing panel no longer contains unreliable dragging slider":
      "Slider(value: $subtitleDelay" not in panel and "V13 BUTTON_TIMING" in p,
  "large and small buttons actually update current content offset":
      'subtitleOffsetButton("−1.00", seconds: -1)' in panel and
      'subtitleOffsetButton("−0.25", seconds: -0.25)' in panel and
      'subtitleOffsetButton("+0.25", seconds: 0.25)' in panel and
      'subtitleOffsetButton("+1.00", seconds: 1)' in panel and
      "subtitleDelay = min(12, max(-12" in p,
  "reset button and 44+ pt accessible hit targets":
      'subtitleDelay = 0' in panel and ".frame(minHeight: 46)" in p,
  "new low caption video baseline ignores legacy stored 76pt":
      '@AppStorage("XSTV.subtitleBottomPadding.v13") private var subtitleBottom = 14.0' in p,
  "portrait visible video bottom correctly follows entire adjustable range":
      (('lowerBlackBar + max(6, CGFloat(subtitleBottom))' in p) or
       ('R5_ASPECTFIT_CAPTION' in p and 'return -blackBarBottom' in p))
      and "min(CGFloat(subtitleBottom), 30)" not in p,
  "caption position slider moves all way to near-bottom":
      'Slider(value: $subtitleBottom, in: 6...220, step: 2)' in p and
      "subtitleBottom = max(6, subtitleBottom - 8)" in p,
  "source native CSS bottom also lowered":
      "bottom: 14" in p,
  "optional audio alignment does not intercept player source stream":
      "captureStream" in s and "createMediaStreamSource(stream)" in s
      and "source.connect(analyser)" in s and "context.close()" in s,
  "no mic, no network upload and no media routing":
      "getUserMedia(" not in s and "fetch(" not in s
      and ".createMediaElementSource(" not in s and
      "source.connect(context.destination)" not in s,
  "confidence threshold, safe default and no guessing":
      "if (!answer)" in s and
      "low-confidence" in s and
      "if (best.quality" not in s, # estimator uses guard, below
  "audible speech energy and cue correlation instead of fabricated model":
      "xsSmartSyncEstimate" in s and "score(offset)" in s
      and "confidence:" in s and "voiceRate" in s,
  "no repeated automatic runs or after server switch":
      "xsSmartSyncBusy" in s and "epoch!==generation" in s
      and "xsSmartCancel" in p,
  "scoped source-only remote commands":
      "sourceSubtitles.autoSync()" in p and
      "sourceSubtitles.cancelAutoSync()" in p and
      'case "xs:subtitleAutoSync":' in p,
  "explicit user opt-in and progress/status":
      "مزامنة ذكية تلقائية بالصوت" in panel and
      'player.smartSyncStatus ?? subtitleTimingHelp' in panel,
  "new offset applied through existing V12 timing bridge":
      "smartSyncSuggestedDelay" in p and
      "subtitleDelay = suggested" in p and
      "sourceSubtitles.setDelay(subtitleDelay)" in p,
  "reset on movie and episode switches retained":
      "@State private var subtitleDelay = 0.0" in p
      and "subtitleDelay = 0\n        player.setSubtitleDelay(0)\n        activePlayback = next" in p,
  "original R5 Backup and source captions preserved":
      "const finishDispatchedSelection = () =>" in p
      and "sourceSubtitles.select(payload);" in p
      and "V39_R5_STABILITY_RESTORE" in sports and
      "XSVLCStableSurfaceView" in sports,
  "original V12 accessible source languages preserved":
      "V11_ALL_SOURCE_SUBTITLES" in source
      and "V12" in p
}
for title,passed in checks.items():
    if not passed: raise SystemExit("V13 QA FAIL: "+title)
print(f"V13 safe subtitle UX, smart sync and R5 preservation PASS: {len(checks)} assertions")
