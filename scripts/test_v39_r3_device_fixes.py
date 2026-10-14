"""Regression guards for the R3 on-device server and live-surface fixes."""
from pathlib import Path


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"V39 R3 guard failed: missing {label}")


player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")

server_start = player.index("    func selectServer(_ server: XSServerOption)")
server_end = player.index("\n    func selectQuality", server_start)
server_function = player[server_start:server_end]
require(server_function, 'payload["quality"] = server.quality', "source quality payload")
require(player, "function selectServerRow(name, quality)", "precise source-row selector")
require(player, "function sourceServerIsSelected(name, quality)", "source selection acknowledgement")
require(player, "const key = row.name.toLowerCase() + '|' + row.quality;", "distinct same-name source rows")
command_start = player.index("else if (action === 'server')")
command_end = player.index("else if (action === 'metadata')", command_start)
command = player[command_start:command_end]
if command.lstrip().startswith("sourceSubtitles.reset()"):
    raise SystemExit("V39 R3 guard failed: subtitles reset before a server acknowledgement")
require(command, "if (sourceServerIsSelected(name, quality))", "server confirmation before reset")
require(command, "setTimeout(openAndScanSubtitles, 260)", "subtitle rescan after switch")

require(sports, "V39_R3_DEVICE_FIXES", "R3 marker")
require(sports, ".frame(maxWidth: .infinity, maxHeight: .infinity)", "full native surface")
if "GeometryReader { proxy in\n                XSVLCVideoSurface" in sports:
    raise SystemExit("V39 R3 guard failed: live surface still uses transient GeometryReader bounds")
require(sports, "videoView.translatesAutoresizingMaskIntoConstraints = false", "constraint-backed video surface")
require(sports, "videoView.bottomAnchor.constraint(equalTo: bottomAnchor)", "video surface bottom constraint")
require(sports, "func refreshGeometry(forceDrawableRebind: Bool = false)", "settled surface rebind API")
require(sports, "player.drawable = drawable", "final same-view VLC rebind")
require(sports, "index == delays.count - 1", "only final pass rebinds")
require(sports, "Do not touch VLC during the temporary portrait/landscape bounds.", "deferred raw orientation handling")
if "player.drawable = nil" in sports[sports.index("V39_R3_DEVICE_FIXES"):]:
    raise SystemExit("V39 R3 guard failed: rotation path detaches VLC drawable")

print("V39 R3 device guard PASS: acknowledged source switching and settled live rotation surface")
