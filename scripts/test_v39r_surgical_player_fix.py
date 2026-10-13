from pathlib import Path
import runpy

# This test is executed only after the proven V39 regression suite has generated
# the final V39 sources. Then it applies the surgical recovery patch and checks
# the exact boundaries that regressed in V40-V42.
runpy.run_path("scripts/app_v39r_surgical_player_fix.py", run_name="__main__")

player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")

assert "V39R_SURGICAL_PLAYER_FIX" in player
assert "V39_STABLE_VLC_SURFACE" in sports

# We really are building on V39, not carrying the broad V40/V42 server scanner
# that caused subtitle rows to appear inside Quality & Server on-device.
assert "V40_PLAYER_SERVER_AUDIT" not in player
assert "V42_FRAME_SOURCE_SERVER_QUALITY" not in player
assert "xsNetworkServers" not in player
assert "inspectServerPayload" not in player

# The server list is source-popup scoped. Generic document-wide menu/div scans
# are forbidden in scanServers; the only document lookup is for the exact
# source heading "Select Server" in xsV39ServerPanel().
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

# A second Swift boundary rejects any malformed server event that looks like a
# subtitle/caption catalog row. This catches the exact screenshot regression.
server_case_start = player.index('        case "xs:servers":')
server_case_end = player.index('\n        case "xs:qualities":', server_case_start)
server_case = player[server_case_start:server_case_end]
assert "let subtitleLike" in server_case
assert 'serverFolded.contains("subtitle")' in server_case
assert 'serverFolded.contains("caption")' in server_case
assert '!name.isEmpty, !subtitleLike' in server_case

# The V39 quality panel explicitly requests the real server popup; subtitles
# continue to use their own V24 source-owned popup and selection channel.
assert "func requestServerMenu()" in player
assert "player.requestServerMenu()" in player
assert "action === 'serverMenu'" in player
assert "sourceSubtitles.select(payload)" in player
assert "xs:subtitleSelected" in player
assert "subtitleFrameID" in player

# Root cause of Black/Gray/opacity bug: the command bridge used to drop
# backgroundStyle/backgroundOpacity. Both values must now survive into the
# source adapter on every slider/button change.
style_action = player[player.index("a==='subtitleStyle'"):]
style_action = style_action[:style_action.index("else if", 30) if "else if" in style_action[30:] else 800]
assert "backgroundStyle:String(p.backgroundStyle" in style_action
assert "backgroundOpacity:Math.max(0,Math.min(1" in style_action
assert "applySubtitleStyle()" in style_action

assert '@AppStorage("XSTV.subtitleBackgroundStyle")' in player
assert '@AppStorage("XSTV.subtitleBackgroundOpacity")' in player
assert ".onChange(of: subtitleBackgroundStyle)" in player
assert ".onChange(of: subtitleBackgroundOpacity)" in player
assert "backgroundStyle: subtitleBackgroundStyle" in player
assert "backgroundOpacity: subtitleBackgroundOpacity" in player

# Both rendering paths honor the chosen background and opacity: WebVTT/DOM
# source captions and the Swift custom timing overlay.
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

print("V39R QA PASS: V39 baseline preserved, server/subtitle isolation enforced, quality decorated, background/opacity propagated")
