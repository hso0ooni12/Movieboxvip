"""V13 subtitle experience postprocessor on TOP of proven R5/V12 build.

- True button-driven fine/coarse timing (no gesture-dependent slider).
- Lower default captions at the bottom edge of the *visible video*.
- Confidence-gated, local acoustic auto-alignment ONLY if media capture
  is natively authorized/supported; never reroute/mute the video element.
- Preserve source-owned tracks, server/Backup, subtitle selection and VLC.
"""
from pathlib import Path
from textwrap import indent

path=Path("FrameNative/FrameXTVPlayerV6.swift")
p=path.read_text(encoding="utf-8")
def once(old,new,label):
    global p
    n=p.count(old)
    if n!=1:
        raise SystemExit(f"V13 {label}: expected one marker, got {n}")
    p=p.replace(old,new,1)

# Reset legacy saved high position ONCE through a new setting key.
# Keep values persistent after user adjusts it in the new version.
once(
    '@AppStorage("XSTV.subtitleBottomPadding") private var subtitleBottom = 76.0',
    '''// V13_VIDEO_BOTTOM: new default is 14pt above actual visible video.
    @AppStorage("XSTV.subtitleBottomPadding.v13") private var subtitleBottom = 14.0''',
    "default subtitle bottom"
)
for original,replacement in [
    ("subtitleBottom = 76","subtitleBottom = 14"),
    ("subtitleBottom = max(32, subtitleBottom - 12)","subtitleBottom = max(6, subtitleBottom - 8)"),
    ("subtitleBottom = min(220, subtitleBottom + 12)","subtitleBottom = min(220, subtitleBottom + 8)"),
    ("Slider(value: $subtitleBottom, in: 32...220, step: 4)",
     "Slider(value: $subtitleBottom, in: 6...220, step: 2)")
]:
    # Appearance reset and position controls differ slightly among R5 versions.
    p=p.replace(original,replacement)
# R5 has two proven geometry implementations. Support both *without*
# rewriting captionOverlay or changing the actual video transform.
if "lowerBlackBar + min(CGFloat(subtitleBottom), 30)" in p:
    p=p.replace("lowerBlackBar + min(CGFloat(subtitleBottom), 30)",
                "lowerBlackBar + max(6, CGFloat(subtitleBottom))",1)
    p=p.replace(": CGFloat(subtitleBottom)",": max(6, CGFloat(subtitleBottom))",1)
elif "R5_ASPECTFIT_CAPTION" in p:
    # Existing .padding(.bottom, subtitleBottom) already supplies the
    # selected inset, so offset only for the bottom letterbox bar.
    original="return -blackBarBottom + max(0, CGFloat(subtitleBottom) - 30)"
    if original not in p:
        raise SystemExit("V13 R5 portrait geometry formula changed")
    p=p.replace(original,"return -blackBarBottom",1)
else:
    raise SystemExit("V13: neither known R5 caption geometry available")

# The source site has its own HTML cue overlay; align it to the low baseline
# too. Native UI style command continues to override it on video launch.
if "bottom: 76" not in p:
    raise SystemExit("V13 source HTML original bottom value absent")
p=p.replace("bottom: 76","bottom: 14")

# Add audio auto-align helper inside the EXISTING source-owned adapter,
# instead of introducing another player or a third-party subtitle provider.
source=Path("scripts/xs_smart_subtitle_sync.js").read_text(encoding="utf-8")
anchor="      function tick() { observeSource(); reportCaption(); }"
if p.count(anchor)!=1:
    raise SystemExit("V13 source adapter tick insertion anchor changed")
p=p.replace(anchor,indent(source.rstrip(), "      ")+"\n"+anchor,1)
once(
    "      return {frameID, scan, publish, select, reset, tick, hidePanels, dispose,",
    "      return {frameID, scan, publish, select, reset, tick, hidePanels, dispose, autoSync:xsSmartAutoSync, cancelAutoSync:xsSmartCancel,",
    "expose smart sync to original source bridge"
)
# Disconnect only analysis graph, not playback streams, on episode/server swap.
once(
    "      function reset() {",
    "      function reset() { xsSmartCancel();",
    "cancel ongoing analysis on source change"
)
once(
    "      function dispose() { disposed = true;",
    "      function dispose() { xsSmartCancel(); disposed = true;",
    "stop analysis on player dismissal"
)
# Source adapter command is already mirrored to the actual child iframe.
route="          else if (action === 'subtitleDelay') { subtitleDelay = Number(payload.seconds || 0); sourceSubtitles.setDelay(subtitleDelay); }"
once(route,route+'''
          else if (action === 'autoSubtitleSync') { sourceSubtitles.autoSync(); }
          else if (action === 'cancelAutoSubtitleSync') { sourceSubtitles.cancelAutoSync(); }''',
     "smart sync command routing"
)

