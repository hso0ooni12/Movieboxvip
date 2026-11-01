import AVFoundation
import Combine
import SwiftUI
import UIKit

@MainActor
final class PlayerSession: ObservableObject {
    let player = AVPlayer()
    let descriptor: PlaybackDescriptor
    @Published var isPlaying = false
    @Published var loading = true
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published var error: String?
    @Published var requiresSourceVerification = false
    @Published var sourceID: String?
    @Published var subtitleID: String?
    @Published var caption = ""
    @Published var subtitleError: String?
    @Published var subtitleOffset = 0.0
    @Published var embeddedTracks: [(id: String, label: String)] = []
    @Published var externalSubtitles: [ExternalSubtitle]
    @Published var availableSources: [VideoSource]
    private var captions: [SubtitleCue] = []
    private var mediaGroup: AVMediaSelectionGroup?
    private var mediaOptions: [String: AVMediaSelectionOption] = [:]
    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var periodic: Any?
    private var notifications = Set<AnyCancellable>()
    private var startupTask: Task<Void, Never>?
    private var subtitleTask: Task<Void, Never>?
    private var generation = UUID()
    private var failedSources = Set<String>()
    private var hasStarted = false
    private var initialCaptionSelection = false
    private var pendingResume: Double?
    private var discoveryTask: Task<Void, Never>?
    private var qualityTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var userChoseSubtitle = false
    private var requestedFallback = false
    private var releasedSession = false
    private var fallbackInFlight = false
    private var sessionIDs = Set<String>()

    init(descriptor: PlaybackDescriptor) {
        self.descriptor = descriptor
        externalSubtitles = descriptor.subtitles
        availableSources = descriptor.sources
        requestedFallback = descriptor.usedFallback
        if let id = descriptor.sessionID { sessionIDs.insert(id) }
    }

