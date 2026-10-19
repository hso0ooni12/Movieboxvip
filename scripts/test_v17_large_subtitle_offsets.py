"""V17 isolated regression gates for >60-second subtitle problems.

Do not disguise release mismatch as a hard-coded ±60s cap. The new correction
reaches ±600s with two visible controls and native long-press options.
Never auto-switch subtitle release or break source-owned R5 playback.
"""
from pathlib import Path
p=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
source=Path("scripts/xs_source_subtitles.js").read_text()
tests=Path("scripts/test_source_subtitles.cjs").read_text()
checks={
  "no artificial +/-60 seconds manual cap":
      "subtitleDelay=min(600,max(-600,shifted))" in p and
      "subtitleDelay=min(60,max(-60,shifted))" not in p,
  "simple large +- tap still ±0.25s":
      "adjustSubtitleClock(-0.25)" in p and
      "adjustSubtitleClock(0.25)" in p and
      'Image(systemName: "minus")' in p and
      'Image(systemName: "plus")' in p,
  "native hold menu handles 60+ second mismatch without hundreds of taps":
      "تقديم دقيقة" in p and "تأخير دقيقة" in p and
      "تأخير 5 دقائق" in p and "تقديم 5 دقائق" in p and
      p.count(".contextMenu {") >= 2,
  "only original selected source cue determines release fit":
      "V17_SOURCE_RELEASE_CHECK" in source and
      "const v=findVideo(),t=active&&trackFor(active);" in source and
      "end>length+60?'late-ending':'ok'" in source,
  "no auto fallback to unrelated language/video/subtitle":
      "reportReleaseFit();" in source and
      "choice.row.click();" in source and
      "sourceSubtitles.select(payload);" in p,
  "native warning visible and scoped to selected source frame":
      "subtitleReleaseWarning" in p and
      'case "xs:subtitleReleaseFit":' in p and
      'payload["frameID"] as? String == frame' in p and
      'Label(warning, systemImage: "exclamationmark.triangle")' in p,
  "source tests distinguish actual impossible tail vs credits":
      "selected source track warns only when subtitle cues extend" in tests and
      "normal credits gap is NOT presented" in tests,
  "no AI/ReplayKit or mic capture reintroduced":
      all(term not in p for term in ("ReplayKit","SoundAnalysis","autoSubtitleSync","XSNativeSubtitleAI")),
  "remaining R5/V16 protected source clock and position preserved":
      "V16_SOURCE_CUE_SYNC" in p and
      "sourceSubtitles.syncPoint()" in p and
      '@AppStorage("XSTV.subtitleBottomPadding.v16")' in p and
      "const finishDispatchedSelection = () =>" in p,
}
for label,ok in checks.items():
    if not ok: raise SystemExit("V17 QA FAILED: "+label)
print(f"V17 large subtitle offset and release-fit PASS: {len(checks)} guards")
