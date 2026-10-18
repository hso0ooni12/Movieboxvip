"""Normalize portrait subtitle placement after V39's generated player layers.

Some R5 compatibility scripts change the body of captionOverlay while keeping
its call signature. This step repairs the final generated view without changing
subtitle selection, source server switching or video playback controls.
"""
from pathlib import Path

p = Path("FrameNative/FrameXTVPlayerV6.swift")
source = p.read_text(encoding="utf-8")
old_call = "captionOverlay(width: proxy.size.width)"
new_call = "captionOverlay(width: proxy.size.width, height: proxy.size.height)"
begin = source.find("    private func captionOverlay(")
end = source.find("    private var loadingOverlay:", begin)
if begin < 0 or end < 0:
    raise SystemExit("R5 captions: final captionOverlay function boundary missing")
block = source[begin:end]
width_height_header = "private func captionOverlay(width: CGFloat, height: CGFloat)" in block
width_only_header = "private func captionOverlay(width: CGFloat)" in block
if not width_height_header and not width_only_header:
    raise SystemExit("R5 captions: unrecognized caption function: " + repr(block[:600]))

# Normalize call to the function actually emitted by the old generation steps.
if width_height_header:
    if new_call not in source:
        if old_call not in source:
            raise SystemExit("R5 captions: call missing for height-aware caption")
        source = source.replace(old_call, new_call, 1)
    selected_call = new_call
else:
    if new_call in source:
        source = source.replace(new_call, old_call, 1)
    elif old_call not in source:
        raise SystemExit("R5 captions: call missing for width-only caption")
    selected_call = old_call

# The fully-native geometry path is already correct.
native_complete = (
    width_height_header
    and "let visibleVideoBottomPadding" in block
    and "lowerBlackBar" in block
    and ".padding(.bottom, visibleVideoBottomPadding)" in block
)
if native_complete:
    print("R5 captions: native visible-video geometry intact.")
else:
    # Remove any stale reference to a variable that regeneration removed.
    if ".padding(.bottom, visibleVideoBottomPadding)" in block:
        block = block.replace(".padding(.bottom, visibleVideoBottomPadding)",
                              ".padding(.bottom, subtitleBottom)", 1)
        source = source[:begin] + block + source[end:]
    marker = "R5_ASPECTFIT_CAPTION"
    if marker not in source:
        replacement = (
            selected_call + "\n                        "
            ".offset(y: captionLetterboxAdjustment(width: proxy.size.width, height: proxy.size.height))"
        )
        source = source.replace(selected_call, replacement, 1)
        anchor = "    private var loadingOverlay: some View {"
        helper = """    // R5_ASPECTFIT_CAPTION: position visible captions within letterboxed
    // portrait video rather than at the bottom of the entire phone screen.
    private func captionLetterboxAdjustment(width: CGFloat, height: CGFloat) -> CGFloat {
        guard height > width * 1.12, aspectMode == "adapt" else { return 0 }
        let videoHeight = min(height, width * (9.0 / 16.0))
        let blackBarBottom = max(0, (height - videoHeight) / 2)
        return -blackBarBottom + max(0, CGFloat(subtitleBottom) - 30)
    }

"""
        source = source.replace(anchor, helper + anchor, 1)
    print("R5 captions: corrected portrait offset after generated-player changes.")

assert "captionOverlay(" in source
assert ("let visibleVideoBottomPadding" in source or "R5_ASPECTFIT_CAPTION" in source)
assert "sourceSubtitles.select(payload)" in source
p.write_text(source, encoding="utf-8")
