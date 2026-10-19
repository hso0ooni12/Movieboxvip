"""V14 native iPhone subtitle intelligence over stable R5/V13.

WKWebView/iOS does NOT expose HTMLMediaElement.captureStream, so browser
acoustic analysis is unusable there. Request source timed cues from the owner
frame, then use iOS ReplayKit app-audio-only capture and Apple's on-device
SoundAnalysis ML classifier with confidence gating.

Every capture is opt-in, video frames discarded, app audio temporary/local,
never uploads media, cancels on server/content changes. DRM remains protected.
"""
from pathlib import Path
p=Path("FrameNative/FrameXTVPlayerV6.swift")
s=p.read_text(encoding="utf-8")
def one(a,b,label):
    global s
    n=s.count(a)
    if n!=1:
        raise SystemExit(f"V14 {label}: expected one marker, got {n}")
    s=s.replace(a,b,1)

# The V13 source adapter is already inserted by the protected build script.
adapter_anchor="      function tick() { observeSource(); reportCaption(); }"
cue_publisher=r'''      function xsSmartPublishCues() {
        const video=findVideo();
        const cues=xsSmartCueWindows(video,trackFor(active),sourceCaptionHistory,48);
        send({event:'xs:subtitleTimedCues',
          mediaTime:video ? Number(video.currentTime||0) : 0,
          items:cues.slice(0,140).map(c=>({start:c.start,end:c.end}))});
      }
'''
one(adapter_anchor,cue_publisher+adapter_anchor,"timecoded original source cue publication")
one(
  "autoSync:xsSmartAutoSync, cancelAutoSync:xsSmartCancel,",
  "autoSync:xsSmartAutoSync, cancelAutoSync:xsSmartCancel, timedCues:xsSmartPublishCues,",
  "expose source cue windows to optional native AI"
)
one(
  "          else if (action === 'autoSubtitleSync') { sourceSubtitles.autoSync(); }",
  "          else if (action === 'autoSubtitleSync') { sourceSubtitles.autoSync(); }\n"
  "          else if (action === 'subtitleCueWindows') { sourceSubtitles.timedCues(); }",
  "query original source cues without changing player"
)

# Native model captures only the app audio after system permission, not the
# HTML media stream (unsupported in Safari). Strong reference to source frame.
one(
  '        send(["action": "autoSubtitleSync"])',
  '''        // iOS: request real timed cues from the selected source before
        // invoking ReplayKit/SoundAnalysis. No blind mic/cross-origin capture.
        send(["action": "subtitleCueWindows"])''',
  "invoke native ML instead of unsupported WebKit captureStream"
)
one(
  '            send(["action": "cancelAutoSubtitleSync"])',
  '''            XSNativeSubtitleAI.shared.cancel()''',
  "native capture cancellation"
)
one(
  '''        case "xs:subtitleAutoSync":
''',
  '''        case "xs:subtitleTimedCues":
            guard let frame = subtitleFrameID,
                  payload["frameID"] as? String == frame,
                  smartSyncRunning,
                  let rows = payload["items"] as? [[String: Any]] else { return }
            let cues: [XSNativeSubtitleCue] = rows.compactMap { row in
                guard let start = doubleValue(row["start"]),
                      let end = doubleValue(row["end"]),
                      start.isFinite, end.isFinite, end > start else { return nil }
                return XSNativeSubtitleCue(start: start, end: end)
            }
            guard cues.count >= 5 else {
                smartSyncRunning = false
                smartSyncStatus = "هذا السيرفر لا يتيح أوقات جمل الترجمة الكافية للمزامنة التلقائية."
                return
            }
            smartSyncStatus = "سيطلب iOS السماح بتحليل صوت التطبيق محلياً لمدة 26 ثانية."
            let selected = selectedSubtitleID
            let currentFrame = subtitleFrameID
            let mediaAtStart = currentTime
            let timing = subtitleTimingOffset
            Task { [weak self] in
                guard let self else { return }
                let result = await XSNativeSubtitleAI.shared.align(
                    cues: cues,
                    mediaTime: { [weak self] in self?.currentTime ?? mediaAtStart },
                    currentOffset: timing
                )
                // Source, episode or server may have changed during analysis.
                guard self.subtitleFrameID == currentFrame,
                      self.selectedSubtitleID == selected,
                      self.smartSyncRunning else { return }
                self.smartSyncRunning = false
                switch result {
                case let .applied(offset, confidence):
                    self.smartSyncSuggestedDelay = offset
                    self.smartSyncStatus = String(format:
                        "ضُبط توقيت الترجمة تلقائياً (ثقة %.0f%%).", confidence * 100)
                case let .unavailable(reason):
                    self.smartSyncStatus = reason
                }
            }

        case "xs:subtitleAutoSync":
''',
  "consume selected-frame timed source cues and run Apple's ML"
)

one(
    'Text("التلقائية تحتاج صوتاً متاحاً وترجمة موقّتة. إذا كانت ثقة التحليل منخفضة لن تُغيّر شيئاً.")',
    'Text("قد يطلب iOS السماح بالتقاط صوت التطبيق مؤقتاً. التحليل بالذكاء الاصطناعي يتم على الآيفون، ولا يُرسل الصوت لخادم أو يُحفظ بعد الانتهاء.")',
    "consent and privacy disclosure"
)
assert "V13 BUTTON_TIMING" in s and "V12_DOM_DELAY" in s
assert "sourceSubtitles.select(payload);" in s and "const finishDispatchedSelection" in s
p.write_text(s,encoding="utf-8")
print("V14 native ReplayKit/SoundAnalysis ML on explicit request; R5 source playback unchanged.")
