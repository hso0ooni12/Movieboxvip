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
        var queryItems: [URLQueryItem] = [
            .init(name: "autoplay", value: autoplay ? "1" : "0"),
            .init(name: "muted", value: muted ? "1" : "0"),
            .init(name: "controls", value: "0"),
            .init(name: "speed", value: String(speed))
        ]

        if startAt > 0 {
            queryItems.append(.init(name: "start", value: String(Int(startAt))))
        }
        if let provider, !provider.isEmpty, provider != "auto" {
            queryItems.append(.init(name: "provider", value: provider))
        }
        if let title, !title.isEmpty {
            queryItems.append(.init(name: "title", value: title))
        }
        if let posterURL {
            queryItems.append(.init(name: "poster", value: posterURL.absoluteString))
        }

        components.queryItems = queryItems
        return components.url
    }
}

private struct XSSubtitleTrack: Identifiable, Hashable {
    let id: Int
    let label: String
    let language: String

    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if !language.isEmpty,
           let localized = Locale.current.localizedString(forLanguageCode: language) {
            return localized.capitalized
        }
        return language.isEmpty ? "Subtitle \(id + 1)" : language.uppercased()
    }
}

private struct XSServerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let quality: String
    let provider: String?
}

@MainActor
private final class XSPlayerState: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var isReady = false
    @Published var captionText = ""
    @Published var subtitleTracks: [XSSubtitleTrack] = []
    @Published var selectedSubtitle: Int? = nil
    @Published var servers: [XSServerOption] = [
        .init(id: "auto", name: "Auto", quality: "AUTO", provider: "auto"),
        .init(id: "barbarian", name: "Barbarian", quality: "", provider: "barbarian"),
        .init(id: "archer", name: "Archer", quality: "", provider: "archer"),
        .init(id: "goblin", name: "Goblin", quality: "", provider: "goblin")
    ]
    @Published var activeServerName = "Auto"
    @Published var activeQuality = "AUTO"
    @Published var errorMessage: String?

    weak var webView: WKWebView?
    var onProgress: ((Double, Double) -> Void)?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func reset() {
        currentTime = 0
        duration = 0
        isPlaying = false
        isReady = false
        captionText = ""
        errorMessage = nil
    }

    func togglePlayback() {
        send(["action": isPlaying ? "pause" : "play"])
    }

    func pause() {
        send(["action": "pause"])
    }

    func seek(to seconds: Double) {
        send(["action": "seek", "time": max(seconds, 0)])
    }

    func seekBy(_ seconds: Double) {
        send(["action": "seekBy", "seconds": seconds])
    }

    func setMuted(_ muted: Bool) {
        send(["action": "mute", "muted": muted])
    }

    func requestPiP() {
        send(["action": "pip"])
    }

    func setRate(_ rate: Double) {
        send(["action": "rate", "rate": rate])
    }

    func setSubtitle(_ index: Int?) {
        selectedSubtitle = index
        send(["action": "subtitle", "index": index ?? -1])
    }

    func setSubtitleDelay(_ seconds: Double) {
        send(["action": "subtitleDelay", "seconds": seconds])
    }

    func requestMetadata() {
        send(["action": "metadata"])
    }

    func selectServer(_ server: XSServerOption) {
        activeServerName = server.name
        if !server.quality.isEmpty {
            activeQuality = server.quality
        }

        var payload: [String: Any] = [
            "action": "server",
            "name": server.name
        ]
        if let provider = server.provider {
            payload["provider"] = provider
        }
        send(payload)
    }

    func receive(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }

        switch event {
        case "xs:ready":
            isReady = true
            errorMessage = nil

        case "xs:error":
            errorMessage = payload["message"] as? String ?? "Playback unavailable"

        case "xs:state", "frameXTV:timeupdate":
            if let value = doubleValue(payload["currentTime"]) { currentTime = value }
            if let value = doubleValue(payload["duration"]) { duration = value }
            if let paused = payload["paused"] as? Bool { isPlaying = !paused }
            if let muted = payload["muted"] as? Bool { isMuted = muted }
            if currentTime > 0 || duration > 0 {
                isReady = true
                onProgress?(currentTime, duration)
            }

        case "xs:caption":
            captionText = payload["text"] as? String ?? ""

        case "xs:tracks":
            guard let list = payload["subtitles"] as? [[String: Any]] else { return }
            subtitleTracks = list.compactMap { row in
                guard let index = intValue(row["index"]) else { return nil }
                return XSSubtitleTrack(
                    id: index,
                    label: row["label"] as? String ?? "",
                    language: row["language"] as? String ?? ""
                )
            }

        case "xs:servers":
            guard let list = payload["servers"] as? [[String: Any]] else { return }
            let parsed = list.compactMap { row -> XSServerOption? in
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let quality = row["quality"] as? String ?? ""
                let provider = row["provider"] as? String
                return XSServerOption(
                    id: (provider ?? name) + quality,
                    name: name,
                    quality: quality,
                    provider: provider
                )
            }
            if !parsed.isEmpty {
                servers = parsed
            }

        default:
            break
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.xsCommand && window.xsCommand(\(json));")
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
}

