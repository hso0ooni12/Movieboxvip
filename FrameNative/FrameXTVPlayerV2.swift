import SwiftUI
import WebKit
import AVFoundation
import AVKit

struct FrameXTVPlayback: Hashable, Codable, Identifiable {
    let tmdbID: Int
    var season: Int? = nil
    var episode: Int? = nil
    var autoplay: Bool = true
    var muted: Bool = false
    var provider: String? = nil
    var startAt: Double = 0
    var speed: Double = 1
    var showEmbeddedControls: Bool = false

    var id: String {
        "\(tmdbID)-\(season ?? 0)-\(episode ?? 0)-\(Int(startAt))"
    }

    func embedURL(title: String? = nil, posterURL: URL? = nil) -> URL? {
        var path = "https://framextv.tech/embed/\(tmdbID)"
        if let season, let episode {
            path += "/\(season)/\(episode)"
        }

        guard var components = URLComponents(string: path) else { return nil }
        var query: [URLQueryItem] = [
            .init(name: "autoplay", value: autoplay ? "1" : "0"),
            .init(name: "muted", value: muted ? "1" : "0"),
            .init(name: "controls", value: showEmbeddedControls ? "1" : "0"),
            .init(name: "speed", value: String(speed))
        ]

        if startAt > 0 {
            query.append(.init(name: "start", value: String(Int(startAt))))
        }
        if let provider, !provider.isEmpty, provider != "auto" {
            query.append(.init(name: "provider", value: provider))
        }
        if let title, !title.isEmpty {
            query.append(.init(name: "title", value: title))
        }
        if let posterURL {
            query.append(.init(name: "poster", value: posterURL.absoluteString))
        }

        components.queryItems = query
        return components.url
    }
}

struct XSTVSubtitleTrack: Identifiable, Hashable {
    let id: Int
    let label: String
    let language: String
    let isSelected: Bool
}