# Native controls:
once(
    '    @Published var subtitleTimingOffset = 0.0',
    '''    @Published var subtitleTimingOffset = 0.0
    @Published var smartSyncRunning = false
    @Published var smartSyncStatus: String?
    @Published var smartSyncSuggestedDelay: Double?''',
    "smart status model"
)
once(
    '    func setSubtitleDelay(_ seconds: Double) { send(["action": "subtitleDelay", "seconds": seconds]) }',
    '''    func setSubtitleDelay(_ seconds: Double) { send(["action": "subtitleDelay", "seconds": seconds]) }

    func requestSmartSubtitleSync() {
        guard subtitleFrameID != nil, selectedSubtitleID != nil else {
            smartSyncStatus = "اختر ترجمة أولاً وانتظر تحميلها قبل المزامنة."
            return
        }
        guard !smartSyncRunning else { return }
        smartSyncStatus = "جارٍ تجهيز المزامنة الذكية…"
        smartSyncRunning = true
        smartSyncSuggestedDelay = nil
        send(["action": "autoSubtitleSync"])
    }

    func cancelSmartSubtitleSync() {
        if smartSyncRunning {
            send(["action": "cancelAutoSubtitleSync"])
            smartSyncRunning = false
            smartSyncStatus = "أُلغيت المزامنة التلقائية."
        }
    }''',
    "native opt-in control"
)
once(
    '''        case "xs:subtitleTimingStatus":
''',
    '''        case "xs:subtitleAutoSync":
            guard let owner = subtitleFrameID,
                  payload["frameID"] as? String == owner else { return }
            let phase = payload["phase"] as? String ?? "unavailable"
            smartSyncRunning = phase == "running"
            smartSyncStatus = payload["message"] as? String
            if phase == "applied", let suggested = doubleValue(payload["offset"]) {
                smartSyncSuggestedDelay = suggested
            }

        case "xs:subtitleTimingStatus":
''',
    "source-owned smart status"
)
once(
    '''        subtitleTimingMode = "waiting"
        subtitleTimingOffset = 0''',
    '''        subtitleTimingMode = "waiting"
        subtitleTimingOffset = 0
        smartSyncRunning = false
        smartSyncStatus = nil
        smartSyncSuggestedDelay = nil''',
    "server state reset"
)
# Reset on a different movie or episode (V11 resets manual offsets already).
once(
    '''    func reset() {
        currentTime = 0''',
    '''    func reset() {
        smartSyncRunning = false
        smartSyncStatus = nil
        smartSyncSuggestedDelay = nil
        currentTime = 0''',
    "player state reset"
)
once(
    '''        .onChange(of: subtitleDelay) { value in player.setSubtitleDelay(value) }''',
    '''        .onChange(of: subtitleDelay) { value in player.setSubtitleDelay(value) }
        .onChange(of: player.smartSyncSuggestedDelay) { suggested in
            if let suggested { subtitleDelay = suggested }
        }''',
    "apply confidence-checked offset to existing player timing"
)

start=p.find("    private var subtitleDelayPanel: some View {")
end=p.find("    private func panelRow(",start)
if start<0 or end<start:
    raise SystemExit("V13 final V27 subtitle delay panel boundaries missing")
panel=r'''    // V13 BUTTON_TIMING: every tap changes an exact offset, accessible on
    // landscape and portrait iPhones. No slider and no invisible thumb.
    private func shiftSubtitles(by delta: Double) {
        player.cancelSmartSubtitleSync()
        let adjusted = (subtitleDelay + delta) * 100
        subtitleDelay = min(12, max(-12, adjusted.rounded() / 100))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func subtitleOffsetButton(_ title: String, seconds: Double) -> some View {
        Button {
            shiftSubtitles(by: seconds)
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(minHeight: 46)
                .background(Color.white.opacity(0.09),
                            in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ?
            "تقديم الترجمة \(abs(seconds)) ثانية" :
            "تأخير الترجمة \(seconds) ثانية")
    }

    private var subtitleDelayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("مزامنة الترجمة")
                    .font(.system(size: 16, weight: .bold))
                Spacer(minLength: 8)
                Text(String(format: "%+.2f s", subtitleDelay))
                    .font(.system(size: 23, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 6) {
                subtitleOffsetButton("−1.00", seconds: -1)
                subtitleOffsetButton("−0.25", seconds: -0.25)
                Button {
                    player.cancelSmartSubtitleSync()
                    subtitleDelay = 0
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Label("0", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تصفير توقيت الترجمة")
                subtitleOffsetButton("+0.25", seconds: 0.25)
                subtitleOffsetButton("+1.00", seconds: 1)
            }
            Text("− تقديم الترجمة · + تأخير الترجمة · كل فيلم وحلقة يبدأ من صفر.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.67))
                .lineLimit(2)

            Button {
                if player.smartSyncRunning {
                    player.cancelSmartSubtitleSync()
                } else {
                    player.requestSmartSubtitleSync()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: player.smartSyncRunning ? "stop.circle.fill" : "waveform.badge.magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                    Text(player.smartSyncRunning ? "إيقاف المزامنة" : "مزامنة ذكية تلقائية بالصوت")
                        .font(.system(size: 13, weight: .bold))
                    Spacer(minLength: 0)
                    if player.smartSyncRunning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 13))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .foregroundStyle(.white)
                .background(Color(red: 0.36, green: 0.25, blue: 0.48).opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)

            Text(player.smartSyncStatus ?? subtitleTimingHelp)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(player.subtitleTimingMode == "unsupported" ?
                    Color.orange : Color.white.opacity(0.77))
                .fixedSize(horizontal: false, vertical: true)

            Text("التلقائية تحتاج صوتاً متاحاً وترجمة موقّتة. إذا كانت ثقة التحليل منخفضة لن تُغيّر شيئاً.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
    }

'''
p=p[:start]+panel+p[end:]

# Keep original source server / VLC / track selection untouched.
assert "sourceSubtitles.select(payload);" in p
assert "const finishDispatchedSelection = () =>" in p
assert "V12_DOM_DELAY" in p
assert "captionOverlay(" in p and ("R5_ASPECTFIT_CAPTION" in p or "let visibleVideoBottomPadding" in p)
path.write_text(p,encoding="utf-8")
print("V13 subtitle timing: precise buttons, low video-bottom captions, opt-in safe audio alignment, preserved R5.")
