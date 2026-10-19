"""V15 post-R5/14 subtitle refinement: precisely two large +/- buttons,
one-point caption inset and reliable source-timed cue collection before AI.

Runs AFTER all original R5 -> V14 source transforms. The video playback
engine, source subtitle track selection, backup handoff and VLCKit are
explicitly unchanged.
"""
from pathlib import Path
path=Path("FrameNative/FrameXTVPlayerV6.swift")
p=path.read_text(encoding="utf-8")

def replace_exact(old,new,label):
    global p
    count=p.count(old)
    if count != 1:
        raise SystemExit(f"V15 {label}: expected 1 marker, got {count}")
    p=p.replace(old,new,1)

# New key avoids inheriting a high saved inset from earlier releases. After
# V15 users can still move captions upward, and down to ONE video pixel-point.
replace_exact(
    '@AppStorage("XSTV.subtitleBottomPadding.v13") private var subtitleBottom = 14.0',
    '''// V15_BOTTOM_ONE_POINT: align to the visible video bottom, not the screen.
    @AppStorage("XSTV.subtitleBottomPadding.v15") private var subtitleBottom = 1.0''',
    "one-point default and versioned persistence"
)
if p.count("subtitleBottom = 14") != 1:
    raise SystemExit("V15 appearance reset marker changed")
p=p.replace("subtitleBottom = 14","subtitleBottom = 1",1)
replace_exact("subtitleBottom = max(6, subtitleBottom - 8)",
              "subtitleBottom = max(1, subtitleBottom - 8)","lower subtitle position button")
replace_exact("Slider(value: $subtitleBottom, in: 6...220, step: 2)",
              "Slider(value: $subtitleBottom, in: 1...220, step: 1)",
              "full position adjustment reaches 1pt")
if "subtitleBottom = min(220, subtitleBottom + 8)" not in p:
    raise SystemExit("V15 upper caption position button missing")
# Legacy native aspect-fit and fully-native R5 geometry share this clamp.
p=p.replace("lowerBlackBar + max(6, CGFloat(subtitleBottom))",
            "lowerBlackBar + max(1, CGFloat(subtitleBottom))")
p=p.replace(": max(6, CGFloat(subtitleBottom))",
            ": max(1, CGFloat(subtitleBottom))")
replace_exact("bottom: 14","bottom: 1",
              "source-owned DOM caption initial position")
assert ("R5_ASPECTFIT_CAPTION" in p or "let visibleVideoBottomPadding" in p)
assert "min(CGFloat(subtitleBottom), 30)" not in p

a=p.find("    // V13 BUTTON_TIMING:")
b=p.find("    private func panelRow(",a)
if a<0 or b<0:
    raise SystemExit("V15 unable to locate V13 timing controls section")
panel=r'''    // V15_TWO_BUTTON_TIMING: simple and accessible ±0.25s per tap.
    // Tap the central offset to reset; no slider or tiny secondary controls.
    private func stepSubtitleTiming(_ seconds: Double) {
        player.cancelSmartSubtitleSync()
        let newValue = ((subtitleDelay + seconds) * 4).rounded() / 4
        subtitleDelay = min(12, max(-12, newValue))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var subtitleDelayPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("توقيت الترجمة")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                Button {
                    stepSubtitleTiming(-0.25)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 25, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تقديم الترجمة ربع ثانية")
                .accessibilityHint("كل ضغطة تقدم الترجمة 0.25 ثانية")

                Button {
                    player.cancelSmartSubtitleSync()
                    subtitleDelay = 0
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    VStack(spacing: 3) {
                        Text(String(format: "%+.2f", subtitleDelay))
                            .font(.system(size: 23, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                        Text("ثانية · تصفير")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(minWidth: 116, minHeight: 60)
                    .foregroundStyle(.white)
                    .background(.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("التوقيت الحالي، اضغط للتصفير")

                Button {
                    stepSubtitleTiming(0.25)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 25, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.13),
                                    in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("تأخير الترجمة ربع ثانية")
                .accessibilityHint("كل ضغطة تؤخر الترجمة 0.25 ثانية")
            }

            Text("− تقديم الترجمة  ·  + تأخير الترجمة  ·  اضغط على الرقم للتصفير")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if player.smartSyncRunning {
                    player.cancelSmartSubtitleSync()
                } else {
                    player.requestSmartSubtitleSync()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: player.smartSyncRunning ?
                          "stop.circle.fill" : "waveform.badge.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                    Text(player.smartSyncRunning ?
                         "إلغاء المزامنة الذكية" : "ضبط الترجمة تلقائياً بالصوت")
                        .font(.system(size: 13, weight: .bold))
                    Spacer(minLength: 0)
                    if player.smartSyncRunning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles").font(.system(size: 13))
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 50)
                .foregroundStyle(.white)
                .background(Color(red: 0.36, green: 0.25, blue: 0.48).opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Text(player.smartSyncStatus ?? subtitleTimingHelp)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(player.subtitleTimingMode == "unsupported" ?
                    Color.orange : Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            Text("الضبط الذكي يعتمد على الصوت وأوقات الجمل المتاحة من المصدر. عند عدم التأكد لا يغيّر التوقيت.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.56))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
    }

'''
p=p[:a]+panel+p[b:]

