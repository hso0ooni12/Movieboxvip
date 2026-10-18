"""R5 portrait caption geometry after generated player pipeline.

The V24→V39 build scripts rewrite the player view; this runs last. Avoid touching
subtitle tracks, source selection, server bridge, or playback lifecycle.
"""
from pathlib import Path

path = Path("FrameNative/FrameXTVPlayerV6.swift")
s = path.read_text(encoding="utf-8")

native_geometry = ("visibleVideoBottomPadding" in s and
                   "captionOverlay(width: proxy.size.width, height: proxy.size.height)" in s)
final_offset = ("R5_ASPECTFIT_CAPTION" in s and "captionLetterboxAdjustment" in s)

if native_geometry or final_offset:
    print("R5 caption video-bounds geometry already present.")
else:
    # Older code-generation scripts restore the one-argument caption overlay.
    old = "captionOverlay(width: proxy.size.width)"
    if old not in s:
        index = s.find("captionOverlay(")
        raise SystemExit("R5 caption patch: no supported call. Nearby: " +
                         repr(s[max(0, index - 50):index + 230]))
    s = s.replace(
        old,
        old + "\n                        .offset(y: captionLetterboxAdjustment(width: proxy.size.width, height: proxy.size.height))",
        1,
    )
    anchor = "    private var loadingOverlay: some View {"
    if anchor not in s:
        raise SystemExit("R5 caption patch: loading overlay insertion marker missing")
    helper = """    // R5_ASPECTFIT_CAPTION: keep portrait captions near the visible video,
    // rather than at the physical bottom of the letterboxed black canvas.
    private func captionLetterboxAdjustment(width: CGFloat, height: CGFloat) -> CGFloat {
        guard height > width * 1.12, aspectMode == "adapt" else { return 0 }
        let videoHeight = min(height, width * (9.0 / 16.0))
        let blackBarBottom = max(0, (height - videoHeight) / 2)
        return -blackBarBottom + max(0, CGFloat(subtitleBottom) - 30)
    }

"""
    s = s.replace(anchor, helper + anchor, 1)
    path.write_text(s, encoding="utf-8")
    print("R5 portrait subtitle overlay moved onto visible aspect-fit video.")

assert (("visibleVideoBottomPadding" in s) or ("R5_ASPECTFIT_CAPTION" in s))
assert "sourceSubtitles.select(payload)" in s
