from pathlib import Path
import re

sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
iptv_path = Path("FrameNative/Services/IPTVService.swift")
project_path = Path("project-native.yml")

sports = sports_path.read_text(encoding="utf-8")
iptv = iptv_path.read_text(encoding="utf-8")
project = project_path.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# V35 Sports player: direct tap hide/show, rotation-safe VLC drawable,
# resilient live recovery, faster startup/failover, and stable controls.
# Runs AFTER V34 so the compact iOS-style chrome is already present.
# ---------------------------------------------------------------------------

sports = sports.replace(
'''                .onTapGesture {
                    revealControls()
                }''',
'''                .onTapGesture {
                    toggleControlsFromCanvas()
                }''',
1,
)

old_reveal = '''    private func revealControls() {
        controlsHideTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = true }
        }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { controlsVisible = false }
        }
    }
'''
new_reveal = '''    private func toggleControlsFromCanvas() {
        controlsHideTask?.cancel()
        if controlsVisible {
            withAnimation(.easeOut(duration: 0.14)) { controlsVisible = false }
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        controlsHideTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.14)) { controlsVisible = true }
        }
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.16)) { controlsVisible = false }
        }
    }

    private func keepControlsVisible() {
        controlsHideTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeOut(duration: 0.14)) { controlsVisible = true }
        }
    }

    private func togglePlaybackFromControls() {
        model.togglePlayPause()
        if model.isPlaying {
            revealControls()
        } else {
            keepControlsVisible()
        }
    }
'''
if old_reveal not in sports:
    raise SystemExit("V35: revealControls block not found")
sports = sports.replace(old_reveal, new_reveal, 1)

# Keep the player alive across interface rotation / app activation without
# rebuilding the stream unless VLC actually fails to recover.
old_disappear = '''        .onDisappear {
            controlsHideTask?.cancel()
            model.stop()
        }
'''
new_disappear = '''        .onDisappear {
            controlsHideTask?.cancel()
            model.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            model.recoverAfterSurfaceChange()
            revealControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            model.recoverAfterSurfaceChange()
        }
'''
if old_disappear not in sports:
    raise SystemExit("V35: player lifecycle anchor not found")
sports = sports.replace(old_disappear, new_disappear, 1)

# V34 compact chrome actions: reset auto-hide timers correctly and keep controls
# visible while paused.
sports = sports.replace(
'''            Button {
                model.togglePlayPause()
            } label: {''',
'''            Button {
                togglePlaybackFromControls()
            } label: {''',
1,
)
sports = sports.replace(
'''                                Button {
                                    model.play(index: index)
                                } label: {''',
'''                                Button {
                                    revealControls()
                                    model.play(index: index)
                                } label: {''',
1,
)
sports = sports.replace(
'''                    Button { model.reload() } label: {''',
'''                    Button {
                        revealControls()
                        model.reload()
                    } label: {''',
1,
)

# Replace the VLC model with a hardened live-stream model. It keeps a user pause
# distinct from a stall, applies conservative live-network buffering, and only
# reloads after rotation if playback does not recover naturally.
model_start = sports.find("@MainActor\nprivate final class XSSportsVLCPlayerModel")
surface_start = sports.find("private struct XSVLCVideoSurface", model_start)
if model_start < 0 or surface_start < 0:
    raise SystemExit("V35: VLC model/surface blocks not found")

