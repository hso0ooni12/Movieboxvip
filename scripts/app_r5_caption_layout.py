"""Repair subtitle placement after the legacy player-generation patches.

Several compatibility scripts regenerate FrameXTVPlayerV6.swift during CI.
The source tree may contain the new geometry but those scripts can overwrite
it. This final, idempotent, display-only step preserves server/subtitle bridges.
"""
from pathlib import Path

path = Path("FrameNative/FrameXTVPlayerV6.swift")
s = path.read_text(encoding="utf-8")

if "visibleVideoBottomPadding" in s and "captionOverlay(width: proxy.size.width, height: proxy.size.height)" in s:
    print("R5 subtitle geometry already present; preserving it.")
else:
    old_call = "captionOverlay(width: proxy.size.width)"
    old_header = """    private func captionOverlay(width: CGFloat) -> some View {
        VStack {
            Spacer()"""
    new_header = """    private func captionOverlay(width: CGFloat, height: CGFloat) -> some View {
        // Anchor caption inside aspect-fit video instead of the device's lower black bar.
        let isLetterboxedPortrait = height > width * 1.12 && aspectMode == "adapt"
        let visibleVideoHeight = min(height, width * (9.0 / 16.0))
        let lowerBlackBar = max(0, (height - visibleVideoHeight) / 2)
        let visibleVideoBottomPadding = isLetterboxedPortrait
            ? lowerBlackBar + min(CGFloat(subtitleBottom), 30)
            : CGFloat(subtitleBottom)

        return VStack {
            Spacer()"""
    if old_call not in s or old_header not in s:
        raise SystemExit("R5 caption repair cannot find generated caption anchors")
    s = s.replace(old_call, "captionOverlay(width: proxy.size.width, height: proxy.size.height)", 1)
    s = s.replace(old_header, new_header, 1)
    start = s.index("    private func captionOverlay(width:")
    end = s.index("    private var loadingOverlay:", start)
    block = s[start:end]
    if ".padding(.bottom, subtitleBottom)" not in block:
        raise SystemExit("R5 caption repair cannot find original bottom inset")
    s = s[:start] + block.replace(".padding(.bottom, subtitleBottom)", ".padding(.bottom, visibleVideoBottomPadding)", 1) + s[end:]
    path.write_text(s, encoding="utf-8")
    print("R5 caption geometry restored after generated-player pipeline.")

assert "captionOverlay(width: proxy.size.width, height: proxy.size.height)" in s
assert "visibleVideoBottomPadding" in s
assert "lowerBlackBar" in s
