"""Surgical V39 device refinements applied after the verified baseline checks."""
from pathlib import Path


player_path = Path("FrameNative/FrameXTVPlayerV6.swift")
sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
player = player_path.read_text(encoding="utf-8")
sports = sports_path.read_text(encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"V39 device refinement: missing {label}")
    return text.replace(old, new, 1)


# Presentation only: give source-provided servers their own compact scroller.
old_quality_panel = '''    private var qualityPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("QUALITY").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(player.qualities) { quality in
                    panelRow(title: quality.name, detail: quality.selected ? "Selected" : nil) {
                        player.selectQuality(quality)
                        closePanel()
                    }
                }

                Divider().padding(.vertical, 6)
                Text("SERVERS").font(.caption.bold()).foregroundStyle(.secondary)
                Text("Quality appears only when FrameXTV provides it")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(player.servers) { server in
                    nativeServerRow(server)
                }
            }
        }
        .onAppear {
            player.requestQualityMenu()
            player.requestMetadata()
        }
    }
'''
new_quality_panel = '''    private var qualityPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !player.qualities.isEmpty {
                Text("QUALITY").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(player.qualities) { quality in
                    panelRow(title: quality.name, detail: quality.selected ? "Selected" : nil) {
                        player.selectQuality(quality)
                        closePanel()
                    }
                }
                Divider().padding(.vertical, 2)
            }

            Text("SERVERS").font(.caption.bold()).foregroundStyle(.secondary)
            Text("Quality appears only when FrameXTV provides it")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // The server mechanics remain player.selectServer(server).  Only
            // this list scrolls, so AUTO no longer stretches a blank gap.
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(player.servers) { server in
                        nativeServerRow(server)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear {
            player.requestQualityMenu()
            player.requestMetadata()
        }
    }
'''
player = replace_once(player, old_quality_panel, new_quality_panel, "quality/server panel")

# V25 already renders style/opacity source-side; the bridge below had discarded
# those values before they reached that renderer.
old_subtitle_style = '''          else if (action === 'subtitleStyle') {
            subtitleStyle={size:Number(payload.size||1),color:String(payload.color||'#ffffff'),background:!!payload.background,bottom:Number(payload.bottom||76)};
            applySubtitleStyle();
          }
'''
new_subtitle_style = '''          else if (action === 'subtitleStyle') {
            const backgroundStyle = String(payload.backgroundStyle || (payload.background === false ? 'none' : 'black')).toLowerCase();
            const requestedOpacity = Number(payload.backgroundOpacity);
            const backgroundOpacity = Number.isFinite(requestedOpacity) ? Math.max(0, Math.min(1, requestedOpacity)) : 0.68;
            subtitleStyle={
              size:Number(payload.size||1),
              color:String(payload.color||'#ffffff'),
              background:backgroundStyle !== 'none' && !!payload.background,
              backgroundStyle:backgroundStyle,
              backgroundOpacity:backgroundOpacity,
              bottom:Number(payload.bottom||76)
            };
            applySubtitleStyle();
          }
'''
player = replace_once(player, old_subtitle_style, new_subtitle_style, "subtitle style bridge")
player_path.write_text(player, encoding="utf-8")


# Live TV: wait for a non-zero, attached surface before first play.  An
# immediate rotation used to start VLC against a temporary portrait drawable.
sports = replace_once(
    sports,
    '''                XSVLCVideoSurface(player: model.player)
                    .frame(width: proxy.size.width, height: proxy.size.height)
''',
    '''                XSVLCVideoSurface(
                    player: model.player,
                    onSurfaceReady: { model.surfaceDidBecomeReady() }
                )
                    .frame(width: proxy.size.width, height: proxy.size.height)
''',
    "live surface callback",
)
sports = replace_once(
    sports,
    '''    private var hasPlayedCurrentSource = false
    private var suppressStoppedUntil = Date.distantPast
''',
    '''    private var hasPlayedCurrentSource = false
    private var surfaceIsReady = false
    private var waitingForInitialSurface = false
    private var hasStartedPlayback = false
    private var suppressStoppedUntil = Date.distantPast
''',
    "live startup state",
)
sports = replace_once(
    sports,
    '''    func start() {
        guard !urls.isEmpty else {
            statusText = "Stream unavailable"
            return
        }
        play(index: currentIndex)
    }

    func play(index: Int) {
''',
    '''    func start() {
        guard !urls.isEmpty else {
            statusText = "Stream unavailable"
            return
        }
        if !hasStartedPlayback && !surfaceIsReady {
            waitingForInitialSurface = true
            statusText = "Connecting…"
            return
        }
        waitingForInitialSurface = false
        play(index: currentIndex)
    }

    func surfaceDidBecomeReady() {
        surfaceIsReady = true
        guard waitingForInitialSurface, !hasStartedPlayback else { return }
        waitingForInitialSurface = false
        play(index: currentIndex)
    }

    func play(index: Int) {
''',
    "live startup gate",
)
sports = replace_once(
    sports,
    '''        currentIndex = index
        statusText = index == 0 ? "Connecting…" : "Trying backup source…"
        isPlaying = false
''',
    '''        currentIndex = index
        statusText = index == 0 ? "Connecting…" : "Trying backup source…"
        waitingForInitialSurface = false
        hasStartedPlayback = true
        isPlaying = false
''',
    "live start transition",
)
old_recovery = '''    func recoverAfterSurfaceChange() {
        guard !userPaused, player.media != nil else { return }
        player.scaleFactor = 0.0
        recoveryTask?.cancel()
        let myGeneration = generation
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                // Do not reload or change source during rotation. Re-loading a
                // healthy live stream is what caused some channels to vanish.
                if !self.player.isPlaying && self.player.state == .paused {
                    self.player.play()
                }
            }
        }
    }
'''
new_recovery = '''    func recoverAfterSurfaceChange() {
        guard !userPaused, player.media != nil else { return }
        // Do not reset output sizing or replay while the first frame is still
        // connecting.  The surface callback supplies the final rotation size.
        if hasPlayedCurrentSource || player.isPlaying {
            player.scaleFactor = 0.0
        }
        recoveryTask?.cancel()
        let myGeneration = generation
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                if self.hasPlayedCurrentSource && !self.player.isPlaying && self.player.state == .paused {
                    self.player.play()
                }
            }
        }
    }
'''
sports = replace_once(sports, old_recovery, new_recovery, "early rotation recovery")
sports = replace_once(
    sports,
    '''        userPaused = true
        suppressStoppedUntil = Date().addingTimeInterval(0.75)
        player.stop()
''',
    '''        userPaused = true
        waitingForInitialSurface = false
        suppressStoppedUntil = Date().addingTimeInterval(0.75)
        player.stop()
''',
    "live stop state",
)

