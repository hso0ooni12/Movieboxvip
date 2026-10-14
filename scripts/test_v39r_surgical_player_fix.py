from pathlib import Path
import runpy

# Apply only the robust V39 recovery patch after the proven V39 generator/test.
runpy.run_path("scripts/app_v39r2_surgical_player_fix.py", run_name="__main__")

player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")

assert "V39R_SURGICAL_PLAYER_FIX" in player
assert "V39_STABLE_VLC_SURFACE" in sports

# No post-V39 player architecture is allowed into this recovery build.
assert "V40_PLAYER_SERVER_AUDIT" not in player
assert "V42_FRAME_SOURCE_SERVER_QUALITY" not in player
assert "xsNetworkServers" not in player
assert "inspectServerPayload" not in player

# Server discovery is scoped to FrameXTV's exact Select Server popup.
scan_start = player.index("      function scanServers() {")
scan_end = player.index("\n      function reportCaption", scan_start)
scan = player[scan_start:scan_end]
assert "const root = xsV39ServerPanel();" in scan
assert "if (!root) return;" in scan
assert "root.querySelectorAll('button,[role=\"button\"],[role=\"menuitem\"]')" in scan
assert "document.querySelectorAll('button" not in scan
assert "subtitle|caption|closed\\s*caption|\\bcc\\b" in scan
assert "xsV39Quality(meta" in scan
assert "v.videoHeight" in scan
assert "xsV39ServerQuality.set" in scan
assert "Full HD" in player and "4K" in player and "HD" in player
assert "/^Select Server$/i" in player

# Swift has a second defensive boundary against subtitle rows entering servers.
server_case_start = player.index('        case "xs:servers":')
server_case_end = player.index('\n        case "xs:qualities":', server_case_start)
server_case = player[server_case_start:server_case_end]
assert "let subtitleLike" in server_case
assert 'serverFolded.contains("subtitle")' in server_case
assert 'serverFolded.contains("caption")' in server_case
assert '!name.isEmpty, !subtitleLike' in server_case

# Quality & Server opens only the real server picker. It must not invoke generic
# metadata/subtitle discovery because that was the regression seen on device.
quality_start = player.index("    private var qualityPanel: some View {")
quality_end = player.index("\n    private var subtitlesPanel", quality_start)
quality_panel = player[quality_start:quality_end]
assert "player.requestServerMenu()" in quality_panel
assert "player.requestMetadata()" not in quality_panel
assert "player.requestSubtitleMenu()" not in quality_panel
assert "func requestServerMenu()" in player
assert "action === 'serverMenu'" in player

# V24 source-owned subtitle selection remains intact.
assert "sourceSubtitles.select(payload)" in player
assert "xs:subtitleSelected" in player
assert "subtitleFrameID" in player

# Black/Gray/White/None and opacity are propagated directly to the source-owned
# subtitle adapter after legacy command handlers have run.
assert "p.action !== 'subtitleStyle'" in player
assert "backgroundStyle: String(p.backgroundStyle" in player
assert "backgroundOpacity: Math.max(0, Math.min(1" in player
assert "window.setTimeout(() => sourceSubtitles.setStyle(completeStyle), 0)" in player

assert '@AppStorage("XSTV.subtitleBackgroundStyle")' in player
assert '@AppStorage("XSTV.subtitleBackgroundOpacity")' in player
assert ".onChange(of: subtitleBackgroundStyle)" in player
assert ".onChange(of: subtitleBackgroundOpacity)" in player
assert "backgroundStyle: subtitleBackgroundStyle" in player
assert "backgroundOpacity: subtitleBackgroundOpacity" in player

# Both source DOM/WebVTT and Swift delayed-caption paths use the chosen style.
apply_start = player.index("      function applyStyle() {")
apply_end = player.index("\n      function installCaptionObserver() {", apply_start)
apply_style = player[apply_start:apply_end]
assert "const bg = subtitleBackgroundCSS();" in apply_style
assert "background-color', bg" in apply_style
assert "background-image', 'none'" in apply_style
assert "deepest.length ? deepest : [el]" in apply_style
assert "-webkit-box-decoration-break" in apply_style
assert 'subtitleBackgroundColor.opacity(subtitleBackgroundOpacity)' in player
assert 'subtitleBackgroundStyle == "none" ? Color.clear' in player

print("V39R QA PASS: V39 preserved, server/subtitle isolation enforced, quality decorated, subtitle background/opacity propagated")
