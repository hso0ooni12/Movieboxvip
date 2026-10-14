"""Guards for R4 Backup handoff and UIKit-final live surface fixes."""
from pathlib import Path


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"V39 R4 guard failed: missing {label}")


player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")

server_start = player.index("else if (action === 'server')")
server_end = player.index("else if (action === 'metadata')", server_start)
server = player[server_start:server_end]
require(server, "const finishDispatchedSelection = () =>", "single dispatched source handoff")
require(server, "if (clicked) {\n                  finishDispatchedSelection();\n                  return;", "no retry after accepted source tap")
require(server, "setTimeout(() => trySelect(attempt + 1), 140);", "retry only when no source row accepted")
if server.index("hideSourcePanels();") < server.index("setTimeout(() => {"):
    raise SystemExit("V39 R4 guard failed: source panel still closes before Backup accepts its tap")

require(sports, "V39_R4_ROOT_FIXES", "R4 marker")
require(sports, "private final class XSVLCVideoSurfaceController: UIViewController", "UIKit live surface controller")
require(sports, "override func viewWillTransition", "UIKit rotation lifecycle")
require(sports, "completion: { _ in", "rotation completion callback")
require(sports, "private struct XSVLCVideoSurface: UIViewControllerRepresentable", "controller representable")
require(sports, "func transitionDidFinish()", "final-bounds handoff")
require(sports, "controller.onTransitionCompleted = { context.coordinator.transitionDidFinish() }", "surface transition hook")
surface = sports[sports.index("V39_R4_ROOT_FIXES"):]
if "forName: UIDevice.orientationDidChangeNotification" in surface:
    raise SystemExit("V39 R4 guard failed: VLC still resets from an early device orientation event")
if "player.drawable = nil" in surface:
    raise SystemExit("V39 R4 guard failed: live rotation detaches the VLC drawable")

print("V39 R4 root guard PASS: Backup is tapped once and VLC waits for UIKit final bounds")
