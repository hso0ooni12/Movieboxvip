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

# Warm only read-only discovery. The R5 V24 adapter init is a stable
# insertion point; later player revisions intentionally removed old timers.
# This never opens a menu or clicks a server, and only reads source rows.
anchor = "      const sourceSubtitles = createXSSourceSubtitles({document, window, findVideo, emit: bridge});"
if anchor not in s:
    raise SystemExit("V5 fast discovery: source-owned subtitle adapter initialization missing")
warm = """      // V5_FAST_READONLY_DISCOVERY: four early read-only menu observations.
      [95, 270, 580, 1050].forEach(delay => setTimeout(() => {
        try { scanServers(); scanQualities(); } catch (_) {}
      }, delay));
"""
s = s.replace(anchor, anchor + "\n" + warm, 1)

assert "sourceSubtitles.select(payload);" in s
assert 'var payload: [String: Any] = ["action": "server", "name": server.name]' in s
assert "V5_FAST_READONLY_DISCOVERY" in s
path.write_text(s, encoding="utf-8")
print("V5 fast discovery PASS: no duplicate source menu opening; four early read-only probes.")
