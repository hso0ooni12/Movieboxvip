"""V17 source subtitle correction for >60-second offsets.

Runs AFTER protected V16/R5. Leaves VLC, server/Backup handoff, movie
catalogs and source-owned subtitle click/ack untouched. Offers giant +/- 
buttons, each tap ±0.25s, native long-press quick jumps up to 5 minutes.
A few releases may genuinely be mismatched; do not pretend that offset
alone corrects missing scenes or different movie cuts.
"""
from pathlib import Path
p=Path("FrameNative/FrameXTVPlayerV6.swift")
s=p.read_text(encoding="utf-8")
def once(old,new,label):
    global s
    n=s.count(old)
    if n!=1: raise SystemExit(f"V17 {label}: expected one marker, got {n}")
    s=s.replace(old,new,1)

# V16 hard-capped ±60 seconds. Some subtitle releases differ by minutes.
once("subtitleDelay=min(60,max(-60,shifted))",
     "subtitleDelay=min(600,max(-600,shifted))",
     "correct arbitrary long subtitle offset limitation")
# Keep simple two large visible controls. A long press opens native
# context menu for real-world cases >60s (instead of 240+ repetitive taps).
minus='''                .accessibilityLabel("تقديم الترجمة ربع ثانية")'''
plus='''                .accessibilityLabel("تأخير الترجمة ربع ثانية")'''
once(minus,minus+'''
                .contextMenu {
                    Button("تقديم 10 ثوانٍ") { adjustSubtitleClock(-10) }
                    Button("تقديم 30 ثانية") { adjustSubtitleClock(-30) }
                    Button("تقديم دقيقة") { adjustSubtitleClock(-60) }
                    Button("تقديم 5 دقائق") { adjustSubtitleClock(-300) }
                }''', "minus long press precise large jumps")
once(plus,plus+'''
                .contextMenu {
                    Button("تأخير 10 ثوانٍ") { adjustSubtitleClock(10) }
                    Button("تأخير 30 ثانية") { adjustSubtitleClock(30) }
                    Button("تأخير دقيقة") { adjustSubtitleClock(60) }
                    Button("تأخير 5 دقائق") { adjustSubtitleClock(300) }
                }''', "plus long press precise large jumps")
# Distinguish manual offset controls from source mismatches.
one_note='''            Text("− تقديم  ·  + تأخير  ·  اضغط الرقم للتصفير")'''
replace_note='''            Text("ضغطة: ربع ثانية · ضغط مطول على + أو −: 10 أو 30 أو 60 أو 300 ثانية. اضغط الرقم للتصفير.")'''
once(one_note,replace_note,"native quick-jump guidance")
# On missing media metadata show no error; only warn about a demonstrable
# subtitle timeline extending 60s AFTER the video ends.
once("    @Published var subtitlePointCount = 0",
     """    @Published var subtitlePointCount = 0
    @Published var subtitleReleaseWarning: String?""",
     "source release warning state")
once('''        case "xs:subtitlePointResult":''',
     '''        case "xs:subtitleReleaseFit":
            guard let frame = subtitleFrameID,
                  payload["frameID"] as? String == frame else { return }
            if payload["status"] as? String == "late-ending" {
                subtitleReleaseWarning = "قد تكون الترجمة لإصدار فيديو مختلف؛ وقت آخر جملة يتجاوز مدة الفيلم. جرّب ترجمة أخرى من المصدر."
            } else {
                subtitleReleaseWarning = nil
            }

        case "xs:subtitlePointResult":''',
     "source release warning receiver")
once("        subtitlePointCount = 0\n        send([\"action\": \"subtitleSyncReset\"])",
     "        subtitlePointCount = 0\n        subtitleReleaseWarning = nil\n        send([\"action\": \"subtitleSyncReset\"])",
     "clear manual release warning")
# Different server: previous track metadata must never persist.
once("        subtitlePointCount = 0\n\n        case",
     "        subtitlePointCount = 0\n        subtitleReleaseWarning = nil\n\n        case",
     "server reset warning") if "        subtitlePointCount = 0\n\n        case" in s else None

marker='''            if player.subtitlePointCount == 2 {'''
once(marker,'''            if let warning = player.subtitleReleaseWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

'''+marker,"non-blocking source mismatch warning")
assert "sourceSubtitles.select(payload);" in s
assert "const finishDispatchedSelection = () =>" in s
assert "R5_ASPECTFIT_CAPTION" in s or "let visibleVideoBottomPadding" in s
p.write_text(s,encoding="utf-8")
print("V17 installed: ±600-second true cue offset, optional native long-press jumps, read-only source release mismatch warning.")