# V14 asked source for cues once. A DOM-only provider at the beginning of a
# movie may not have accumulated five cues yet. Sample on its existing source
# adapter tick (even at zero delay), retry briefly and use actual owner state.
old="      function xsSmartPublishCues() {\n        const video=findVideo();\n        const cues=xsSmartCueWindows(video,trackFor(active),sourceCaptionHistory,48);\n        send({event:'xs:subtitleTimedCues',\n          mediaTime:video ? Number(video.currentTime||0) : 0,\n          items:cues.slice(0,140).map(c=>({start:c.start,end:c.end}))});\n      }"
replacement=r'''      function xsSmartPublishCues() {
        const video=findVideo(), epoch=generation;
        const subtitle=active;
        if (!video || !subtitle) {
          send({event:'xs:subtitleTimedCues', items:[], mediaTime:0});
          return;
        }
        const began=Date.now();
        function tryRead() {
          if (disposed || generation!==epoch || active!==subtitle) return;
          // Cue collectors now observe the original DOM even when the
          // user has never adjusted the timing slider.
          if (!trackFor(active)) captureSourceCaption(video);
          const cues=xsSmartCueWindows(video,trackFor(active),sourceCaptionHistory,48);
          if (cues.length>=5 || Date.now()-began>14000) {
            send({event:'xs:subtitleTimedCues',
              mediaTime:Number(video.currentTime||0),
              items:cues.slice(0,140).map(c=>({start:c.start,end:c.end}))});
            return;
          }
          win.setTimeout(tryRead,1200);
        }
        tryRead();
      }'''
replace_exact(old,replacement,"wait for true source caption timestamps")

# Prevent a subtitle source with DOM-only cues from arriving at the 5-cue
# threshold with no observations: pick up DOM text while timing remains 0.
replace_exact(
   "      function reportCaption() {\n        const v = findVideo();\n        if (!active || !v || !delay) {",
   "      function reportCaption() {\n        const v = findVideo();\n        if (active && v && !delay) captureSourceCaption(v);\n        if (!active || !v || !delay) {",
   "source DOM caption observation at zero timing offset"
)

# Watchdog for missing/cross-origin source responses. A source may never
# respond to subtitleCueWindows; restore the button rather than spinning.
# Once native ReplayKit has started, the status changes and this watchdog
# intentionally leaves the active user-authorized capture alone.
replace_exact(
    '        send(["action": "subtitleCueWindows"])',
    '''        send(["action": "subtitleCueWindows"])
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self,
                  self.smartSyncRunning,
                  self.smartSyncStatus == "جارٍ تجهيز المزامنة الذكية…" else { return }
            self.smartSyncRunning = false
            self.smartSyncStatus = "المصدر لم يرسل بيانات الترجمة في الوقت المحدد؛ جرب سيرفراً آخر."
        }''',
    "avoid permanently spinning automatic sync if source does not reply"
)

assert "sourceSubtitles.select(payload);" in p
assert "const finishDispatchedSelection = () =>" in p
assert "subtitleDelay = 0\n        player.setSubtitleDelay(0)\n        activePlayback = next" in p
path.write_text(p,encoding="utf-8")
print("V15: simple +/− buttons, 1pt subtitle baseline, source-owned AI cue readiness without video/player changes.")
