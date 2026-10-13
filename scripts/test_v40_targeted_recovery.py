from pathlib import Path

player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")

required = [
    "V40_V39_TARGETED_RECOVERY",
    "var displayQuality: String",
    'return "4K"',
    'return "Full HD"',
    'return "HD"',
    'let subtitleContamination = lowered.hasPrefix("subtitle")',
    'lowered.contains("subtitles •")',
    'panelRow(title: server.name, detail: "\\(server.displayQuality) · \\(server.selected ? \"Connected\" : \"Available\")")',
    "const nativeCaption = !!(active && trackFor(active));",
    "const selectedTrack = active ? trackFor(active) : null;",
    "selectedTrack.mode = 'hidden';",
    "child.style.setProperty('background-color', 'transparent', 'important');",
    "Slider(value: $subtitleBackgroundOpacity, in: 0.0...1.0, step: 0.05)",
    'case "gray": return Color(white: 0.28)',
    ".background(subtitleBackgroundStyle == \"none\" ? Color.clear : subtitleBackgroundColor.opacity(subtitleBackgroundOpacity), in: RoundedRectangle(cornerRadius: 7))",
]
for marker in required:
    assert marker in player, f"V40 missing marker: {marker}"

# Regression boundaries: server and subtitle lists remain separate Swift models.
assert 'case "xs:servers":' in player
assert 'case "xs:subtitles":' in player
server_start = player.index('case "xs:servers":')
server_end = player.index('case "xs:qualities":', server_start)
server_block = player[server_start:server_end]
assert "XSSubtitleOption" not in server_block
assert "subtitleOptions =" not in server_block
assert "guard !subtitleContamination else { return nil }" in server_block

# V39's proven source-owned subtitle selection remains untouched: only visual
# presentation moves to SwiftUI after the source confirms/loads the real track.
for marker in [
    "sourceSubtitles.select(payload)",
    "sourceSubtitles.reset()",
    "xs:subtitleSelected",
    "pendingSubtitleID",
    "subtitleFrameID",
]:
    assert marker in player, f"V39 subtitle ownership regression: {marker}"

# There must no longer be a delay-only condition for native cue ownership.
assert "const selectedTrack = delay && active ? trackFor(active) : null;" not in player
assert "if (!delay || !active) { caption(''); return; }" not in player

# No post-V39 network subtitle catalog injection is allowed in this recovery.
# The selected source's own subtitle menu remains authoritative.
assert "networkSubtitleItems" not in player

print("V40 targeted V39 recovery integrity PASS")