@MainActor
final class XSTVPlayerModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var volume: Double = 1
    @Published var playbackRate: Double = 1
    @Published var isReady = false
    @Published var subtitleTracks: [XSTVSubtitleTrack] = []
    @Published var selectedSubtitleIndex: Int? = nil

    weak var webView: WKWebView?
    var onTelemetry: ((Double, Double) -> Void)?

    var remaining: Double {
        guard duration > 0 else { return .infinity }
        return max(duration - currentTime, 0)
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func reset() {
        currentTime = 0
        duration = 0
        isPlaying = false
        isMuted = false
        volume = 1
        playbackRate = 1
        isReady = false
        subtitleTracks = []
        selectedSubtitleIndex = nil
    }

    func togglePlay() {
        send(["action": isPlaying ? "pause" : "play"])
    }

    func play() { send(["action": "play"]) }
    func pause() { send(["action": "pause"]) }

    func seek(to time: Double) {
        let target = max(0, min(time, duration > 0 ? duration : time))
        currentTime = target
        send(["action": "seek", "time": target, "currentTime": target, "value": target])
    }

    func seekBy(_ seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func toggleMute() {
        send(["action": "mute", "muted": !isMuted])
        isMuted.toggle()
    }

    func setRate(_ rate: Double) {
        playbackRate = rate
        send(["action": "rate", "rate": rate])
    }

    func selectSubtitle(index: Int?) {
        selectedSubtitleIndex = index
        send(["action": "subtitle", "index": index ?? -1])
    }

    func requestPictureInPicture() {
        send(["action": "pip"])
    }

    func setFill(_ fill: Bool) {
        send(["action": "fit", "mode": fill ? "cover" : "contain"])
    }

    func receive(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }

        switch event {
        case "xs:ready":
            isReady = true
            receiveState(payload)
        case "xs:state":
            isReady = true
            receiveState(payload)
        case "xs:tracks":
            receiveTracks(payload)
        case "frameXTV:timeupdate":
            if let value = doubleValue(payload["currentTime"]) { currentTime = value }
            if let value = doubleValue(payload["duration"]) { duration = value }
            isReady = true
            onTelemetry?(currentTime, duration)
        case "frameXTV:play", "play":
            isPlaying = true
            isReady = true
        case "frameXTV:pause", "pause":
            isPlaying = false
            isReady = true
        default:
            break
        }
    }

    private func receiveState(_ payload: [String: Any]) {
        if let value = doubleValue(payload["currentTime"]) { currentTime = value }
        if let value = doubleValue(payload["duration"]) { duration = value }
        if let value = payload["paused"] as? Bool { isPlaying = !value }
        if let value = payload["playing"] as? Bool { isPlaying = value }
        if let value = payload["muted"] as? Bool { isMuted = value }
        if let value = doubleValue(payload["volume"]) { volume = value }
        if let value = doubleValue(payload["rate"]) { playbackRate = value }
        onTelemetry?(currentTime, duration)
    }

    private func receiveTracks(_ payload: [String: Any]) {
        guard let rawTracks = payload["subtitles"] as? [[String: Any]] else { return }
        subtitleTracks = rawTracks.compactMap { raw in
            guard let index = raw["index"] as? Int else { return nil }
            let label = (raw["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let language = (raw["language"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let selected = raw["selected"] as? Bool ?? false
            return XSTVSubtitleTrack(
                id: index,
                label: (label?.isEmpty == false ? label! : (language?.isEmpty == false ? language! : "Subtitle \(index + 1)")),
                language: language ?? "",
                isSelected: selected
            )
        }
        selectedSubtitleIndex = subtitleTracks.first(where: { $0.isSelected })?.id
    }

    private func send(_ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.xsPlayerCommand && window.xsPlayerCommand(\(json));")
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}

struct XSTVPlayerWebView: UIViewRepresentable {
    let playback: FrameXTVPlayback
    let title: String
    let posterURL: URL?
    @ObservedObject var model: XSTVPlayerModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "xsTelemetry")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = false

        configureAudioSession()
        model.attach(webView)
        loadPlayer(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "xsTelemetry")
        uiView.stopLoading()
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            // WebKit playback still works if the audio session is unavailable.
        }
    }

    private func loadPlayer(in webView: WKWebView) {
        guard let embedURL = playback.embedURL(title: title, posterURL: posterURL) else { return }

        let escapedURL = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let pointerEvents = playback.showEmbeddedControls ? "auto" : "none"

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
          <style>
            html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}
            iframe{position:fixed;inset:0;width:100%;height:100%;border:0;background:#000;pointer-events:\(pointerEvents)}
          </style>
        </head>
        <body>
          <iframe id="framePlayer" src="\(escapedURL)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
          <script>
            const player = document.getElementById('framePlayer');
            let hookedVideo = null;
            let lastTrackSignature = '';

            function bridge(payload) {
              try { window.webkit.messageHandlers.xsTelemetry.postMessage(payload); } catch (_) {}
            }

            function frameVideo() {
              try {
                const doc = player.contentDocument || player.contentWindow.document;
                if (!doc) return null;
                return doc.querySelector('video');
              } catch (_) { return null; }
            }

            function reportState() {
              const v = hookedVideo || frameVideo();
              if (!v) return;
              bridge({
                event:'xs:state',
                currentTime:Number(v.currentTime || 0),
                duration:Number(isFinite(v.duration) ? v.duration : 0),
                paused:!!v.paused,
                muted:!!v.muted,
                volume:Number(v.volume || 0),
                rate:Number(v.playbackRate || 1)
              });
            }

            function reportTracks() {
              const v = hookedVideo || frameVideo();
              if (!v || !v.textTracks) return;
              const subtitles = [];
              for (let i=0; i<v.textTracks.length; i++) {
                const t = v.textTracks[i];
                subtitles.push({index:i,label:t.label || '',language:t.language || '',selected:t.mode === 'showing'});
              }
              const signature = JSON.stringify(subtitles);
              if (signature !== lastTrackSignature) {
                lastTrackSignature = signature;
                bridge({event:'xs:tracks', subtitles});
              }
            }

            function hookVideo() {
              const v = frameVideo();
              if (!v) return false;
              if (hookedVideo === v) {
                reportTracks();
                return true;
              }
              hookedVideo = v;
              try { v.controls = false; v.playsInline = true; } catch (_) {}
              ['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ratechange','ended','canplay'].forEach(name => {
                try { v.addEventListener(name, reportState, {passive:true}); } catch (_) {}
              });
              try { v.addEventListener('loadedmetadata', reportTracks, {passive:true}); } catch (_) {}
              bridge({event:'xs:ready'});
              reportState();
              reportTracks();
              return true;
            }

            window.xsPlayerCommand = async function(payload) {
              const v = hookedVideo || frameVideo();
              if (v) {
                try {
                  switch (payload.action) {
                    case 'play': await v.play(); break;
                    case 'pause': v.pause(); break;
                    case 'seek': v.currentTime = Number(payload.time || payload.currentTime || payload.value || 0); break;
                    case 'mute': v.muted = !!payload.muted; break;
                    case 'rate': v.playbackRate = Number(payload.rate || 1); break;
                    case 'subtitle': {
                      if (v.textTracks) {
                        const wanted = Number(payload.index);
                        for (let i=0; i<v.textTracks.length; i++) v.textTracks[i].mode = (i === wanted ? 'showing' : 'disabled');
                        reportTracks();
                      }
                      break;
                    }
                    case 'fit': v.style.objectFit = payload.mode === 'cover' ? 'cover' : 'contain'; v.style.width='100%'; v.style.height='100%'; break;
                    case 'pip':
                      if (typeof v.webkitSetPresentationMode === 'function') v.webkitSetPresentationMode('picture-in-picture');
                      else if (v.requestPictureInPicture) await v.requestPictureInPicture();
                      break;
                  }
                  reportState();
                  return true;
                } catch (_) {}
              }

              try {
                if (player && player.contentWindow) {
                  player.contentWindow.postMessage(payload, '*');
                  if (payload.action === 'seek') {
                    player.contentWindow.postMessage({action:'seek', time:payload.time, currentTime:payload.time, value:payload.time}, '*');
                  }
                  return true;
                }
              } catch (_) {}
              return false;
            };

            window.addEventListener('message', function(event) {
              try {
                if (event && event.data && typeof event.data === 'object') bridge(event.data);
              } catch (_) {}
            }, true);

            player.addEventListener('load', function() {
              setTimeout(hookVideo, 250);
              setTimeout(hookVideo, 800);
              setTimeout(hookVideo, 1600);
            });

            setInterval(function(){ hookVideo(); reportState(); }, 750);
          </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://framextv.tech"))
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let model: XSTVPlayerModel

        init(model: XSTVPlayerModel) {
            self.model = model
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "xsTelemetry",
                  let payload = message.body as? [String: Any] else { return }
            Task { @MainActor in model.receive(payload) }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame == true,
                  let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "about" || url.host == "framextv.tech" || url.host == "www.framextv.tech" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

struct FrameXTVPlayerScreen: View {
    let item: MediaItem
    let playback: FrameXTVPlayback
    let nextPlayback: FrameXTVPlayback?
    let nextLabel: String?

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var playerModel = XSTVPlayerModel()
    @State private var activePlayback: FrameXTVPlayback
    @State private var queuedNextPlayback: FrameXTVPlayback?
    @State private var queuedNextLabel: String?
    @State private var didAdvance = false
    @State private var isResolvingNext = false
    @State private var controlsVisible = true
    @State private var showSubtitles = false
    @State private var showSettings = false
    @State private var fallbackMode = false
    @State private var fillVideo = false
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var fallbackTask: Task<Void, Never>?

    @AppStorage("XSTV.autoNextEpisode") private var autoNextEpisode = true

    init(
        item: MediaItem,
        playback: FrameXTVPlayback,
        nextPlayback: FrameXTVPlayback? = nil,
        nextLabel: String? = nil
    ) {
        self.item = item
        var initial = playback
        initial.showEmbeddedControls = false
        self.playback = initial
        self.nextPlayback = nextPlayback
        self.nextLabel = nextLabel
        _activePlayback = State(initialValue: initial)
        _queuedNextPlayback = State(initialValue: nextPlayback)
        _queuedNextLabel = State(initialValue: nextLabel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                XSTVPlayerWebView(
                    playback: renderedPlayback,
                    title: playbackTitle,
                    posterURL: item.imageURL(backdrop: true, width: 1280) ?? item.imageURL(width: 780),
                    model: playerModel
                )
                .id("\(activePlayback.id)-\(fallbackMode)")
                .ignoresSafeArea()

                if !fallbackMode {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { toggleControls() }

                    if controlsVisible {
                        nativeChrome(proxy: proxy)
                            .transition(.opacity)
                    }
                }

                if !playerModel.isReady && !fallbackMode {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.25)
                        .allowsHitTesting(false)
                }

                if !fallbackMode && shouldShowNextPrompt {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            nextEpisodePrompt
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 92)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSubtitles) { subtitlesSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .onAppear {
            installTelemetry()
            scheduleAutoHide()
            scheduleFallbackCheck()
            Task { await resolveNextEpisodeIfNeeded() }
        }
        .onChange(of: playerModel.currentTime) { _ in handlePlaybackProgress() }
        .onChange(of: playerModel.isReady) { ready in
            if ready {
                fallbackTask?.cancel()
                scheduleAutoHide()
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
            fallbackTask?.cancel()
            playerModel.pause()
            playerModel.onTelemetry = nil
        }
    }

    private var renderedPlayback: FrameXTVPlayback {
        var copy = activePlayback
        copy.showEmbeddedControls = fallbackMode
        return copy
    }

    private var playbackTitle: String {
        if let season = activePlayback.season, let episode = activePlayback.episode {
            return "\(item.title) · S\(season) E\(episode)"
        }
        return item.title
    }

    @ViewBuilder
    private func nativeChrome(proxy: GeometryProxy) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    chromeButton(systemName: "chevron.backward", size: 48) {
                        dismiss()
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.kind == .movie ? "NOW PLAYING" : "YOU’RE WATCHING")
                            .font(.caption2.bold())
                            .tracking(1.4)
                            .foregroundStyle(.white.opacity(0.62))
                        Text(playbackTitle)
                            .font(.headline.bold())
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Circle().fill(.green).frame(width: 8, height: 8)
                        Text("AUTO")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(.black.opacity(0.56), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.12)))

                    AirPlayRoutePicker()
                        .frame(width: 42, height: 42)
                        .background(.black.opacity(0.56), in: Circle())
                }
                .padding(.top, max(proxy.safeAreaInsets.top, 10))
                .padding(.horizontal, 20)

                Spacer()

                HStack(spacing: min(72, proxy.size.width * 0.08)) {
                    chromeButton(systemName: "gobackward.10", size: 62) {
                        playerModel.seekBy(-10)
                        scheduleAutoHide()
                    }

                    Button {
                        playerModel.togglePlay()
                        scheduleAutoHide()
                    } label: {
                        Image(systemName: playerModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .bold))
                            .offset(x: playerModel.isPlaying ? 0 : 2)
                            .frame(width: 92, height: 92)
                            .background(.black.opacity(0.60), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.24), lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    chromeButton(systemName: "goforward.10", size: 62) {
                        playerModel.seekBy(10)
                        scheduleAutoHide()
                    }
                }

                Spacer()

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Text(formatTime(playerModel.currentTime))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 54, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { min(playerModel.currentTime, max(playerModel.duration, 1)) },
                                set: { playerModel.seek(to: $0) }
                            ),
                            in: 0...max(playerModel.duration, 1)
                        )
                        .tint(.red)
                        .disabled(playerModel.duration <= 0)

                        Text("−\(formatTime(max(playerModel.duration - playerModel.currentTime, 0)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(width: 58, alignment: .trailing)
                    }

                    HStack(spacing: 14) {
                        chromeButton(systemName: playerModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", size: 44) {
                            playerModel.toggleMute()
                            scheduleAutoHide()
                        }

                        Spacer()

                        chromeButton(systemName: "captions.bubble.fill", size: 44) {
                            hideControlsTask?.cancel()
                            showSubtitles = true
                        }

                        chromeButton(systemName: "gearshape.fill", size: 44) {
                            hideControlsTask?.cancel()
                            showSettings = true
                        }

                        chromeButton(systemName: "pip.enter", size: 44) {
                            playerModel.requestPictureInPicture()
                            scheduleAutoHide()
                        }

                        chromeButton(systemName: fillVideo ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", size: 44) {
                            fillVideo.toggle()
                            playerModel.setFill(fillVideo)
                            scheduleAutoHide()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 16))
            }
        }
    }

    private func chromeButton(systemName: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: max(18, size * 0.38), weight: .semibold))
                .frame(width: size, height: size)
                .background(.black.opacity(0.58), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14)))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private var subtitlesSheet: some View {
        NavigationStack {
            List {
                Section("Subtitles") {
                    Button {
                        playerModel.selectSubtitle(index: nil)
                        showSubtitles = false
                        scheduleAutoHide()
                    } label: {
                        HStack {
                            Text("Off")
                            Spacer()
                            if playerModel.selectedSubtitleIndex == nil { Image(systemName: "checkmark") }
                        }
                    }

                    ForEach(playerModel.subtitleTracks) { track in
                        Button {
                            playerModel.selectSubtitle(index: track.id)
                            showSubtitles = false
                            scheduleAutoHide()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.label)
                                    if !track.language.isEmpty {
                                        Text(track.language.uppercased())
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if playerModel.selectedSubtitleIndex == track.id { Image(systemName: "checkmark") }
                            }
                        }
                    }

                    if playerModel.subtitleTracks.isEmpty {
                        Text("No HTML subtitle tracks were reported by this stream. The source may burn subtitles into the video or expose them only through its own advanced player.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSubtitles = false; scheduleAutoHide() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var settingsSheet: some View {
        NavigationStack {
            List {
                Section("Playback Speed") {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button {
                            playerModel.setRate(rate)
                        } label: {
                            HStack {
                                Text(rate == 1 ? "Normal" : "\(rate, specifier: "%.2g")×")
                                Spacer()
                                if abs(playerModel.playbackRate - rate) < 0.01 { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }

                Section("Stream") {
                    LabeledContent("Quality", value: "Auto / Adaptive")
                    LabeledContent("Source", value: activePlayback.provider ?? "Auto")
                }

                Section {
                    Button {
                        showSettings = false
                        fallbackMode = true
                        controlsVisible = false
                    } label: {
                        Label("Use Source Player Controls", systemImage: "rectangle.on.rectangle")
                    }
                } footer: {
                    Text("Use this only if a stream exposes a server, audio or quality option that is not available through the native XS TV controls. Native controls are removed first, so two players never overlap.")
                }
            }
            .navigationTitle("Player Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false; scheduleAutoHide() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var shouldShowNextPrompt: Bool {
        queuedNextPlayback != nil && playerModel.isReady && playerModel.duration > 0 && playerModel.remaining <= 22 && playerModel.remaining > 0
    }

    private var nextEpisodePrompt: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("UP NEXT")
                .font(.caption2.bold())
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.58))
            Text(queuedNextLabel ?? "Next Episode")
                .font(.subheadline.bold())
                .lineLimit(1)
            HStack(spacing: 10) {
                if autoNextEpisode {
                    Text("Playing in \(max(Int(ceil(playerModel.remaining)), 1))s")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                }
                Button("Play Now") { playQueuedEpisode() }
                    .font(.caption.bold())
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: 330, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() }
        if controlsVisible { scheduleAutoHide() }
        else { hideControlsTask?.cancel() }
    }

    private func scheduleAutoHide() {
        guard !fallbackMode else { return }
        hideControlsTask?.cancel()
        controlsVisible = true
        hideControlsTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) { controlsVisible = false }
            }
        }
    }

    private func scheduleFallbackCheck() {
        fallbackTask?.cancel()
        fallbackTask = Task {
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard !playerModel.isReady else { return }
                fallbackMode = true
                controlsVisible = false
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func installTelemetry() {
        playerModel.onTelemetry = { current, duration in
            library.updateProgress(
                item: item,
                season: activePlayback.season,
                episode: activePlayback.episode,
                current: current,
                duration: duration
            )
        }
    }

    @MainActor
    private func resolveNextEpisodeIfNeeded() async {
        guard queuedNextPlayback == nil,
              !isResolvingNext,
              item.kind != .movie,
              let season = activePlayback.season,
              let episode = activePlayback.episode else { return }

        isResolvingNext = true
        defer { isResolvingNext = false }

        do {
            let currentSeasonEpisodes = try await app.episodes(tmdbID: item.tmdbID, season: season)
            if let index = currentSeasonEpisodes.firstIndex(where: { $0.episodeNumber == episode }),
               currentSeasonEpisodes.indices.contains(index + 1) {
                let next = currentSeasonEpisodes[index + 1]
                queuedNextPlayback = FrameXTVPlayback(tmdbID: item.tmdbID, season: season, episode: next.episodeNumber)
                queuedNextLabel = "S\(season) · E\(next.episodeNumber)  \(next.name)"
                return
            }

            let seasons = try await app.seasons(for: item)
            guard let nextSeasonNumber = seasons.map(\.seasonNumber).filter({ $0 > season }).sorted().first else { return }
            let nextSeasonEpisodes = try await app.episodes(tmdbID: item.tmdbID, season: nextSeasonNumber)
            guard let first = nextSeasonEpisodes.first else { return }

            queuedNextPlayback = FrameXTVPlayback(tmdbID: item.tmdbID, season: nextSeasonNumber, episode: first.episodeNumber)
            queuedNextLabel = "S\(nextSeasonNumber) · E\(first.episodeNumber)  \(first.name)"
        } catch {
            // Current playback stays active if next-episode metadata is unavailable.
        }
    }

    private func handlePlaybackProgress() {
        guard autoNextEpisode,
              queuedNextPlayback != nil,
              playerModel.isReady,
              playerModel.duration > 0,
              playerModel.remaining <= 1.2,
              !didAdvance else { return }
        playQueuedEpisode()
    }

    private func playQueuedEpisode() {
        guard var next = queuedNextPlayback else { return }
        didAdvance = true
        playerModel.pause()
        playerModel.reset()
        next.showEmbeddedControls = false
        activePlayback = next
        queuedNextPlayback = nil
        queuedNextLabel = nil
        fallbackMode = false
        controlsVisible = true
        scheduleFallbackCheck()
        scheduleAutoHide()

        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await resolveNextEpisodeIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            didAdvance = false
        }
    }
}

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
