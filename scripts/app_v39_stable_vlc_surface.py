from pathlib import Path

sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
sports = sports_path.read_text(encoding="utf-8")

# V39: Device recording showed that rebuilding the MobileVLCKit drawable during
# rotation can leave decoding alive (status remains LIVE) while video output is
# black. Keep one stable drawable for the life of the player instead. A host
# UIView owns an inner video UIView whose frame follows the final container
# bounds. On geometry changes we reset VLC scaleFactor to zero so libvlc fits
# the existing drawable again, without stopping media or swapping the drawable.

if "V39_STABLE_VLC_SURFACE" not in sports:
    sports = "// V39_STABLE_VLC_SURFACE: persistent drawable + explicit inner-view resize + VLC auto-scale reset.\n" + sports

# Remove V38's drawable-remount state. Rebuilding the UIView was confirmed by
# an on-device recording to black out some live channels after rotation.
for state_line in [
    "    @State private var surfaceGeneration = 0\n",
    "    @State private var lastSurfaceSize: CGSize = .zero\n",
    "    @State private var surfaceRepairTask: Task<Void, Never>?\n",
]:
    sports = sports.replace(state_line, "", 1)

old_surface = '''            GeometryReader { proxy in
                XSVLCVideoSurface(player: model.player)
                    .id(surfaceGeneration)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .onAppear {
                        observeSurfaceSize(proxy.size)
                    }
                    .onChange(of: proxy.size) { newSize in
                        observeSurfaceSize(newSize)
                    }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
'''
new_surface = '''            GeometryReader { proxy in
                XSVLCVideoSurface(player: model.player)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
'''
if old_surface not in sports:
    raise SystemExit("V39: V38 GeometryReader surface block not found")
sports = sports.replace(old_surface, new_surface, 1)

sports = sports.replace("            surfaceRepairTask?.cancel()\n", "", 2)

# Remove V38's observe/debounce/remount helper completely.
helper_start = sports.find("    private func observeSurfaceSize(_ size: CGSize) {")
helper_end = sports.find("    private func closePlayer() {", helper_start)
if helper_start < 0 or helper_end < 0:
    raise SystemExit("V39: V38 surface observer helper not found")
sports = sports[:helper_start] + sports[helper_end:]

# Reset VLC to automatic output scaling whenever playback starts. scaleFactor=0
# means fit the current drawable/window according to MobileVLCKit's own API.
media_anchor = '''        player.media = media
        player.play()
'''
media_replacement = '''        player.media = media
        player.scaleFactor = 0.0
        player.play()
'''
if media_anchor not in sports:
    raise SystemExit("V39: player media/play anchor not found")
sports = sports.replace(media_anchor, media_replacement, 1)

# Surface recovery is geometry-only: do not reload/switch sources. Reset output
# scaling first; only resume if VLC itself is paused unexpectedly.
recovery_anchor = '''    func recoverAfterSurfaceChange() {
        guard !userPaused, player.media != nil else { return }
        recoveryTask?.cancel()
'''
recovery_replacement = '''    func recoverAfterSurfaceChange() {
        guard !userPaused, player.media != nil else { return }
        player.scaleFactor = 0.0
        recoveryTask?.cancel()
'''
if recovery_anchor not in sports:
    raise SystemExit("V39: recovery anchor not found")
sports = sports.replace(recovery_anchor, recovery_replacement, 1)

# Replace the V35/V36 drawable bridge. The drawable is now the persistent inner
# videoView, never detached merely because width/height changed. The outer host
# can follow SwiftUI geometry and explicitly lays the drawable to its bounds.
surface_start = sports.find("private final class XSVLCDrawableHostView")
if surface_start < 0:
    raise SystemExit("V39: old drawable host block not found")

stable_surface = r'''private final class XSVLCStableSurfaceView: UIView {
    let videoView = UIView(frame: .zero)
    var onGeometryChanged: (() -> Void)?
    private var lastSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        backgroundColor = .black
        clipsToBounds = true
        isUserInteractionEnabled = false

        videoView.backgroundColor = .black
        videoView.clipsToBounds = true
        videoView.isUserInteractionEnabled = false
        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(videoView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        UIView.performWithoutAnimation {
            videoView.transform = .identity
            videoView.frame = bounds
            videoView.layoutIfNeeded()
        }

        let size = bounds.size
        guard size.width > 1, size.height > 1 else { return }
        if abs(size.width - lastSize.width) > 0.5 || abs(size.height - lastSize.height) > 0.5 {
            lastSize = size
            onGeometryChanged?()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            setNeedsLayout()
            layoutIfNeeded()
            onGeometryChanged?()
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
        onGeometryChanged?()
    }
}

private struct XSVLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
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

    final class Coordinator {
        private let player: VLCMediaPlayer
        private weak var host: XSVLCStableSurfaceView?
        private var observers: [NSObjectProtocol] = []
        private var refreshWorkItems: [DispatchWorkItem] = []
        private var lastDrawableSize: CGSize = .zero

        init(player: VLCMediaPlayer) {
            self.player = player
        }

        deinit {
            refreshWorkItems.forEach { $0.cancel() }
            for token in observers { NotificationCenter.default.removeObserver(token) }
        }

        func attach(_ host: XSVLCStableSurfaceView) {
            let hostChanged = self.host !== host
            self.host = host
            host.onGeometryChanged = { [weak self] in
                self?.scheduleGeometryRefreshes()
            }

            if observers.isEmpty { installObservers() }

            host.setNeedsLayout()
            host.layoutIfNeeded()
            if hostChanged || player.drawable as AnyObject? !== host.videoView {
                player.drawable = host.videoView
            }
            refreshGeometry()
        }

        func detach(_ host: XSVLCStableSurfaceView) {
            host.onGeometryChanged = nil
            if self.host === host { self.host = nil }
            refreshWorkItems.forEach { $0.cancel() }
            refreshWorkItems.removeAll()
            // Intentionally keep player.drawable intact until either a new host
            // attaches or model.stop() performs the real teardown.
        }

        func refreshGeometry() {
            guard let host else { return }
            host.setNeedsLayout()
            host.layoutIfNeeded()
            let drawable = host.videoView
            let size = drawable.bounds.size
            guard size.width > 1, size.height > 1 else { return }

            if player.drawable as AnyObject? !== drawable {
                player.drawable = drawable
            }

            // Zero is MobileVLCKit's documented automatic-fit mode. Resetting it
            // after each settled geometry change forces libvlc to recalculate
            // output dimensions for the same drawable without interrupting live
            // media or creating a new rendering surface.
            if abs(size.width - lastDrawableSize.width) > 0.5 || abs(size.height - lastDrawableSize.height) > 0.5 {
                lastDrawableSize = size
                player.scaleFactor = 0.0
            }
        }

        private func scheduleGeometryRefreshes() {
            refreshWorkItems.forEach { $0.cancel() }
            refreshWorkItems.removeAll()
            for delay in [0.0, 0.05, 0.16, 0.34, 0.65] {
                let item = DispatchWorkItem { [weak self] in
                    self?.refreshGeometry()
                }
                refreshWorkItems.append(item)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            }
        }

        private func installObservers() {
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
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleGeometryRefreshes()
            })
        }
    }
}
'''

sports = sports[:surface_start] + stable_surface
sports_path.write_text(sports, encoding="utf-8")
print("Applied V39 stable VLC drawable rotation fix")
