"""R4: source Backup handoff and UIKit-complete live rotation fixes."""
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"V39 R4 root fix: missing {label}")
    return text.replace(old, new, 1)


player_path = Path("FrameNative/FrameXTVPlayerV6.swift")
sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
player = player_path.read_text(encoding="utf-8")
sports = sports_path.read_text(encoding="utf-8")

# Once the exact source row has accepted the tap, do not press it again while
# its provider is loading. Backup is one of the providers that updates its
# Connected label late, so retrying the tap can toggle/interrupt the handoff.
old_server_command = '''              const trySelect = (attempt) => {
                let clicked = selectServerRow(name, quality);
                if (!clicked) openServerMenu();
                setTimeout(() => {
                  if (!clicked) clicked = selectServerRow(name, quality);
                  hideSourcePanels();
                  setTimeout(() => {
                    scanServers();
                    if (sourceServerIsSelected(name, quality)) {
                      finishSelection();
                    } else if (attempt < 3) {
                      openServerMenu();
                      setTimeout(() => trySelect(attempt + 1), 90);
                    }
                  }, 460);
                }, 190);
              };
'''
new_server_command = '''              const finishDispatchedSelection = () => {
                // The source row click is authoritative. Some providers only
                // mark Connected after their media handshake, so waiting for
                // that visual label must never cause a second row click.
                setTimeout(() => {
                  scanServers();
                  hideSourcePanels();
                  finishSelection();
                }, 680);
              };
              const trySelect = (attempt) => {
                let clicked = selectServerRow(name, quality);
                if (clicked) {
                  finishDispatchedSelection();
                  return;
                }
                openServerMenu();
                setTimeout(() => {
                  clicked = selectServerRow(name, quality);
                  if (clicked) {
                    finishDispatchedSelection();
                  } else if (attempt < 2) {
                    setTimeout(() => trySelect(attempt + 1), 140);
                  }
                }, 220);
              };
'''
player = replace_once(player, old_server_command, new_server_command, "repeat Backup source tap")
player_path.write_text(player, encoding="utf-8")

# UIViewRepresentable receives intermediate SwiftUI sizes during an immediate
# orientation change. Host the exact same drawable in a UIViewController so
# VLC is rebound after UIKit's transition coordinator reports final bounds.
old_surface = '''private struct XSVLCVideoSurface: UIViewRepresentable {
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
new_surface = '''// V39_R4_ROOT_FIXES
private final class XSVLCVideoSurfaceController: UIViewController {
    let host = XSVLCStableSurfaceView(frame: .zero)
    var onTransitionCompleted: (() -> Void)?

    override func loadView() {
        view = host
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        host.setNeedsLayout()
        host.layoutIfNeeded()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.host.setNeedsLayout()
            self.host.layoutIfNeeded()
        }, completion: { _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.host.setNeedsLayout()
                self.host.layoutIfNeeded()
                self.onTransitionCompleted?()
            }
        })
    }
}

private struct XSVLCVideoSurface: UIViewControllerRepresentable {
    let player: VLCMediaPlayer
    let onSurfaceReady: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player, onSurfaceReady: onSurfaceReady)
    }

    func makeUIViewController(context: Context) -> XSVLCVideoSurfaceController {
        let controller = XSVLCVideoSurfaceController()
        controller.onTransitionCompleted = { context.coordinator.transitionDidFinish() }
        context.coordinator.attach(controller.host)
        return controller
    }

    func updateUIViewController(_ controller: XSVLCVideoSurfaceController, context: Context) {
        controller.onTransitionCompleted = { context.coordinator.transitionDidFinish() }
        context.coordinator.attach(controller.host)
        controller.host.setNeedsLayout()
        controller.host.layoutIfNeeded()
        context.coordinator.refreshGeometry()
    }

    static func dismantleUIViewController(_ controller: XSVLCVideoSurfaceController, coordinator: Coordinator) {
        // A real player close calls model.stop(). Keep the drawable attached
        // while SwiftUI remounts its controller during a rotation.
        coordinator.detach(controller.host)
    }
'''
sports = replace_once(sports, old_surface, new_surface, "SwiftUI-only VLC surface")

sports = replace_once(
    sports,
    '''        func detach(_ host: XSVLCStableSurfaceView) {
''',
    '''        func transitionDidFinish() {
            // This is called by UIKit after the rotation coordinator has
            // committed final bounds, not from the early device notification.
            scheduleGeometryRefreshes()
        }

        func detach(_ host: XSVLCStableSurfaceView) {
''',
    "UIKit transition callback",
)

old_orientation_observer = '''            observers.append(center.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleGeometryRefreshes()
            })
'''
sports = replace_once(sports, old_orientation_observer, "", "early orientation observer")
sports_path.write_text(sports, encoding="utf-8")
