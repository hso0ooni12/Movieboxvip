"""Regression guard for the surgical V39 device refinements."""
from pathlib import Path


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"V39 device refinement guard failed: missing {label}")


player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")

# The server list is compact presentation only; the original source command
# and its source provider payload must still be the route used on a tap.
require(player, 'ScrollView(showsIndicators: false)', "compact server-only scroller")
require(player, 'LazyVStack(alignment: .leading, spacing: 8)', "compact server row stack")
require(player, 'player.selectServer(server)', "native row source selection")
server_start = player.index("    func selectServer(_ server: XSServerOption)")
server_end = player.index("\n    func selectQuality", server_start)
server_function = player[server_start:server_end]
require(server_function, 'var payload: [String: Any] = ["action": "server", "name": server.name]', "server name payload")
require(server_function, 'if let provider = server.provider { payload["provider"] = provider }', "server provider payload")
require(server_function, "send(payload)", "server command dispatch")

# Subtitle filtering is covered by the adapter's node regression suite.  This
# final-source guard verifies that the appearance values now reach its existing
# source-owned renderer instead of being discarded at the bridge.
require(player, "const backgroundStyle = String(payload.backgroundStyle", "subtitle background style bridge")
require(player, "const requestedOpacity = Number(payload.backgroundOpacity);", "subtitle opacity input")
require(player, "backgroundOpacity:backgroundOpacity", "subtitle opacity forwarded")
require(player, "function subtitleBackgroundCSS()", "source subtitle background renderer")

# Opening live TV now waits for a valid UIKit drawable.  During the first
# connection, orientation recovery does not replay VLC or reset its scale;
# after the first frame, later rotations preserve normal auto-fit recovery.
require(sports, "V39_DEVICE_REFINEMENTS", "refinement marker")
require(sports, "onSurfaceReady: { model.surfaceDidBecomeReady() }", "surface-ready callback")
require(sports, "private var waitingForInitialSurface = false", "pending initial surface state")
require(sports, "func surfaceDidBecomeReady()", "surface-ready model hook")
require(sports, "guard waitingForInitialSurface, !hasStartedPlayback else { return }", "single initial start")
require(sports, "guard size.width > 1, size.height > 1 else { return }", "non-zero drawable guard")
require(sports, "private var didReportUsableSurface = false", "usable-surface state")
require(sports, "if !didReportUsableSurface {", "usable-surface callback")
require(sports, "if hasPlayedCurrentSource || player.isPlaying {", "deferred rotation scale reset")
require(sports, "if self.hasPlayedCurrentSource && !self.player.isPlaying && self.player.state == .paused", "post-first-frame pause recovery")
require(sports, "if player.isPlaying {\n                    player.scaleFactor = 0.0", "post-first-frame surface auto-fit")
require(sports, "for delay in [0.0, 0.06, 0.18, 0.40, 0.82]", "settled geometry passes")

surface_start = sports.index("private struct XSVLCVideoSurface")
attach_start = sports.index("        func attach(", surface_start)
attach_end = sports.index("        func detach(", attach_start)
attach = sports[attach_start:attach_end]
if "player.drawable = host.videoView" in attach:
    raise SystemExit("V39 device refinement guard failed: attach still binds a zero-sized drawable")

refresh_start = sports.index("        func refreshGeometry()", surface_start)
refresh_end = sports.index("        private func scheduleGeometryRefreshes()", refresh_start)
refresh = sports[refresh_start:refresh_end]
if refresh.index("guard size.width > 1, size.height > 1 else { return }") > refresh.index("player.drawable = drawable"):
    raise SystemExit("V39 device refinement guard failed: drawable may be assigned before size validation")

print("V39 device refinement guard PASS: source selection preserved and early rotation is surface-gated")

