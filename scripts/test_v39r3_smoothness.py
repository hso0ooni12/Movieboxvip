from pathlib import Path
import re
import subprocess
import tempfile

player_path = Path("FrameNative/FrameXTVPlayerV6.swift")
player = player_path.read_text(encoding="utf-8")

assert "V39R4_FINAL_POLISH" in player
assert "V39R3_PLAYER_SMOOTHNESS" in player
assert "V39R_SURGICAL_PLAYER_FIX" in player

bridge_start = player.index('private static let bridgeScript = #"""') + len('private static let bridgeScript = #"""')
bridge_end = player.index('"""#', bridge_start)
bridge = player[bridge_start:bridge_end]
bridge = "\n".join(line[4:] if line.startswith("    ") else line for line in bridge.splitlines())

# Catch the exact V39R2 regression: command call sites without bridge helpers.
for function_name in (
    "openServerMenu",
    "selectByText",
    "openAndScanServers",
    "openAndScanSubtitles",
    "xsV39Failover",
    "xsV39BeginServerWatch",
):
    assert f"function {function_name}(" in bridge, function_name

assert "xsV39ServerChoices.splice" in bridge
assert "xsV39HandleServerSignal" in bridge
assert "event:'xs:serverSwitching'" in bridge
assert "event:'xs:serverFailover'" in bridge
assert "event:'xs:serverReady'" in bridge
assert "event:'xs:serverFailed'" in bridge
assert "name.toLowerCase() === 'auto'" in bridge

# A subtitle panel open is one source scan, not a metadata + server scan.
subtitle_start = player.index("    private var subtitlesPanel: some View {")
subtitle_end = player.index("\n    private var audioPanel", subtitle_start)
subtitle_panel = player[subtitle_start:subtitle_end]
assert "player.requestSubtitleMenu()" in subtitle_panel
assert "player.requestMetadata()" not in subtitle_panel

quality_start = player.index("    private var qualityPanel: some View {")
quality_end = player.index("\n    private var subtitlesPanel", quality_start)
quality_panel = player[quality_start:quality_end]
assert "player.requestServerMenu()" in quality_panel
assert "player.requestMetadata()" not in quality_panel
assert "player.requestSubtitleMenu()" not in quality_panel

open_start = player.index("    private func openPanel(_ newPanel: XSPlayerPanel) {")
open_end = player.index("\n    private func closePanel", open_start)
open_panel = player[open_start:open_end]
assert "requestMetadata" not in open_panel
assert "requestSubtitleMenu" not in open_panel
assert "requestQualityMenu" not in open_panel
assert "requestAudioMenu" not in open_panel

assert "backgroundStyle:String(payload.backgroundStyle" in bridge
assert "backgroundOpacity:Math.max(0,Math.min(1" in bridge
assert "backgroundStyle: subtitleBackground ? subtitleBackgroundStyle : \"none\"" in player
assert "private var effectiveSubtitleBackgroundStyle" in player
assert '@Published var serverSwitching = false' in player
assert 'case "xs:serverFailover":' in player

# Validate the extracted bridge as JavaScript, not just as text.
with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8") as handle:
    handle.write(bridge)
    handle.flush()
    result = subprocess.run(["node", "--check", handle.name], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr

print("V39R3 QA PASS: server helpers/failover are defined, panels are de-duplicated, subtitle style is complete, bridge syntax is valid")

