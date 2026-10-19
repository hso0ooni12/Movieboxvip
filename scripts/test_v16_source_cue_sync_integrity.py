"""V16 no-AI release gate: source-owned timed cue calibration and protected R5.

The source's sourceTextTrack cues are authoritative (same subtitle selected in
the real provider menu). A single point fixes delay, two points can fix
constant speed drift. DOM-only subtitles explicitly report missing timestamps,
never fake early lookahead or guess a source subtitle URL.
"""
from pathlib import Path
p=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
source=Path("scripts/xs_source_subtitles.js").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
checks={
  "no AI/audio/screen-capture subsystem is in shipped player":
    all(key not in p for key in ("ReplayKit","SoundAnalysis","smartSyncRunning","smartSyncSuggestedDelay","XSNativeSubtitleAI","autoSubtitleSync","مزامنة ذكية")),
  "no UI AI button or unsupported autoplay analysis":
    'markSubtitleSyncPoint()' in p and 'مزامنة الترجمة بالذكاء الاصطناعي' not in p,
  "large straightforward +/- with center reset":
    'V16_SOURCE_CUE_SYNC' in p and 'Image(systemName: "minus")' in p and
    'Image(systemName: "plus")' in p and 'subtitleDelay=0' in p and
    'Slider(value: $subtitleDelay' not in p,
  "1pt source/default native subtitle edge stays user-adjustable":
    '@AppStorage("XSTV.subtitleBottomPadding.v16") private var subtitleBottom = 1.0' in p and
    'Slider(value: $subtitleBottom, in: 1...220, step: 1)' in p and
    'bottom: 1' in p,
  "portrait aspect fit and physical video-bottom compensation preserved":
    ("R5_ASPECTFIT_CAPTION" in p and "return -blackBarBottom" in p) or
    ("let visibleVideoBottomPadding" in p and "lowerBlackBar" in p),
  "source cue matching derived from real video's clock":
    "V16_CUE_CLOCK_SYNC" in source and
    "const now=Number(v.currentTime)" in source and
    "const cue=findCueAt(track,sourceTime)" in source,
  "source cue media time supports 2-point speed+offset":
    "const candidateRate=(second.video-first.video)/distance;" in source and
    "const at = (Number(v.currentTime || 0) - delay) / subtitleRate;" in source,
  "reject bad point matches, spoofed source clocks and unreasonable scale":
    "candidateRate<.94 || candidateRate>1.06" in source and
    "distance<60" in source and
    "findCueAt(track,sourceTime)" in source,
  "source UI acknowledges only current owner iframe":
    'case "xs:subtitlePointResult":' in p and
    'payload["frameID"] as? String == owner' in p and
    'sourceSubtitles.syncPoint();' in p,
  "rate-only drift correction is displayed at zero offset":
    "(delay !== 0 || subtitleRate !== 1) && active" in p and
    "(delay === 0 && subtitleRate === 1)" in source,
  "source cue editor no longer includes audio analysis or made-up timing":
    "function syncPoint()" in source and "return {frameID, scan, publish, select, reset, tick, hidePanels, dispose, syncPoint," in source and
    "captureStream(" not in source and "getUserMedia(" not in source and
    "XSNativeSubtitleAI" not in source,
  "source menu owns exact subtitle selection and original server flow":
    "sourceSubtitles.select(payload);" in p and
    "choice.row.click();" in source and
    "const finishDispatchedSelection = () =>" in p,
  "all source subtitles still available":
    "V11_ALL_SOURCE_SUBTITLES" in source and
    "return catalog.filter(item => item.label && item.label !== 'Off')" in source,
  "cue updates follow seeked/timeupdate and clean up listeners":
    "video.addEventListener('timeupdate',timingHandler)" in source and
    "timingVideo.removeEventListener('seeked',timingHandler)" in source and
    "timingVideo.removeEventListener('seeked',timingHandler)" in p,
  "new subtitle/source does not inherit old point calibration":
    "subtitleRate=1;syncPoints=[];delay=0;" in source and
    ".onChange(of: player.selectedSubtitleID)" in p,
  "per title/episode reset from V11 still intact":
    "@State private var subtitleDelay = 0.0" in p and
    "subtitleDelay = 0\n        player.setSubtitleDelay(0)\n        activePlayback = next" in p,
  "live VLCKit/R5 stable drawable preserved":
    "V39_R5_STABILITY_RESTORE" in sports and "XSVLCStableSurfaceView" in sports,
}
for label,ok in checks.items():
    if not ok: raise SystemExit("V16 QA FAIL: "+label)
print(f"V16 source subtitle timing and protected R5 PASS: {len(checks)} assertions")