    func start(preferredLanguage: String) {
        guard !hasStarted else { return }
        hasStarted = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.automaticallyWaitsToMinimizeStalling = true
        periodic = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                let length = self.player.currentItem?.duration.seconds ?? 0
                self.duration = length.isFinite ? length : 0
                self.caption = SubtitleParser.text(at: self.position, offset: self.subtitleOffset, cues: self.captions)
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
                self?.loading = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                if player.timeControlStatus == .playing { self?.startupTask?.cancel() }
            }
        }
        guard let source = descriptor.sources.first else { error = WatchedError.unsupportedStream.localizedDescription; loading = false; return }
        load(source, at: descriptor.resumeAt, preferredLanguage: preferredLanguage)
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            do {
                let tracks = try await WatchedClient.shared.subtitles(title: self.descriptor.title, season: self.descriptor.season, episode: self.descriptor.episode)
                try Task.checkCancellation()
                var seen = Set(self.externalSubtitles.map(\.url))
                let additions = tracks.filter { seen.insert($0.url).inserted }
                self.externalSubtitles += additions.map { ExternalSubtitle(id: "discovery-" + $0.id, label: $0.label, language: $0.language, url: $0.url) }
                if !self.userChoseSubtitle, self.subtitleID == nil, preferredLanguage != "off",
                   let track = self.externalSubtitles.first(where: { $0.language.hasPrefix(preferredLanguage) }) {
                    self.selectSubtitle(track.id, userInitiated: false)
                }
            } catch { }
        }
        if descriptor.sources.count == 1, source.kind == "hls" { discoverQualities(source) }
    }

    func chooseSource(_ source: VideoSource, preferredLanguage: String) {
        guard source.id != sourceID else { return }
        failedSources.remove(source.id)
        load(source, at: position, preferredLanguage: preferredLanguage)
    }

    private func load(_ source: VideoSource, at time: Double, preferredLanguage: String) {
        guard source.url.scheme == "https" else { error = WatchedError.unsupportedStream.localizedDescription; loading = false; return }
        startupTask?.cancel(); notifications.removeAll(); itemObservation = nil
        let identity = UUID(); generation = identity
        sourceID = source.id; error = nil; requiresSourceVerification = false; loading = true; mediaOptions = [:]; embeddedTracks = []
        pendingResume = time
        let item = NativeMediaAsset.item(url: source.url)
        item.preferredForwardBufferDuration = 8
        if let bandwidth = source.bandwidth { item.preferredPeakBitRate = bandwidth }
        if let width = source.width, let height = source.height { item.preferredMaximumResolution = CGSize(width: CGFloat(width), height: CGFloat(height)) }
        player.replaceCurrentItem(with: item)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.generation == identity else { return }
                switch item.status {
                case .readyToPlay:
                    if time > 0 { _ = await self.player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) }
                    guard self.generation == identity else { return }
                    self.pendingResume = nil
                    self.player.play()
                    await self.loadEmbeddedTracks(item, identity: identity, preferredLanguage: preferredLanguage)
                case .failed: self.failCurrentSource(preferredLanguage: preferredLanguage)
                default: break
                }
            }
        }
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard self?.generation == identity else { return }
                self?.failCurrentSource(preferredLanguage: preferredLanguage)
            }.store(in: &notifications)
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard self?.generation == identity else { return }
                self?.isPlaying = false; self?.loading = false
            }.store(in: &notifications)
        startupTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(22)) } catch { return }
            guard let self, self.generation == identity, self.player.timeControlStatus != .playing else { return }
            if self.position < max(1, time + 0.5) { self.failCurrentSource(preferredLanguage: preferredLanguage) }
        }
    }

    private func failCurrentSource(preferredLanguage: String) {
        guard !fallbackInFlight else { return }
        if let url = availableSources.first(where: { $0.id == sourceID })?.url {
            failedSources.formUnion(availableSources.filter { $0.url == url }.map(\.id))
        }
        if let alternative = availableSources.first(where: { !failedSources.contains($0.id) }) {
            load(alternative, at: pendingResume ?? position, preferredLanguage: preferredLanguage)
        } else if !requestedFallback {
            requestedFallback = true; fallbackInFlight = true; player.pause(); loading = true; startupTask?.cancel()
            let identity = generation
            fallbackTask = Task { [weak self] in
                guard let self else { return }
                defer { self.fallbackInFlight = false }
                do {
                    let fallback = try await WatchedClient.shared.playback(title: self.descriptor.title, season: self.descriptor.season,
                                                                                 episode: self.descriptor.episode, resumeAt: self.pendingResume ?? self.position)
                    try Task.checkCancellation()
                    guard self.generation == identity else { return }
                    let sources = fallback.sources.map { VideoSource(id: "fallback-" + $0.id, label: $0.label, url: $0.url, height: $0.height, kind: $0.kind) }
                    guard let first = sources.first else { throw WatchedError.unavailable }
                    self.availableSources += sources
                    if let id = fallback.sessionID { self.sessionIDs.insert(id) }
                    self.load(first, at: fallback.resumeAt, preferredLanguage: preferredLanguage)
                } catch is CancellationError { }
                catch {
                    guard self.generation == identity else { return }
                    self.loading = false; self.error = error.localizedDescription
                    self.requiresSourceVerification = (error as? WatchedError)?.offersSourceVerification ?? false
                }
            }
        } else {
            startupTask?.cancel(); player.pause(); loading = false
            error = "تعذّر تشغيل الفيديو من المصادر المتاحة / Couldn’t play the available sources"
        }
    }

    private func loadEmbeddedTracks(_ item: AVPlayerItem, identity: UUID, preferredLanguage: String) async {
        let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
        guard generation == identity else { return }
        mediaGroup = group
        if let group {
            for (index, option) in group.options.enumerated() {
                let key = "embedded-\(index)"
                mediaOptions[key] = option
                embeddedTracks.append((key, option.displayName))
            }
        }
        if initialCaptionSelection {
            selectSubtitle(subtitleID, userInitiated: false)
        } else {
            initialCaptionSelection = true
            if preferredLanguage == "off" { selectSubtitle(nil, userInitiated: false) }
            else if let external = externalSubtitles.first(where: { $0.language.hasPrefix(preferredLanguage) }) { selectSubtitle(external.id, userInitiated: false) }
            else if let embedded = mediaOptions.first(where: { ($0.value.extendedLanguageTag ?? $0.value.locale?.language.languageCode?.identifier ?? "").hasPrefix(preferredLanguage) }) {
                selectSubtitle(embedded.key, userInitiated: false)
            } else { selectSubtitle(nil, userInitiated: false) }
        }
    }

    func selectSubtitle(_ id: String?, userInitiated: Bool = true) {
        if userInitiated { userChoseSubtitle = true }
        initialCaptionSelection = true
        subtitleTask?.cancel(); subtitleID = id; captions = []; caption = ""; subtitleError = nil
        if let group = mediaGroup { player.currentItem?.select(id.flatMap { mediaOptions[$0] }, in: group) }
        guard let id, let track = externalSubtitles.first(where: { $0.id == id }) else { return }
        subtitleTask = Task { [weak self] in
            do {
                guard track.url.scheme == "https" else { throw WatchedError.malformed }
                let (data, response) = try await URLSession.shared.data(from: track.url)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw WatchedError.malformed }
                let source = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
                guard self?.subtitleID == id else { return }
                let parsed = SubtitleParser.parse(source)
                guard !parsed.isEmpty else { throw WatchedError.malformed }
                self?.captions = parsed
            } catch is CancellationError { }
            catch { if self?.subtitleID == id { self?.subtitleError = "تعذّر تحميل الترجمة / Subtitles unavailable" } }
        }
    }

    func togglePlay() { if isPlaying { player.pause() } else { player.play() } }
    func seek(_ time: Double) {
        guard time.isFinite else { return }
        let target = min(max(0, time), duration > 0 ? duration : max(0, time))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func close() {
        generation = UUID(); startupTask?.cancel(); subtitleTask?.cancel(); notifications.removeAll()
        itemObservation = nil; timeControlObservation = nil
        if let periodic { player.removeTimeObserver(periodic); self.periodic = nil }
        player.pause(); player.replaceCurrentItem(with: nil)
        discoveryTask?.cancel(); qualityTask?.cancel(); fallbackTask?.cancel()
        if !releasedSession {
            releasedSession = true
            for id in sessionIDs { Task { await WatchedClient.shared.releasePlayback(sessionID: id) } }
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func discoverQualities(_ source: VideoSource) {
        qualityTask = Task { [weak self] in
            do {
                var request = URLRequest(url: source.url)
                request.timeoutInterval = 5
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return }
                let variants = HLSMasterParser.renditions(String(decoding: data, as: UTF8.self))
                guard let self, self.availableSources.count == 1 else { return }
                self.availableSources += variants.map { variant in
                    VideoSource(id: source.id + "-\(variant.height)", label: "\(variant.height)p", url: source.url,
                                height: variant.height, kind: "hls", bandwidth: variant.bandwidth, width: variant.width)
                }
            } catch { }
        }
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView(); view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspect; view.playerLayer.player = player
        return view
    }
    func updateUIView(_ uiView: PlayerLayerView, context: Context) { uiView.playerLayer.player = player }
    static func dismantleUIView(_ uiView: PlayerLayerView, coordinator: ()) { uiView.playerLayer.player = nil }
}

@MainActor
struct NativePlayerScreen: View {
    let descriptor: PlaybackDescriptor
    var onSourceVerification: (() -> Void)?
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session: PlayerSession
    @State private var controlsVisible = true
    @State private var captionSettings = false
    @State private var scrubbing: Double?
    init(descriptor: PlaybackDescriptor, onSourceVerification: (() -> Void)? = nil) {
        self.descriptor = descriptor
        self.onSourceVerification = onSourceVerification
        _session = StateObject(wrappedValue: PlayerSession(descriptor: descriptor))
    }
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                VideoSurface(player: session.player).ignoresSafeArea().onTapGesture { withAnimation(.easeOut(duration: 0.18)) { controlsVisible.toggle() } }
                if !session.caption.isEmpty {
                    Text(session.caption).font(.system(size: min(25, max(18, proxy.size.width / 36)), weight: .medium))
                        .multilineTextAlignment(.center).lineSpacing(4).foregroundStyle(.white).shadow(color: .black, radius: 2, y: 1)
                        .padding(.horizontal, 9).padding(.vertical, 5).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                        .frame(maxWidth: proxy.size.width * 0.86)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, controlsVisible ? 110 : 35).allowsHitTesting(false)
                }
                if session.loading { ProgressView().controlSize(.large).tint(.white).allowsHitTesting(false) }
                if let error = session.error {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.circle").font(.largeTitle)
                        Text(error).font(.subheadline).multilineTextAlignment(.center)
                        if session.requiresSourceVerification, onSourceVerification != nil {
                            Button(store.t("التحقق من المصدر", "Verify source")) { onSourceVerification?(); dismiss() }.buttonStyle(.borderedProminent)
                        }
                        Button(store.t("إغلاق", "Close")) { dismiss() }.buttonStyle(.borderedProminent)
                    }.padding(25).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 20)).padding(25)
                }
                if controlsVisible { controls }
            }
        }
        .background(.black).statusBarHidden()
        .environment(\.layoutDirection, .leftToRight)
        .sheet(isPresented: $captionSettings) { subtitleSettings.presentationDetents([.height(360)]) }
        .task { session.start(preferredLanguage: store.subtitleLanguage) }
        .onDisappear {
            store.updateProgress(title: descriptor.title, position: session.position, duration: session.duration, season: descriptor.season, episode: descriptor.episode)
            session.close()
        }
    }
    private var controls: some View {
        VStack {
            HStack(spacing: 16) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }.accessibilityLabel(store.t("إغلاق", "Close"))
                Text(descriptor.title.name).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                Spacer()
                Menu {
                    ForEach(session.availableSources) { source in
                        Button { session.chooseSource(source, preferredLanguage: store.subtitleLanguage) } label: {
                            if source.id == session.sourceID { Label(source.label, systemImage: "checkmark") } else { Text(source.label) }
                        }
                    }
                } label: { Image(systemName: "gearshape").frame(width: 40, height: 44) }.accessibilityLabel(store.t("الجودة", "Quality"))
                Button { captionSettings = true } label: { Image(systemName: "captions.bubble").frame(width: 40, height: 44) }.accessibilityLabel(store.t("الترجمة", "Subtitles"))
            }.padding(.horizontal, 13).padding(.top, 12).background(LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .top, endPoint: .bottom))
            Spacer()
            HStack(spacing: 50) {
                Button { session.seek(session.position - 10) } label: { Image(systemName: "gobackward.10").font(.system(size: 29)).frame(width: 50, height: 60) }
                Button { session.togglePlay() } label: { Image(systemName: session.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 45)).frame(width: 65, height: 65) }
                Button { session.seek(session.position + 10) } label: { Image(systemName: "goforward.10").font(.system(size: 29)).frame(width: 50, height: 60) }
            }.shadow(radius: 6)
            Spacer()
            VStack(spacing: 3) {
                Slider(value: Binding(get: { min(max(0, scrubbing ?? session.position), max(1, session.duration)) }, set: { scrubbing = $0 }), in: 0...max(1, session.duration), onEditingChanged: { editing in
                    if !editing, let value = scrubbing { session.seek(value); scrubbing = nil }
                }).tint(WatchedTheme.red)
                HStack {
                    Text(clock(scrubbing ?? session.position))
                    Spacer()
                    Text(clock(session.duration))
                }.font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
            }.padding(.horizontal, 24).padding(.bottom, 20).background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }.foregroundStyle(.white)
    }
    private var subtitleSettings: some View {
        NavigationStack {
            Form {
                Picker(store.t("الترجمة", "Subtitles"), selection: Binding(get: { session.subtitleID ?? "off" }, set: { session.selectSubtitle($0 == "off" ? nil : $0) })) {
                    Text(store.t("إيقاف", "Off")).tag("off")
                    ForEach(session.embeddedTracks, id: \.id) { Text($0.label).tag($0.id) }
                    ForEach(session.externalSubtitles) { Text($0.label).tag($0.id) }
                }
                if let message = session.subtitleError { Text(message).font(.footnote).foregroundStyle(WatchedTheme.accent) }
                HStack {
                    Button("− 0.5 s") { session.subtitleOffset -= 0.5 }
                    Spacer()
                    Text(String(format: "%+.1f s", session.subtitleOffset)).monospacedDigit()
                    Spacer()
                    Button("+ 0.5 s") { session.subtitleOffset += 0.5 }
                }.buttonStyle(.borderless)
                Button(store.t("إعادة ضبط التوقيت", "Reset timing")) { session.subtitleOffset = 0 }
            }
            .navigationTitle(store.t("الترجمة", "Subtitles")).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(store.t("تم", "Done")) { captionSettings = false } } }
        }.preferredColorScheme(.dark)
    }
    private func clock(_ time: Double) -> String {
        guard time.isFinite else { return "00:00" }
        let seconds = max(0, Int(time))
        if seconds >= 3600 { return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
