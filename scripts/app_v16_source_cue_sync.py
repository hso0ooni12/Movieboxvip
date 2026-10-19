"""V16: zero-AI, source-owned timestamp synchronization.
Runs after proven V12 / R5 transforms. No ReplayKit, SoundAnalysis,
Whisper, voice capture, microphone permission or AI button is shipped.

Selected source TextTrack cues keep their original times. Video.currentTime
controls showing captions. One anchor fixes offset, two anchor rate drift.
DOM-only sources retain the existing honest positive-buffer delay fallback.
"""
from pathlib import Path
path=Path("FrameNative/FrameXTVPlayerV6.swift")
s=path.read_text(encoding="utf-8")

def once(old,new,label):
    global s
    n=s.count(old)
    if n!=1:
        raise SystemExit("V16 "+label+": expected exactly one marker, found "+str(n))
    s=s.replace(old,new,1)

# Lower native and website caption placement to 1pt above the ACTUAL video.
once(
    '@AppStorage("XSTV.subtitleBottomPadding") private var subtitleBottom = 76.0',
    '''// V16_VISIBLE_VIDEO_ONE_POINT: new key avoids carrying V12's old 76pt.
    @AppStorage("XSTV.subtitleBottomPadding.v16") private var subtitleBottom = 1.0''',
    "one-point default"
)
once("subtitleBottom = 76", "subtitleBottom = 1", "appearance reset")
once("subtitleBottom = max(32, subtitleBottom - 12)",
     "subtitleBottom = max(1, subtitleBottom - 8)","lower position")
once("subtitleBottom = min(220, subtitleBottom + 12)",
     "subtitleBottom = min(220, subtitleBottom + 8)","raise position")
once("Slider(value: $subtitleBottom, in: 32...220, step: 4)",
     "Slider(value: $subtitleBottom, in: 1...220, step: 1)",
     "position adjustable down to 1pt")
if "lowerBlackBar + min(CGFloat(subtitleBottom), 30)" in s:
    s=s.replace("lowerBlackBar + min(CGFloat(subtitleBottom), 30)",
                "lowerBlackBar + max(1, CGFloat(subtitleBottom))",1)
    s=s.replace(": CGFloat(subtitleBottom)",
                ": max(1, CGFloat(subtitleBottom))",1)
elif "R5_ASPECTFIT_CAPTION" in s:
    # captionOverlay already has .padding(.bottom, subtitleBottom).
    # The additional +max(padding-30) raised the subtitle unnecessarily.
    once("return -blackBarBottom + max(0, CGFloat(subtitleBottom) - 30)",
         "return -blackBarBottom","portrait video-bottom inset")
else:
    raise SystemExit("V16: R5 final caption geometry is not recognized")
once("bottom: 76","bottom: 1","source DOM default position")

# Display native timed captions if either constant offset or subtitle
# speed differs; rate-only correction with offset 0 must also be visible.
once(
    "const customTiming = delay !== 0 && active &&",
    "const customTiming = (delay !== 0 || subtitleRate !== 1) && active &&",
    "rate-only shift activates custom source cue layer"
)

# Wire the original source adapter's point-synchronization handler through
# the existing source iframe. No fetching new or alternate subtitle files.
once(
    "          else if (action === 'subtitleDelay') { subtitleDelay = Number(payload.seconds || 0); sourceSubtitles.setDelay(subtitleDelay); }",
    """          else if (action === 'subtitleDelay') { subtitleDelay = Number(payload.seconds || 0); sourceSubtitles.setDelay(subtitleDelay); }
          else if (action === 'subtitleSyncPoint') { sourceSubtitles.syncPoint(); }""",
    "exact owner iframe action"
)
once(
    '    @Published var subtitleTimingOffset = 0.0',
    '''    @Published var subtitleTimingOffset = 0.0
    @Published var subtitlePointStatus: String?
    @Published var subtitlePointResult: Double?
    @Published var subtitlePointRate = 1.0
    @Published var subtitlePointCount = 0''',
    "native source timing calibration state"
)
once(
    '    func setSubtitleDelay(_ seconds: Double) { send(["action": "subtitleDelay", "seconds": seconds]) }',
    '''    func setSubtitleDelay(_ seconds: Double) { send(["action": "subtitleDelay", "seconds": seconds]) }

    func markSubtitleSyncPoint() {
        guard selectedSubtitleID != nil, subtitleFrameID != nil else {
            subtitlePointStatus = "اختر ترجمة من قائمة المصدر أولاً."
            return
        }
        send(["action": "subtitleSyncPoint"])
    }''',
    "point-sync owner command"
)
once(
    '''        case "xs:subtitleTimingStatus":
''',
    '''        case "xs:subtitlePointResult":
            // Only the active selected source frame may calibrate subtitle time.
            guard let owner = subtitleFrameID,
                  payload["frameID"] as? String == owner else { return }
            subtitlePointStatus = payload["message"] as? String
            if payload["ok"] as? Bool == true,
               let seconds = doubleValue(payload["offset"]),
               let rate = doubleValue(payload["rate"]),
               seconds.isFinite, rate.isFinite,
               (0.94...1.06).contains(rate) {
                subtitlePointRate = rate
                subtitlePointCount = payload["points"] as? Int ?? 1
                // Assign UI display through the original delay publisher.
                // An echo with an identical value does not clear JS anchors.
                subtitlePointResult = seconds
            }

        case "xs:subtitleTimingStatus":
''',
    "guarded sync-point acknowledgement"
)
once(
    '''        subtitleTimingMode = "waiting"
        subtitleTimingOffset = 0''',
    '''        subtitleTimingMode = "waiting"
        subtitleTimingOffset = 0
        subtitlePointStatus = nil
        subtitlePointResult = nil
        subtitlePointRate = 1
        subtitlePointCount = 0''',
    "server change sync reset"
)
once(
    '''        .onChange(of: subtitleDelay) { value in player.setSubtitleDelay(value) }''',
    '''        .onChange(of: subtitleDelay) { value in player.setSubtitleDelay(value) }
        .onChange(of: player.selectedSubtitleID) { _ in
            // Another subtitle release might have a different time basis.
            subtitleDelay = 0
        }
        .onChange(of: player.subtitlePointResult) { aligned in
            if let aligned { subtitleDelay = aligned }
        }''',
    "point result updates UI without independent media time"
)

