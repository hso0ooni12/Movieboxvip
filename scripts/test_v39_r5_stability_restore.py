"""Regression guard for the R5 stability restore."""
from pathlib import Path


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"V39 R5 guard failed: missing {label}")


player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")

server_start = player.index("else if (action === 'server')")
server_end = player.index("else if (action === 'metadata')", server_start)
server = player[server_start:server_end]
require(server, "const finishDispatchedSelection = () =>", "single Backup source tap")
if "hideSourcePanels();" in server:
    raise SystemExit("V39 R5 guard failed: native bridge still hides Backup source handoff UI")

require(sports, "V39_R5_STABILITY_RESTORE", "R5 marker")
require(sports, "private struct XSVLCVideoSurface: UIViewRepresentable", "proven UIView surface")
require(sports, "func makeUIView(context: Context) -> XSVLCStableSurfaceView", "stable surface creation")
require(sports, "forName: UIDevice.orientationDidChangeNotification", "stable geometry refresh")
surface = sports[sports.index("V39_R5_STABILITY_RESTORE"):]
if "UIViewControllerRepresentable" in surface or "XSVLCVideoSurfaceController" in surface:
    raise SystemExit("V39 R5 guard failed: experimental controller surface still present")
if "player.drawable = nil" in surface:
    raise SystemExit("V39 R5 guard failed: live surface detaches VLC drawable")

print("V39 R5 stability guard PASS: Backup UI preserved and live player uses proven UIView surface")
