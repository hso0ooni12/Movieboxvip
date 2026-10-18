"""V5 accelerated SOURCE-owned server and subtitle discovery.

Run after the complete V39 R5 playback pipeline. Never modify provider order,
selectServer, sourceSubtitles.select(), choice indexes, or acknowledgement.
The delay previously came from redundant opens of source menus triggered by
both openPanel() and the respective SwiftUI panel onAppear.
"""
from pathlib import Path
import re

path = Path("FrameNative/FrameXTVPlayerV6.swift")
s = path.read_text(encoding="utf-8")

for anchor in [
    "func selectServer(_ server: XSServerOption)",
    'var payload: [String: Any] = ["action": "server", "name": server.name]',
    "sourceSubtitles.select(payload);",
    "func requestQualityMenu()",
    "func requestSubtitleMenu()",
    "private var qualityPanel: some View",
    "private var subtitlesPanel: some View",
]:
    if anchor not in s:
        raise SystemExit("V5 fast discovery: R5 protected marker missing: " + anchor)

def section_replace(start, stop, old, label):
    global s
    a = s.index(start)
    b = s.index(stop, a + len(start))
    block = s[a:b]
    if old not in block:
        raise SystemExit("V5 fast discovery: unexpected generated " + label)
    block = block.replace(old, "", 1)
    s = s[:a] + block + s[b:]

# The opening action is sent by openPanel exactly once. Do not click the site's
# React server/subtitle menu again during SwiftUI view presentation.
section_replace(
    "    private var qualityPanel: some View {",
    "    private func nativeServerRow(",
    """        .onAppear {
            player.requestQualityMenu()
            player.requestMetadata()
        }
""",
    "duplicate quality menu presentation command"
)
section_replace(
    "    private var subtitlesPanel: some View {",
    "    private var audioPanel: some View {",
    """        .onAppear {
            player.requestSubtitleMenu()
            player.requestMetadata()
        }
""",
    "duplicate subtitle menu presentation command"
)

# Warm only read-only discovery. Existing source-specific selection/acknowledgement
# is unchanged. This is bounded to four early probes and does NOT tap any server.
start = re.search(r"setInterval\(\(\)\s*=>\s*\{\s*scanServers\(\);\s*scanQualities\(\)\s*\}\s*,\s*1400\s*\);", s)
if start is None:
    # Some generated releases use a single expression instead of a block.
    start = re.search(r"setInterval\(\(\)\s*=>\s*\{?\s*scanServers\(\);\s*scanQualities\(\)\s*\}?\s*,\s*1400\s*\);", s)
if start is None:
    raise SystemExit("V5 fast discovery: original read-only server scan interval missing")

warm = """// V5_FAST_READONLY_DISCOVERY: show existing source server rows quickly,
      // without touching selected provider, source popup, or subtitle owner.
      [95, 270, 580, 1050].forEach(delay => setTimeout(() => {
        try { scanServers(); scanQualities(); } catch (_) {}
      }, delay));
      """
s = s[:start.start()] + warm + s[start.start():]
assert "sourceSubtitles.select(payload);" in s
assert 'var payload: [String: Any] = ["action": "server", "name": server.name]' in s
assert "V5_FAST_READONLY_DISCOVERY" in s
path.write_text(s, encoding="utf-8")
print("V5 fast discovery PASS: no duplicate source menu opening; four early read-only probes.")