# Replace V12 slider with two accessible buttons. Point matching operates on
# REAL source cue timestamps and requires the user to tap on the right spoken
# line. No audio observation, record/AI or unexplained delay guesses.
a=s.find("    private var subtitleDelayPanel: some View {")
b=s.find("    private func panelRow(",a)
if a<0 or b<=a:
    raise SystemExit("V16: unable to find final subtitle delay panel")
panel=r'''    // V16_SOURCE_CUE_SYNC: no AI. Real TextTrack start/end times compared to
    // the actual video media clock; one/two manually confirmed sync anchors.
    private func adjustSubtitleClock(_ delta: Double) {
        let shifted=((subtitleDelay+delta)*4).rounded()/4
        subtitleDelay=min(60,max(-60,shifted))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var subtitleDelayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("توقيت الترجمة")
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button {
                    adjustSubtitleClock(-0.25)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 25, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تقديم الترجمة ربع ثانية")

                Button {
                    subtitleDelay=0
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 3) {
                        Text(String(format: "%+.2f", subtitleDelay))
                            .font(.system(size: 23, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                        Text("ثانية · تصفير")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .frame(minWidth: 112, minHeight: 58)
                    .background(.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("التوقيت الحالي، اضغط للتصفير")

                Button {
                    adjustSubtitleClock(0.25)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(.white.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تأخير الترجمة ربع ثانية")
            }

            Text("− تقديم  ·  + تأخير  ·  اضغط الرقم للتصفير")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.76))

            Button {
                player.markSubtitleSyncPoint()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                    Text("مطابقة الجملة مع الصوت")
                    Spacer()
                    Image(systemName: "scope")
                }
                .font(.system(size: 13, weight: .bold))
                .frame(height: 48)
                .padding(.horizontal, 15)
                .background(.white.opacity(0.11),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityHint("اضغط وقت سماع بداية نفس الجملة المعروضة؛ أعد المطابقة بعد دقيقة إذا زاد فرق التوقيت")

            Text("عند سماع بداية الجملة الظاهرة اضغط المطابقة. إذا زاد فرق التوقيت لاحقاً، طابق جملة ثانية بعد دقيقة أو أكثر.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.70))
                .fixedSize(horizontal: false, vertical: true)

            if let status = player.subtitlePointStatus {
                Text(status)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.93))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(subtitleTimingHelp)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(player.subtitleTimingMode == "unsupported" ?
                        Color.orange : Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if player.subtitlePointCount == 2 {
                Text(String(format: "مزامنة نقطتين · معامل السرعة %.5f", player.subtitlePointRate))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.70))
            }
        }
        .foregroundStyle(.white)
    }

'''
s=s[:a]+panel+s[b:]
# Dispose of added media time listeners when the source iframe closes.
# V25 installs its own caption observer; preserve that cleanup unchanged.
once(
    "function dispose() { disposed = true; pending = null; if (captionObserver) captionObserver.disconnect();",
    """function dispose() {
        if (timingVideo && timingHandler) {
          timingVideo.removeEventListener('timeupdate',timingHandler);
          timingVideo.removeEventListener('seeked',timingHandler);
        }
        timingVideo = null;
        disposed = true; pending = null;
        if (captionObserver) captionObserver.disconnect();""",
    "detach source media clock listener on player close"
)

# Maintain original R5/V12 playback engine protections.
assert "sourceSubtitles.select(payload);" in s
assert "const finishDispatchedSelection = () =>" in s
assert "V12_DOM_DELAY" in s
assert "R5_ASPECTFIT_CAPTION" in s or "let visibleVideoBottomPadding" in s
assert "ReplayKit" not in s and "SoundAnalysis" not in s
path.write_text(s,encoding="utf-8")
print("V16 applied: source-owned one/two cue point sync, 1pt video bottom, +/- only, no AI.")
