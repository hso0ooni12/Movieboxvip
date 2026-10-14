"""R5: restore the proven non-crashing live surface and keep Backup source UI alive."""
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"V39 R5 stability restore: missing {label}")
    return text.replace(old, new, 1)


player_path = Path("FrameNative/FrameXTVPlayerV6.swift")
sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
player = player_path.read_text(encoding="utf-8")
sports = sports_path.read_text(encoding="utf-8")

# Backup can require its own source popup for a follow-up handoff. Do not hide
# that popup from the native bridge after an accepted source-row tap.
player = replace_once(
    player,
    '''                  scanServers();
                  hideSourcePanels();
                  finishSelection();
''',
    '''                  scanServers();
                  finishSelection();
''',
    "Backup source popup preservation",
)
player_path.write_text(player, encoding="utf-8")

# R4's controller host was an experimental rotation path and crashes on some
# live-channel opens. Restore the previously proven UIView surface verbatim;
# it still has the non-zero-size gate, Auto Layout drawable and final rebind.
r4_prefix_start = sports.index("// V39_R4_ROOT_FIXES")
r4_prefix_end = sports.index("    final class Coordinator {", r4_prefix_start)
r3_prefix = '''// V39_R5_STABILITY_RESTORE
private struct XSVLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer
    let onSurfaceReady: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player, onSurfaceReady: onSurfaceReady)
    }

    func makeUIView(context: Context) -> XSVLCStableSurfaceView {
        let host = XSVLCStableSurfaceView(frame: .zero)
        context.coordinator.attach(host)
        return host
    }

    func updateUIView(_ uiView: XSVLCStableSurfaceView, context: Context) {
        context.coordinator.attach(uiView)
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        context.coordinator.refreshGeometry()
    }

    static func dismantleUIView(_ uiView: XSVLCStableSurfaceView, coordinator: Coordinator) {
        // Do not clear player.drawable here. SwiftUI can dismantle/remount views
        // during interface transitions. A real player close calls model.stop(),
        // which clears the drawable explicitly and safely.
        coordinator.detach(uiView)
    }

'''
sports = sports[:r4_prefix_start] + r3_prefix + sports[r4_prefix_end:]

old_transition_method = '''        func transitionDidFinish() {
            // This is called by UIKit after the rotation coordinator has
            // committed final bounds, not from the early device notification.
            scheduleGeometryRefreshes()
        }

'''
sports = replace_once(sports, old_transition_method, "", "R4 controller transition callback")

old_install = '''        private func installObservers() {
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
'''
new_install = '''        private func installObservers() {
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleGeometryRefreshes()
            })
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
'''
sports = replace_once(sports, old_install, new_install, "R3 orientation geometry observer")
sports_path.write_text(sports, encoding="utf-8")