new_model = r'''@MainActor
private final class XSSportsVLCPlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    let urls: [URL]

    @Published var statusText = "Connecting…"
    @Published var currentIndex = 0
    @Published var isPlaying = false

    private var fallbackTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var generation = 0
    private var userPaused = false
    private var hasPlayedCurrentSource = false

    init(urls: [URL]) {
        self.urls = urls
        super.init()
        player.delegate = self
    }

    func start() {
        guard !urls.isEmpty else {
            statusText = "Stream unavailable"
            return
        }
        play(index: currentIndex)
    }

    func play(index: Int) {
        guard urls.indices.contains(index) else { return }
        generation += 1
        let myGeneration = generation
        fallbackTask?.cancel()
        recoveryTask?.cancel()
        currentIndex = index
        statusText = index == 0 ? "Connecting…" : "Trying backup source…"
        isPlaying = false
        userPaused = false
        hasPlayedCurrentSource = false

        player.stop()
        let media = VLCMedia(url: urls[index])
        let options: [String: Any] = [
            ":network-caching": 1400,
            ":live-caching": 1400,
            ":http-reconnect": NSNull()
        ]
        media.addOptions(options)
        player.media = media
        player.play()
        scheduleFallback(generation: myGeneration, delayNanoseconds: 7_000_000_000)
    }

    func reload() {
        play(index: currentIndex)
    }

    func togglePlayPause() {
        if player.isPlaying {
            userPaused = true
            player.pause()
            isPlaying = false
            statusText = "Paused"
            fallbackTask?.cancel()
            recoveryTask?.cancel()
        } else {
            userPaused = false
            player.play()
            isPlaying = true
            statusText = "Connecting…"
            scheduleFallback(generation: generation, delayNanoseconds: 7_000_000_000)
        }
    }

    func recoverAfterSurfaceChange() {
        guard !userPaused, player.media != nil else { return }
        recoveryTask?.cancel()
        let myGeneration = generation
        recoveryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                if !self.player.isPlaying {
                    self.player.play()
                }
            }
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                if !self.player.isPlaying && self.player.state != .buffering {
                    self.reload()
                }
            }
        }
    }

    func stop() {
        generation += 1
        fallbackTask?.cancel()
        recoveryTask?.cancel()
        userPaused = false
        player.stop()
        player.delegate = nil
        player.drawable = nil
        isPlaying = false
    }

    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.handleStateChanged(newState)
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.player.isPlaying {
                self.hasPlayedCurrentSource = true
                self.statusText = "Live"
                self.isPlaying = true
                self.fallbackTask?.cancel()
            }
        }
    }

    private func handleStateChanged(_ state: VLCMediaPlayerState) {
        if state == .playing {
            hasPlayedCurrentSource = true
            statusText = "Live"
            isPlaying = true
            fallbackTask?.cancel()
        } else if state == .buffering {
            if !userPaused { statusText = "Buffering…" }
        } else if state == .paused {
            if userPaused { statusText = "Paused" }
            isPlaying = false
        } else if state == .error {
            isPlaying = false
            if !userPaused { tryNextSource() }
        } else if state == .ended {
            isPlaying = false
            if !userPaused { reload() }
        }
    }

    private func scheduleFallback(generation myGeneration: Int, delayNanoseconds: UInt64) {
        fallbackTask?.cancel()
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation, !self.userPaused else { return }
                if self.player.isPlaying || self.hasPlayedCurrentSource {
                    return
                }
                if self.player.state == .buffering {
                    self.scheduleFallback(generation: myGeneration, delayNanoseconds: 4_000_000_000)
                } else {
                    self.tryNextSource()
                }
            }
        }
    }

    private func tryNextSource() {
        let next = currentIndex + 1
        if urls.indices.contains(next) {
            play(index: next)
        } else {
            fallbackTask?.cancel()
            statusText = "Stream unavailable"
            isPlaying = false
        }
    }
}

'''
sports = sports[:model_start] + new_model + sports[surface_start:]

# Replace the drawable bridge. VLC can lose its drawable during an iPhone/iPad
# rotation even though the decoder is still alive. This view rebinds on layout,
# window attachment, orientation, and app activation without tearing down media.
surface_start = sports.find("private struct XSVLCVideoSurface")
if surface_start < 0:
    raise SystemExit("V35: surface start not found after model replacement")
# surface is the final declaration in this file.
new_surface = r'''private final class XSVLCDrawableHostView: UIView {
    var onNeedsRebind: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onNeedsRebind?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { onNeedsRebind?() }
    }
}

private struct XSVLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeCoordinator() -> Coordinator {
        Coordinator(player: player)
    }

    func makeUIView(context: Context) -> XSVLCDrawableHostView {
        let view = XSVLCDrawableHostView(frame: .zero)
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        view.clipsToBounds = true
        context.coordinator.attach(view)
        return view
    }

    func updateUIView(_ uiView: XSVLCDrawableHostView, context: Context) {
        uiView.isUserInteractionEnabled = false
        context.coordinator.attach(uiView)
    }

    static func dismantleUIView(_ uiView: XSVLCDrawableHostView, coordinator: Coordinator) {
        coordinator.detach(uiView)
    }

    final class Coordinator {
        private let player: VLCMediaPlayer
        private weak var view: XSVLCDrawableHostView?
        private var observers: [NSObjectProtocol] = []
        private var lastBoundSize: CGSize = .zero

        init(player: VLCMediaPlayer) {
            self.player = player
        }

        deinit {
            for token in observers { NotificationCenter.default.removeObserver(token) }
        }

        func attach(_ view: XSVLCDrawableHostView) {
            self.view = view
            view.onNeedsRebind = { [weak self, weak view] in
                guard let self, let view else { return }
                self.bind(view)
            }
            if observers.isEmpty { installObservers() }
            bind(view)
            rebind(after: 0.08)
            rebind(after: 0.32)
        }

        func detach(_ view: XSVLCDrawableHostView) {
            view.onNeedsRebind = nil
            if self.view === view { self.view = nil }
            if player.drawable as AnyObject? === view {
                player.drawable = nil
            }
        }

        private func bind(_ view: XSVLCDrawableHostView) {
            guard view.window != nil || view.bounds.width > 0 else { return }
            let sizeChanged = view.bounds.size != lastBoundSize
            if player.drawable as AnyObject? !== view || sizeChanged {
                player.drawable = view
                lastBoundSize = view.bounds.size
            }
        }

        private func rebind(after delay: TimeInterval) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let view = self.view else { return }
                self.bind(view)
            }
        }

        private func installObservers() {
            let center = NotificationCenter.default
            observers.append(center.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.rebind(after: 0.05)
                self?.rebind(after: 0.28)
            })
            observers.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.rebind(after: 0.05)
            })
        }
    }
}
'''
sports = sports[:surface_start] + new_surface

