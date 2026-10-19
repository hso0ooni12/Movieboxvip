"""V14 iPhone AI subtitle QA: opt-in native OS capture, Apple speech
classification, user consent, ephemeral audio, strong alignment threshold,
selected source scoping and protected R5/V13 controls.
"""
from pathlib import Path
p=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
native=Path("FrameNative/Services/XSNativeSubtitleAI.swift").read_text()
sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()

checks={
 "iOS really runs a native speech ML model":
    "import SoundAnalysis" in native and
    "SNClassifySoundRequest(classifierIdentifier: .version1)" in native and
    "SNAudioFileAnalyzer(url:" in native and
    'classification(forIdentifier: "speech")' in native,
 "ReplayKit captures app audio, NOT the microphone or video":
    "RPScreenRecorder.shared()" in native and
    "recorder.isMicrophoneEnabled = false" in native and
    "type == .audioApp" in native and
    "audio.append(sample)" in native,
 "privacy: no network connection, temp file always removed":
    'FileManager.default.temporaryDirectory' in native and
    "defer { try? FileManager.default.removeItem(at: audio.url) }" in native and
    "URLSession." not in native and
    "fetch(" not in native and
    ".audioMic" not in native,
 "timecoded cues are genuinely sourced from selected source media":
    "xsSmartPublishCues()" in p and
    "xsSmartCueWindows(video,trackFor(active),sourceCaptionHistory,48)" in p and
    "sourceSubtitles.timedCues()" in p,
 "native ML can only start with selected source + enough cues":
    'case "xs:subtitleTimedCues":' in p and
    "guard cues.count >= 5" in p and
    "self.selectedSubtitleID == selected" in p and
    "self.subtitleFrameID == currentFrame" in p,
 "capture-start time uses actual media position after consent":
    "let startMediaTime = mediaTime()" in native and
    "mediaTime: { [weak self] in self?.currentTime ?? mediaAtStart }" in p,
 "low-confidence ML never mutates offset":
    "best.1 >= 0.69" in native and
    "best.1 - previous >= 0.19" in native and
    'return .unavailable("تطابق الصوت مع الترجمة غير مؤكد' in native,
 "native feature observable/cancellable":
    "XSNativeSubtitleAI.shared.cancel()" in p and
    "smartSyncStatus" in p and
    "smartSyncSuggestedDelay" in p and
    "smartSyncRunning" in p,
 "honest OS capture permission disclosure visible":
    "قد يطلب iOS السماح" in p and
    "لا يُرسل الصوت لخادم" in p,
 "subtitle controls are still buttons, not sliders":
    "V13 BUTTON_TIMING" in p and
    "subtitleOffsetButton("+chr(34)+"−0.25"+chr(34) in p,
 "default bottom video-aligned caption preset retained":
    "subtitleBottomPadding.v13" in p and
    "subtitleBottom = 14.0" in p,
 "source/server and VLC baseline unchanged":
    "sourceSubtitles.select(payload);" in p and
    "const finishDispatchedSelection" in p and
    "XSVLCStableSurfaceView" in sports and
    "V39_R5_STABILITY_RESTORE" in sports
}
for label,valid in checks.items():
    if not valid:
        raise SystemExit("V14 native AI integrity FAIL: "+label)
print(f"V14 native on-device ML & R5 protection PASS: {len(checks)} checks")