# A drawable is now attached only inside refreshGeometry, after its bounds are
# valid.  The callback starts the initial live session exactly once.
sports = replace_once(
    sports,
    '''private struct XSVLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }
''',
    '''private struct XSVLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer
    let onSurfaceReady: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player, onSurfaceReady: onSurfaceReady)
    }
''',
    "surface coordinator input",
)
sports = replace_once(
    sports,
    '''        private let player: VLCMediaPlayer
        private weak var host: XSVLCStableSurfaceView?
        private var observers: [NSObjectProtocol] = []
        private var refreshWorkItems: [DispatchWorkItem] = []
        private var lastDrawableSize: CGSize = .zero

        init(player: VLCMediaPlayer) {
            self.player = player
        }
''',
    '''        private let player: VLCMediaPlayer
        private let onSurfaceReady: () -> Void
        private weak var host: XSVLCStableSurfaceView?
        private var observers: [NSObjectProtocol] = []
        private var refreshWorkItems: [DispatchWorkItem] = []
        private var lastDrawableSize: CGSize = .zero
        private var didReportUsableSurface = false

        init(player: VLCMediaPlayer, onSurfaceReady: @escaping () -> Void) {
            self.player = player
            self.onSurfaceReady = onSurfaceReady
        }
''',
    "surface coordinator state",
)
sports = replace_once(
    sports,
    '''            host.setNeedsLayout()
            host.layoutIfNeeded()
            if hostChanged || player.drawable as AnyObject? !== host.videoView {
                player.drawable = host.videoView
            }
            refreshGeometry()
''',
    '''            host.setNeedsLayout()
            host.layoutIfNeeded()
            if hostChanged { didReportUsableSurface = false }
            // refreshGeometry never binds the temporary zero-sized drawable.
            refreshGeometry()
''',
    "zero-sized drawable binding",
)
old_refresh = '''        func refreshGeometry() {
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
'''
new_refresh = '''        func refreshGeometry() {
            guard let host else { return }
            host.setNeedsLayout()
            host.layoutIfNeeded()
            let drawable = host.videoView
            let size = drawable.bounds.size
            guard size.width > 1, size.height > 1 else { return }

            let drawableChanged = player.drawable as AnyObject? !== drawable
            let sizeChanged = abs(size.width - lastDrawableSize.width) > 0.5 || abs(size.height - lastDrawableSize.height) > 0.5
            if drawableChanged {
                player.drawable = drawable
            }
            if !didReportUsableSurface {
                didReportUsableSurface = true
                onSurfaceReady()
            }
            if drawableChanged || sizeChanged {
                lastDrawableSize = size
                // Later rotations still auto-fit.  The first connection keeps
                // the final drawable untouched until VLC has a real frame.
                if player.isPlaying {
                    player.scaleFactor = 0.0
                }
            }
        }
'''
sports = replace_once(sports, old_refresh, new_refresh, "settled geometry refresh")
sports = replace_once(
    sports,
    "            for delay in [0.0, 0.05, 0.16, 0.34, 0.65] {\n",
    "            for delay in [0.0, 0.06, 0.18, 0.40, 0.82] {\n",
    "settled geometry timing",
)
if "V39_DEVICE_REFINEMENTS" not in sports:
    sports = "// V39_DEVICE_REFINEMENTS: first-frame drawable gating and early-rotation protection.\n" + sports
sports_path.write_text(sports, encoding="utf-8")

print("Applied V39 device refinements: compact servers, working subtitle opacity, early-rotation-safe live surface")

