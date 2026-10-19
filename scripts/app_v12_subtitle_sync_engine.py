"""V12 final caption synchronization bridge.

Applied AFTER all proven R5/V11 scripts so the native source adapter,
V27 styling, and playback surface keep their existing mechanics.
Do not edit VLCKit, stream URL switching, source subtitles selection payloads
or primary player routing.
"""
from pathlib import Path

path=Path("FrameNative/FrameXTVPlayerV6.swift")
p=path.read_text(encoding="utf-8")
def replace_one(old,new,label):
    global p
    count=p.count(old)
    if count != 1:
        raise SystemExit(f"V12 {label}: expected 1 source marker, found {count}")
    p=p.replace(old,new,1)

# V27 rebuilds applyStyle after V24 injects the source-owned adapter.
# Restore the V12 timing fallback to its final generated CSS implementation.
replace_one(
    "        const customTiming = delay !== 0 && active && trackFor(active);",
    """        // V12_DOM_DELAY: source may display only React <div> captions.
        // Buffer positive offsets; do not silently fake negative lead times
        // without a genuine cue file containing future timestamps.
        const customTiming = delay !== 0 && active &&
          (trackFor(active) || (delay > 0 && sourceCaptionNodes().length > 0));""",
    "final source DOM timing visibility"
)

# Send timing capability back to native UI. This prevents another release in
# which the delay slider seems functional while the caption text never moves.
replace_one(
    "    @Published var subtitleSelectionError: String?",
    """    @Published var subtitleSelectionError: String?
    @Published var subtitleTimingMode = "idle"
    @Published var subtitleTimingOffset = 0.0""",
    "native timing feedback state"
)
replace_one(
    '''        case "xs:caption":
            guard payload["frameID"] as? String == subtitleFrameID else { return }''',
    '''        case "xs:subtitleTimingStatus":
            // An advertising iframe or previous server may not overwrite the
            // selected source's actual timing capability.
            guard let owner = subtitleFrameID,
                  payload["frameID"] as? String == owner else { return }
            subtitleTimingMode = payload["mode"] as? String ?? "unsupported"
            if let offset = doubleValue(payload["offset"]) {
                subtitleTimingOffset = offset
            }

        case "xs:caption":
            guard payload["frameID"] as? String == subtitleFrameID else { return }''',
    "native source-owned status receive"
)
replace_one(
    '''        subtitleOptions = []
        subtitleScanFinished = false
        selectedSubtitleID = nil
        captionText = ""''',
    '''        subtitleOptions = []
        subtitleScanFinished = false
        selectedSubtitleID = nil
        captionText = ""
        subtitleTimingMode = "waiting"
        subtitleTimingOffset = 0''',
    "server change status reset"
)

# The V11 generated picker keeps multiple subtitle variants. Deduplicate only
# identical source IDs, never two different English/Arabic/SDH source rows.
replace_one(
    '''            let key = "\\(item.displayName.lowercased())|\\(item.language.lowercased())"''',
    '''            let key = item.id''',
    "keep same-language source subtitle variants"
)

# Explain +delay vs −advance and whether the selected source actually supports
# the requested adjustment.
anchor="    private var subtitleDelayPanel: some View {"
if p.count(anchor)!=1:
    raise SystemExit("V12 timing panel declaration changed")
helper='''    private var subtitleTimingHelp: String {
        guard subtitleDelay != 0 else {
            return "كل فيلم أو حلقة يبدأ بتوقيت 0.00 ثانية."
        }
        switch player.subtitleTimingMode {
        case "cues":
            return "تم تطبيق التوقيت مباشرة على جمل الترجمة الفعلية."
        case "buffered":
            return "تم تطبيق التأخير على ترجمة المصدر بعد تسجيل توقيت ظهورها."
        case "waiting":
            return "اختر الترجمة وانتظر ظهور أول سطر حتى نتحقق من المزامنة."
        case "unsupported":
            return "هذا السيرفر لا يتيح توقيت الجمل القادمة؛ لا يمكن تقديم الترجمة هنا. جرّب سيرفراً بترجمة نصية."
        default:
            return "جارٍ التحقق من قدرة السيرفر على تعديل توقيت الترجمة…"
        }
    }

'''
p=p.replace(anchor,helper+anchor,1)
replace_one(
    'Text("If captions appear late, increase timing. Each movie and episode starts at 0.")',
    'Text("تأخير الترجمة (+) · تقديم الترجمة (−). يعود التوقيت للصفر مع كل فيلم أو حلقة.")',
    "timing control sign instructions"
)
replace_one(
    '''            Slider(value: $subtitleDelay, in: -7.5...9.0, step: 0.25)
                .tint(.white)''',
    '''            Slider(value: $subtitleDelay, in: -7.5...9.0, step: 0.25)
                .tint(.white)
            Text(subtitleTimingHelp)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(player.subtitleTimingMode == "unsupported" ? Color.orange : Color.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)''',
    "timing status shown within editor"
)

# Source playback/Backup engine and V24 cue selection unchanged.
assert "sourceSubtitles.select(payload);" in p
assert "const finishDispatchedSelection = () =>" in p
assert "V39_R5_STABILITY_RESTORE" in Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
path.write_text(p,encoding="utf-8")
print("V12: native UI reflects applied timing or unsupported mode; DOM delay and all source-language variants preserved.")