private struct XSPlaybackWebView: UIViewRepresentable {
    let playback: FrameXTVPlayback
    let title: String
    let posterURL: URL?
    @ObservedObject var model: XSPlayerState

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "xsTelemetry")
        contentController.addUserScript(
            WKUserScript(
                source: Self.bridgeScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.isUserInteractionEnabled = false

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch { }

        model.attach(webView)
        load(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "xsTelemetry")
    }

    private func load(in webView: WKWebView) {
        guard let embedURL = playback.embedURL(title: title, posterURL: posterURL) else { return }
        let escapedURL = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">
          <style>
            html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}
            iframe{position:fixed;inset:0;width:100%;height:100%;border:0;pointer-events:none}
          </style>
        </head>
        <body>
          <iframe id="engine" src="\(escapedURL)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
          <script>
            const engine = document.getElementById('engine');
            window.xsCommand = function(payload) {
              try { engine.contentWindow.postMessage({__xsCommand:payload}, '*'); } catch (_) {}
              try { engine.contentWindow.postMessage(payload, '*'); } catch (_) {}
            };
          </script>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://framextv.tech"))
    }

    private static let bridgeScript = #"""
    (function(){
      if (window.__xsV5) return;
      window.__xsV5 = true;
      let video = null;
      let subtitleIndex = -1;
      let subtitleDelay = 0;
      let lastCaption = '';

      function bridge(payload) {
        try { window.webkit.messageHandlers.xsTelemetry.postMessage(payload); } catch (_) {}
      }

      function findVideo() {
        try {
          const videos = Array.from(document.querySelectorAll('video'));
          if (!videos.length) return null;
          return videos.sort((a,b) => (b.clientWidth*b.clientHeight) - (a.clientWidth*a.clientHeight))[0];
        } catch (_) { return null; }
      }

      function hideChrome() {
        const v = video || findVideo();
        if (!v) return;
        try { v.controls = false; v.setAttribute('playsinline',''); } catch (_) {}
        try {
          Array.from(document.querySelectorAll('button,[role="button"],[role="dialog"]')).forEach(el => {
            el.style.setProperty('display','none','important');
            el.style.setProperty('pointer-events','none','important');
          });
        } catch (_) {}
      }

      function reportState() {
        const v = video || findVideo();
        if (!v) return;
        bridge({
          event:'xs:state',
          currentTime:Number(v.currentTime || 0),
          duration:Number(isFinite(v.duration) ? v.duration : 0),
          paused:!!v.paused,
          muted:!!v.muted
        });
      }

      function reportTracks() {
        const v = video || findVideo();
        if (!v || !v.textTracks) return;
        const tracks = [];
        for (let i = 0; i < v.textTracks.length; i++) {
          const t = v.textTracks[i];
          tracks.push({index:i,label:t.label || '',language:t.language || ''});
        }
        bridge({event:'xs:tracks', subtitles:tracks});
      }

      function reportCaption() {
        const v = video || findVideo();
        if (!v || !v.textTracks || subtitleIndex < 0 || subtitleIndex >= v.textTracks.length) {
          if (lastCaption !== '') { lastCaption = ''; bridge({event:'xs:caption', text:''}); }
          return;
        }

        const track = v.textTracks[subtitleIndex];
        try { track.mode = 'hidden'; } catch (_) {}
        const wanted = Number(v.currentTime || 0) + subtitleDelay;
        let text = '';
        try {
          const cues = track.cues || [];
          for (let i = 0; i < cues.length; i++) {
            const cue = cues[i];
            if (cue.startTime <= wanted && cue.endTime >= wanted) { text = cue.text || ''; break; }
            if (cue.startTime > wanted) break;
          }
        } catch (_) {}
        if (text !== lastCaption) { lastCaption = text; bridge({event:'xs:caption', text:text}); }
      }

      function scanServers() {
        const result = [];
        const seen = new Set();
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],li,div'));
          nodes.forEach(el => {
            const text = String(el.innerText || el.textContent || '').replace(/\s+/g,' ').trim();
            if (!text || text.length > 90) return;
            if (!/(Connected|Available|4K|FHD|UHD|1080p|720p|HD)/i.test(text)) return;
            const qualityMatch = text.match(/(4K|UHD|FHD|1080p|720p|HD)/i);
            const quality = qualityMatch ? qualityMatch[1].toUpperCase() : '';
            const name = text.replace(/Connected|Available|4K|UHD|FHD|1080p|720p|HD/ig,'').replace(/\s+/g,' ').trim();
            if (!name || seen.has(name.toLowerCase())) return;
            seen.add(name.toLowerCase());
            result.push({name:name,quality:quality});
          });
        } catch (_) {}
        if (result.length) bridge({event:'xs:servers', servers:result});
      }

      function install(v) {
        if (!v || video === v) return;
        video = v;
        try { v.controls = false; } catch (_) {}
        ['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ended','canplay'].forEach(name => {
          try { v.addEventListener(name, reportState, {passive:true}); } catch (_) {}
        });
        bridge({event:'xs:ready'});
        reportState();
        reportTracks();
        scanServers();
        hideChrome();
      }

      function command(payload) {
        const v = video || findVideo();
        const action = payload && payload.action;
        try {
          if (action === 'play' && v) v.play();
          else if (action === 'pause' && v) v.pause();
          else if (action === 'seek' && v) v.currentTime = Math.max(0, Number(payload.time || 0));
          else if (action === 'seekBy' && v) v.currentTime = Math.max(0, Number(v.currentTime || 0) + Number(payload.seconds || 0));
          else if (action === 'mute' && v) v.muted = !!payload.muted;
          else if (action === 'rate' && v) v.playbackRate = Number(payload.rate || 1);
          else if (action === 'pip' && v) {
            if (typeof v.webkitSetPresentationMode === 'function') v.webkitSetPresentationMode('picture-in-picture');
            else if (v.requestPictureInPicture) v.requestPictureInPicture();
          }
          else if (action === 'subtitleDelay') subtitleDelay = Number(payload.seconds || 0);
          else if (action === 'subtitle' && v && v.textTracks) {
            subtitleIndex = Number(payload.index);
            for (let i = 0; i < v.textTracks.length; i++) {
              try { v.textTracks[i].mode = i === subtitleIndex ? 'hidden' : 'disabled'; } catch (_) {}
            }
          }
          else if (action === 'server' && payload.provider) {
            window.postMessage({action:'setProvider',provider:payload.provider}, '*');
          }
          else if (action === 'metadata') {
            reportTracks();
            scanServers();
          }
        } catch (_) {}
        reportState();
      }

      window.addEventListener('message', event => {
        try { if (event.data && event.data.__xsCommand) command(event.data.__xsCommand); } catch (_) {}
      });

      new MutationObserver(() => {
        const v = findVideo();
        if (v) install(v);
        hideChrome();
      }).observe(document.documentElement || document.body, {subtree:true, childList:true});

      setInterval(() => {
        const v = findVideo();
        if (v) install(v);
        hideChrome();
        reportState();
        reportTracks();
        reportCaption();
        scanServers();
      }, 400);

      setTimeout(() => {
        if (!findVideo()) bridge({event:'xs:error', message:'Waiting for playback engine…'});
      }, 9000);
    })();
    """#

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let model: XSPlayerState

        init(model: XSPlayerState) {
            self.model = model
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any] else { return }
            Task { @MainActor in
                model.receive(payload)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(.allow)
        }
    }
}

private struct XSAirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}

struct FrameXTVPlayerScreen: View {
    let item: MediaItem
    let playback: FrameXTVPlayback
    let nextPlayback: FrameXTVPlayback?
    let nextLabel: String?

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var player = XSPlayerState()
    @State private var activePlayback: FrameXTVPlayback
    @State private var queuedPlayback: FrameXTVPlayback?
    @State private var queuedLabel: String?
    @State private var controlsVisible = true
    @State private var showSubtitles = false
    @State private var showServers = false
    @State private var showSettings = false
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hideTask: Task<Void, Never>?
    @State private var resolvingNext = false
    @State private var advancing = false

    @AppStorage("XSTV.autoNextEpisode") private var autoNext = true
    @AppStorage("XSTV.subtitleFontScale") private var subtitleScale = 1.0
    @AppStorage("XSTV.subtitleBottomPadding") private var subtitleBottom = 76.0
    @AppStorage("XSTV.subtitleDelay") private var subtitleDelay = 0.0
    @AppStorage("XSTV.subtitleBackground") private var subtitleBackground = true

    init(
        item: MediaItem,
        playback: FrameXTVPlayback,
        nextPlayback: FrameXTVPlayback? = nil,
        nextLabel: String? = nil
    ) {
        self.item = item
        self.playback = playback
        self.nextPlayback = nextPlayback
        self.nextLabel = nextLabel

        var clean = playback
        clean.showEmbeddedControls = false
        _activePlayback = State(initialValue: clean)
        _queuedPlayback = State(initialValue: nextPlayback)
        _queuedLabel = State(initialValue: nextLabel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                XSPlaybackWebView(
                    playback: activePlayback,
                    title: playbackTitle,
                    posterURL: item.imageURL(backdrop: true, width: 1280) ?? item.imageURL(width: 780),
                    model: player
                )
                .id(activePlayback.id)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        revealControls()
                    }

                if !player.captionText.isEmpty {
                    captionOverlay(width: proxy.size.width)
                }

                if controlsVisible {
                    controlsOverlay(proxy)
                        .transition(.opacity)
                }

                if !player.isReady {
                    loadingOverlay
                }

                if shouldShowNext {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            nextEpisodePrompt
                        }
                        .padding(.trailing, 28)
                        .padding(.bottom, 96)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onAppear {
            installProgressHandler()
            player.setSubtitleDelay(subtitleDelay)
            controlsVisible = true
            scheduleHide()
            Task { await resolveNextEpisode() }
        }
        .onChange(of: player.isPlaying) { isPlaying in
            if isPlaying {
                scheduleHide()
            } else {
                hideTask?.cancel()
                controlsVisible = true
            }
        }
        .onChange(of: player.currentTime) { _ in
            handlePlaybackProgress()
        }
        .onChange(of: subtitleDelay) { newValue in
            player.setSubtitleDelay(newValue)
        }
        .onDisappear {
            hideTask?.cancel()
            player.pause()
            player.onProgress = nil
        }
        .sheet(isPresented: $showServers, onDismiss: { revealControls() }) {
            serverSheet
        }
        .sheet(isPresented: $showSubtitles, onDismiss: { revealControls() }) {
            subtitlesSheet
        }
        .sheet(isPresented: $showSettings, onDismiss: { revealControls() }) {
            settingsSheet
        }
    }

    private var playbackTitle: String {
        if let season = activePlayback.season, let episode = activePlayback.episode {
            return "\(item.title) · S\(season) E\(episode)"
        }
        return item.title
    }

    private func controlsOverlay(_ proxy: GeometryProxy) -> some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.62), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    roundButton(systemName: "xmark") {
                        dismiss()
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.headline.bold())
                            .lineLimit(1)
                        if let season = activePlayback.season, let episode = activePlayback.episode {
                            Text("S\(season) · E\(episode)")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    Spacer()

                    Button {
                        holdControls()
                        player.requestMetadata()
                        showServers = true
                    } label: {
                        Text(player.activeQuality)
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .frame(height: 42)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        holdControls()
                        player.requestMetadata()
                        showSubtitles = true
                    } label: {
                        Image(systemName: "captions.bubble.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 44, height: 42)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)

                    Button {
                        holdControls()
                        showSettings = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 44, height: 42)
                            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.top, max(proxy.safeAreaInsets.top, 14))

                Spacer()

                HStack(spacing: 52) {
                    Button {
                        player.seekBy(-10)
                        revealControls()
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 38, weight: .medium))
                    }

                    Button {
                        player.togglePlayback()
                        revealControls()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44, weight: .bold))
                            .frame(width: 88, height: 88)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.22)))
                    }

                    Button {
                        player.seekBy(10)
                        revealControls()
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 38, weight: .medium))
                    }
                }
                .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 11) {
                    HStack(spacing: 12) {
                        Text(formatTime(isScrubbing ? scrubValue : player.currentTime))
                            .font(.caption.monospacedDigit())
                            .frame(width: 58, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubValue : player.currentTime },
                                set: { scrubValue = $0 }
                            ),
                            in: 0...max(player.duration, 1),
                            onEditingChanged: { editing in
                                isScrubbing = editing
                                if editing {
                                    scrubValue = player.currentTime
                                    holdControls()
                                } else {
                                    player.seek(to: scrubValue)
                                    revealControls()
                                }
                            }
                        )
                        .tint(.white)

                        Text("−" + formatTime(max(player.duration - (isScrubbing ? scrubValue : player.currentTime), 0)))
                            .font(.caption.monospacedDigit())
                            .frame(width: 62, alignment: .trailing)
                    }

                    HStack(spacing: 16) {
                        Button {
                            player.setMuted(!player.isMuted)
                            revealControls()
                        } label: {
                            Image(systemName: player.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        }

                        Text(player.activeServerName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.65))

                        Spacer()

                        XSAirPlayPicker()
                            .frame(width: 35, height: 35)

                        Button {
                            player.requestPiP()
                            revealControls()
                        } label: {
                            Image(systemName: "pip.enter")
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
            }
        }
    }

    private func captionOverlay(width: CGFloat) -> some View {
        VStack {
            Spacer()
            Text(player.captionText)
                .font(.system(size: max(18, min(width * 0.028, 34)) * subtitleScale, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, subtitleBackground ? 7 : 0)
                .background(
                    subtitleBackground ? Color.black.opacity(0.68) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .shadow(color: .black.opacity(0.9), radius: 2)
                .padding(.horizontal, width * 0.12)
                .padding(.bottom, subtitleBottom)
        }
        .allowsHitTesting(false)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.15)
            Text(player.errorMessage ?? "Loading video…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(22)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20))
        .allowsHitTesting(false)
    }

    private var serverSheet: some View {
        NavigationStack {
            List {
                ForEach(player.servers) { server in
                    Button {
                        player.selectServer(server)
                        showServers = false
                    } label: {
                        HStack {
                            Text(server.name)
                                .font(.headline)
                            Spacer()
                            if !server.quality.isEmpty {
                                Text(server.quality)
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Servers & Quality")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .task {
                player.requestMetadata()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var subtitlesSheet: some View {
        NavigationStack {
            Form {
                Section("Subtitles") {
                    Button {
                        player.setSubtitle(nil)
                        showSubtitles = false
                    } label: {
                        HStack {
                            Text("Off")
                            Spacer()
                            if player.selectedSubtitle == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    ForEach(player.subtitleTracks) { track in
                        Button {
                            player.setSubtitle(track.id)
                            showSubtitles = false
                        } label: {
                            HStack {
                                Text(track.displayName)
                                Spacer()
                                if player.selectedSubtitle == track.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                Section("Appearance") {
                    VStack(alignment: .leading) {
                        Text("Size · \(Int(subtitleScale * 100))%")
                        Slider(value: $subtitleScale, in: 0.7...1.6, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("Position")
                        Slider(value: $subtitleBottom, in: 38...180, step: 4)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Timing · %+.1fs", subtitleDelay))
                        Slider(value: $subtitleDelay, in: -5...5, step: 0.25)
                    }
                    Toggle("Background", isOn: $subtitleBackground)
                }
            }
            .navigationTitle("Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .task {
                player.requestMetadata()
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Playback Speed") {
                    Button("0.5×") { player.setRate(0.5) }
                    Button("1×") { player.setRate(1.0) }
                    Button("1.25×") { player.setRate(1.25) }
                    Button("1.5×") { player.setRate(1.5) }
                    Button("2×") { player.setRate(2.0) }
                }

                Section("Episodes") {
                    Toggle("Auto Play Next Episode", isOn: $autoNext)
                }
            }
            .navigationTitle("Player Settings")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium])
    }

    private func roundButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func holdControls() {
        hideTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeInOut(duration: 0.15)) {
                controlsVisible = true
            }
        }
    }

    private func revealControls() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) {
            controlsVisible = true
        }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible,
              player.isPlaying,
              !showSubtitles,
              !showServers,
              !showSettings,
              !isScrubbing else { return }

        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    if player.isPlaying,
                       !showSubtitles,
                       !showServers,
                       !showSettings,
                       !isScrubbing {
                        withAnimation(.easeOut(duration: 0.2)) {
                            controlsVisible = false
                        }
                    }
                }
            }
        }
    }

    private var shouldShowNext: Bool {
        queuedPlayback != nil &&
        player.duration > 0 &&
        player.duration - player.currentTime <= 22 &&
        player.duration - player.currentTime > 0
    }

    private var nextEpisodePrompt: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("UP NEXT")
                .font(.caption2.bold())
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.58))
            Text(queuedLabel ?? "Next Episode")
                .font(.subheadline.bold())
            HStack {
                if autoNext {
                    Text("Playing soon")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.66))
                }
                Button("Play Now") {
                    playNextEpisode()
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
    }

    private func installProgressHandler() {
        player.onProgress = { current, duration in
            library.updateProgress(
                item: item,
                season: activePlayback.season,
                episode: activePlayback.episode,
                current: current,
                duration: duration
            )
        }
    }

    private func handlePlaybackProgress() {
        guard autoNext,
              queuedPlayback != nil,
              player.duration > 0,
              player.duration - player.currentTime <= 1.2,
              !advancing else { return }
        playNextEpisode()
    }

    @MainActor
    private func resolveNextEpisode() async {
        guard queuedPlayback == nil,
              !resolvingNext,
              item.kind != .movie,
              let season = activePlayback.season,
              let episode = activePlayback.episode else { return }

        resolvingNext = true
        defer { resolvingNext = false }

        do {
            let episodes = try await app.episodes(tmdbID: item.tmdbID, season: season)
            if let index = episodes.firstIndex(where: { $0.episodeNumber == episode }),
               episodes.indices.contains(index + 1) {
                let next = episodes[index + 1]
                queuedPlayback = FrameXTVPlayback(
                    tmdbID: item.tmdbID,
                    season: season,
                    episode: next.episodeNumber
                )
                queuedLabel = "S\(season) · E\(next.episodeNumber)  \(next.name)"
                return
            }

            let seasons = try await app.seasons(for: item)
            guard let nextSeason = seasons
                .map(\.seasonNumber)
                .filter({ $0 > season })
                .sorted()
                .first else { return }

            let nextSeasonEpisodes = try await app.episodes(tmdbID: item.tmdbID, season: nextSeason)
            guard let first = nextSeasonEpisodes.first else { return }

            queuedPlayback = FrameXTVPlayback(
                tmdbID: item.tmdbID,
                season: nextSeason,
                episode: first.episodeNumber
            )
            queuedLabel = "S\(nextSeason) · E\(first.episodeNumber)  \(first.name)"
        } catch { }
    }

    private func playNextEpisode() {
        guard var next = queuedPlayback else { return }
        advancing = true
        next.showEmbeddedControls = false
        player.pause()
        player.reset()
        activePlayback = next
        queuedPlayback = nil
        queuedLabel = nil
        controlsVisible = true

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await resolveNextEpisode()
            await MainActor.run {
                advancing = false
                revealControls()
            }
        }
    }
}