if "V35_FINAL_POLISH" not in sports:
    sports = "// V35_FINAL_POLISH: tap-toggle controls, rotation-safe VLC surface, resilient live recovery.\n" + sports
sports_path.write_text(sports, encoding="utf-8")

# ---------------------------------------------------------------------------
# Sports data startup: disk cache of the non-sensitive channel catalog so the
# Sports tab can paint immediately, then refresh silently from the provider.
# ---------------------------------------------------------------------------
iptv = iptv.replace(
    "struct IPTVCategory: Identifiable, Hashable, Decodable {",
    "struct IPTVCategory: Identifiable, Hashable, Codable {",
    1,
)
iptv = iptv.replace(
    "struct IPTVLiveStream: Identifiable, Hashable, Decodable {",
    "struct IPTVLiveStream: Identifiable, Hashable, Codable {",
    1,
)

actor_anchor = "actor IPTVService {\n    static let shared = IPTVService()\n"
if actor_anchor not in iptv:
    raise SystemExit("V35: IPTV actor anchor not found")
cache_support = r'''actor IPTVService {
    static let shared = IPTVService()

    private struct SportsCacheEnvelope: Codable {
        let host: String
        let savedAt: Date
        let categories: [IPTVCategory]
        let streams: [IPTVLiveStream]
    }

    private var sportsCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("xstv-sports-catalog-v1.json", isDirectory: false)
    }

    func cachedSports(credentials: IPTVCredentials) -> ([IPTVCategory], [IPTVLiveStream])? {
        guard let url = sportsCacheURL,
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(SportsCacheEnvelope.self, from: data),
              envelope.host == credentials.normalizedHost,
              Date().timeIntervalSince(envelope.savedAt) < 24 * 60 * 60,
              !envelope.streams.isEmpty else { return nil }
        return (envelope.categories, envelope.streams)
    }

    private func persistSportsCache(
        credentials: IPTVCredentials,
        categories: [IPTVCategory],
        streams: [IPTVLiveStream]
    ) {
        guard let url = sportsCacheURL else { return }
        let envelope = SportsCacheEnvelope(
            host: credentials.normalizedHost,
            savedAt: Date(),
            categories: categories,
            streams: streams
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }
'''
iptv = iptv.replace(actor_anchor, cache_support, 1)

old_return = '''        guard !sportsStreams.isEmpty else { throw IPTVError.noSportsChannels }
        return (sportsCategories, sportsStreams)
'''
new_return = '''        guard !sportsStreams.isEmpty else { throw IPTVError.noSportsChannels }
        persistSportsCache(credentials: credentials, categories: sportsCategories, streams: sportsStreams)
        return (sportsCategories, sportsStreams)
'''
if old_return not in iptv:
    raise SystemExit("V35: loadSports return anchor not found")
iptv = iptv.replace(old_return, new_return, 1)

refresh_anchor = '''    func refresh() async throws {
        guard let credentials else { return }
        isLoading = true
'''
refresh_replacement = '''    func restoreCachedSports() async {
        guard streams.isEmpty, let credentials else { return }
        if let cached = await service.cachedSports(credentials: credentials) {
            categories = cached.0
            streams = cached.1
        }
    }

    func refresh() async throws {
        guard let credentials, !isLoading else { return }
        isLoading = true
'''
if refresh_anchor not in iptv:
    raise SystemExit("V35: store refresh anchor not found")
iptv = iptv.replace(refresh_anchor, refresh_replacement, 1)

if "V35_SPORTS_CACHE" not in iptv:
    iptv = "// V35_SPORTS_CACHE: instant cached sports catalog + background provider refresh.\n" + iptv
iptv_path.write_text(iptv, encoding="utf-8")

# Sports view should restore the cache before doing a network refresh.
sports = sports_path.read_text(encoding="utf-8")
old_task = '''        .task {
            applyConfiguredServer()
            guard store.credentials != nil, store.streams.isEmpty, !store.isLoading else { return }
            try? await store.refresh()
        }
'''
new_task = '''        .task {
            applyConfiguredServer()
            await store.restoreCachedSports()
            guard store.credentials != nil, !store.isLoading else { return }
            try? await store.refresh()
        }
'''
if old_task not in sports:
    raise SystemExit("V35: Sports .task cache anchor not found")
sports = sports.replace(old_task, new_task, 1)
sports_path.write_text(sports, encoding="utf-8")

# ---------------------------------------------------------------------------
# Reproducible media engine: pin the exact VLCKit wrapper revision that passed
# device builds rather than following a moving branch.
# ---------------------------------------------------------------------------
project = project.replace(
'''  VLCKitSPM:
    url: https://github.com/rursache/VLCKitSPM
    branch: master''',
'''  VLCKitSPM:
    url: https://github.com/rursache/VLCKitSPM
    revision: aa0082dd94e4c91450dc3b9cbadb2b385f1e995e''',
1,
)
if "revision: aa0082dd94e4c91450dc3b9cbadb2b385f1e995e" not in project:
    raise SystemExit("V35: could not pin VLCKit revision")
project_path.write_text(project, encoding="utf-8")

print("Applied V35 final app polish: controls, rotation recovery, live stability, sports cache, pinned VLC.")
