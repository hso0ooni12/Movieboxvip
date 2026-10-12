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
            .init(name: "controls", value: "0"),
            .init(name: "speed", value: String(speed))
        ]
        if startAt > 0 { query.append(.init(name: "start", value: String(Int(startAt)))) }
        if let provider, !provider.isEmpty, provider != "auto" {
            query.append(.init(name: "provider", value: provider))
        }
        if let title, !title.isEmpty { query.append(.init(name: "title", value: title)) }
        if let posterURL { query.append(.init(name: "poster", value: posterURL.absoluteString)) }
        components.queryItems = query
        return components.url
    }
}

struct XSTVSubtitleTrack: Identifiable, Hashable {
    let id: Int
    let label: String
    let language: String
    let isSelected: Bool

    var displayName: String {
        if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return label }
        let code = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty,
           let name = Locale.current.localizedString(forLanguageCode: code) {
            return name.capitalized
        }
        return code.isEmpty ? "Subtitle \(id + 1)" : code.uppercased()
    }
}

struct XSTVServerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let quality: String?
    let isSelected: Bool
    let provider: String?
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
    @Published var captionText: String = ""
    @Published var servers: [XSTVServerOption] = []
    @Published var activeServerName: String = "Auto"
    @Published var activeQuality: String = "AUTO"
    @Published var engineError: String?

    weak var webView: WKWebView?
    var onTelemetry: ((Double, Double) -> Void)?

    var remaining: Double {
        guard duration > 0 else { return .infinity }
        return max(duration - currentTime, 0)
    }

    func attach(_ webView: WKWebView) { self.webView = webView }

    func reset() {
        currentTime = 0
        duration = 0
        isPlaying = false
        isReady = false
        captionText = ""
        subtitleTracks = []
        servers = []
        engineError = nil
    }

    func togglePlayback() { send(["action": isPlaying ? "pause" : "play"]) }
    func play() { send(["action": "play"]) }
    func pause() { send(["action": "pause"]) }
    func seek(to seconds: Double) { send(["action": "seek", "time": max(seconds, 0)]) }
    func seekBy(_ seconds: Double) { send(["action": "seekBy", "seconds": seconds]) }
    func setMuted(_ muted: Bool) { send(["action": "mute", "muted": muted]) }
    func setRate(_ rate: Double) { send(["action": "rate", "rate": rate]) }
    func requestPictureInPicture() { send(["action": "pip"]) }
    func requestMetadata() { send(["action": "metadata"]) }
    func setSubtitleDelay(_ seconds: Double) { send(["action": "subtitleDelay", "seconds": seconds]) }

    func selectSubtitle(_ index: Int?) {
        selectedSubtitleIndex = index
        send(["action": "subtitle", "index": index ?? -1])
    }

    func selectServer(_ server: XSTVServerOption) {
        activeServerName = server.name
        if let quality = server.quality, !quality.isEmpty { activeQuality = quality }
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }

    func receive(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }

        switch event {
        case "xs:ready":
            isReady = true
            engineError = nil
        case "xs:error":
            engineError = payload["message"] as? String ?? "Playback engine unavailable."
        case "xs:state", "frameXTV:timeupdate":
            if let value = doubleValue(payload["currentTime"]) { currentTime = value }
            if let value = doubleValue(payload["duration"]) { duration = value }
            if let paused = payload["paused"] as? Bool { isPlaying = !paused }
            if let muted = payload["muted"] as? Bool { isMuted = muted }
            if let value = doubleValue(payload["volume"]) { volume = value }
            if let value = doubleValue(payload["rate"]) { playbackRate = value }
            if currentTime > 0 || duration > 0 {
                isReady = true
                onTelemetry?(currentTime, duration)
            }
        case "xs:tracks":
            guard let list = payload["subtitles"] as? [[String: Any]] else { return }
            subtitleTracks = list.compactMap { item in
                guard let index = intValue(item["index"]) else { return nil }
                let selected = (item["selected"] as? Bool) ?? false
                return XSTVSubtitleTrack(
                    id: index,
                    label: item["label"] as? String ?? "",
                    language: item["language"] as? String ?? "",
                    isSelected: selected
                )
            }
            selectedSubtitleIndex = subtitleTracks.first(where: { $0.isSelected })?.id
        case "xs:caption":
            captionText = payload["text"] as? String ?? ""
        case "xs:servers":
            guard let list = payload["servers"] as? [[String: Any]] else { return }
            let parsed: [XSTVServerOption] = list.compactMap { item in
                let name = (item["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let quality = (item["quality"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let selected = (item["selected"] as? Bool) ?? false
                let provider = item["provider"] as? String
                return XSTVServerOption(
                    id: "\(provider ?? name)-\(quality ?? "")",
                    name: name,
                    quality: quality,
                    isSelected: selected,
                    provider: provider
                )
            }
            if !parsed.isEmpty {
                servers = parsed
                if let selected = parsed.first(where: { $0.isSelected }) {
                    activeServerName = selected.name
                    if let quality = selected.quality, !quality.isEmpty { activeQuality = quality }
                }
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
        if let text = value as? String { return Double(text) }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
}

struct FrameXTVWebView: UIViewRepresentable {
    let playback: FrameXTVPlayback
    let title: String
    let posterURL: URL?
    @ObservedObject var model: XSTVPlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "xsTelemetry")
        contentController.addUserScript(
            WKUserScript(
                source: Self.engineBridgeScript,
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
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
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
        } catch { }
    }

    private func loadPlayer(in webView: WKWebView) {
        guard let embedURL = playback.embedURL(title: title, posterURL: posterURL) else { return }
        let escapedURL = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
          <style>
            html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}
            iframe{position:fixed;inset:0;width:100%;height:100%;border:0;background:#000;pointer-events:none}
          </style>
        </head>
        <body>
          <iframe id="framePlayer" src="\(escapedURL)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
          <script>
            const engine = document.getElementById('framePlayer');
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

    private static let engineBridgeScript = #"""
    (function(){
      if (window.__xsInstalled) return;
      window.__xsInstalled = true;

      let video = null;
      let selectedSubtitle = -1;
      let subtitleDelay = 0;
      let lastCaption = '';
      let lastTrackSignature = '';
      let lastServerSignature = '';

      function bridge(payload) {
        try { window.webkit.messageHandlers.xsTelemetry.postMessage(payload); } catch (_) {}
      }

      function findVideo() {
        try {
          const videos = Array.from(document.querySelectorAll('video'));
          if (!videos.length) return null;
          return videos.sort((a,b)=>(b.clientWidth*b.clientHeight)-(a.clientWidth*a.clientHeight))[0];
        } catch (_) { return null; }
      }

      function hideEngineChrome(v) {
        if (!v || !document.body) return;
        try { v.controls = false; v.setAttribute('playsinline',''); v.setAttribute('webkit-playsinline',''); } catch (_) {}
        const keep = new Set();
        let node = v;
        while (node) { keep.add(node); node = node.parentElement; }

        try {
          Array.from(document.body.querySelectorAll('*')).forEach(el => {
            if (keep.has(el) || el === v || el.contains(v)) return;
            const tag = String(el.tagName || '').toLowerCase();
            if (tag === 'script' || tag === 'style' || tag === 'source' || tag === 'track') return;
            const text = (el.innerText || '').trim();
            const role = (el.getAttribute && el.getAttribute('role')) || '';
            const cls = String(el.className || '').toLowerCase();
            const isChrome = tag === 'button' || role === 'button' || role === 'dialog' ||
              /control|toolbar|progress|seek|volume|subtitle|caption|server|provider|menu|header|tooltip/.test(cls) ||
              /SELECT SERVER|Connected|Available/.test(text);
            if (isChrome) {
              el.style.setProperty('opacity','0','important');
              el.style.setProperty('pointer-events','none','important');
            }
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
          muted:!!v.muted,
          volume:Number(v.volume || 0),
          rate:Number(v.playbackRate || 1)
        });
      }

      function reportTracks() {
        const v = video || findVideo();
        if (!v || !v.textTracks) return;
        const subtitles = [];
        for (let i=0; i<v.textTracks.length; i++) {
          const t = v.textTracks[i];
          subtitles.push({index:i,label:t.label || '',language:t.language || '',selected:i===selectedSubtitle});
        }
        const signature = JSON.stringify(subtitles);
        if (signature !== lastTrackSignature) {
          lastTrackSignature = signature;
          bridge({event:'xs:tracks', subtitles});
        }
      }

      function reportCaption() {
        const v = video || findVideo();
        if (!v || !v.textTracks || selectedSubtitle < 0 || selectedSubtitle >= v.textTracks.length) {
          if (lastCaption !== '') { lastCaption=''; bridge({event:'xs:caption',text:''}); }
          return;
        }
        const t = v.textTracks[selectedSubtitle];
        try { t.mode = 'hidden'; } catch (_) {}
        const wantedTime = Number(v.currentTime || 0) + subtitleDelay;
        let text = '';
        try {
          if (t.cues) {
            for (let i=0; i<t.cues.length; i++) {
              const cue = t.cues[i];
              if (cue.startTime <= wantedTime && cue.endTime >= wantedTime) {
                text = cue.text || '';
                break;
              }
              if (cue.startTime > wantedTime) break;
            }
          }
        } catch (_) {}
        if (text !== lastCaption) {
          lastCaption = text;
          bridge({event:'xs:caption',text});
        }
      }

      function textOf(el) {
        return String((el && (el.innerText || el.textContent)) || '').replace(/\s+/g,' ').trim();
      }

      function scanServers() {
        const options = [];
        const seen = new Set();
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],li,div'));
          nodes.forEach(el => {
            const text = textOf(el);
            if (!text || text.length > 100) return;
            if (!/(Connected|Available|4K|FHD|UHD|1080p|720p|HD)/i.test(text)) return;
            const qualityMatch = text.match(/(4K|UHD|FHD|1080p|720p|HD)/i);
            const quality = qualityMatch ? qualityMatch[1].toUpperCase() : '';
            const cleaned = text
              .replace(/Connected/ig,'')
              .replace(/Available/ig,'')
              .replace(/4K|UHD|FHD|1080p|720p|HD/ig,'')
              .replace(/\s+/g,' ')
              .trim();
            if (!cleaned || cleaned.length > 45 || /^SELECT SERVER$/i.test(cleaned)) return;
            const name = cleaned.split(' • ')[0].trim();
            if (!name || seen.has(name.toLowerCase())) return;
            seen.add(name.toLowerCase());
            options.push({name, quality, selected:/Connected/i.test(text)});
          });
        } catch (_) {}

        if (!options.length) {
          options.push(
            {name:'Auto',quality:'AUTO',selected:true,provider:'auto'},
            {name:'Barbarian',quality:'',selected:false,provider:'barbarian'},
            {name:'Archer',quality:'',selected:false,provider:'archer'},
            {name:'Goblin',quality:'',selected:false,provider:'goblin'}
          );
        }
        const signature = JSON.stringify(options);
        if (signature !== lastServerSignature) {
          lastServerSignature = signature;
          bridge({event:'xs:servers',servers:options});
        }
      }

      function openServerMenuForScan() {
        try {
          const candidates = Array.from(document.querySelectorAll('button,[role="button"]'));
          const target = candidates.find(el => {
            const a = String(el.getAttribute('aria-label') || el.getAttribute('title') || '').toLowerCase();
            const t = textOf(el).toLowerCase();
            return a.includes('server') || a.includes('provider') || t.includes('server') || t.includes('miner');
          });
          if (target) target.click();
        } catch (_) {}
        setTimeout(scanServers, 250);
        setTimeout(scanServers, 700);
      }

      function clickServer(name) {
        const wanted = String(name || '').trim().toLowerCase();
        if (!wanted) return false;
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],li,div'));
          const exact = nodes.find(el => {
            const t = textOf(el).toLowerCase();
            return t === wanted || t.startsWith(wanted + ' ') || t.includes(wanted + ' connected') || t.includes(wanted + ' available');
          });
          if (exact) { exact.click(); return true; }
        } catch (_) {}
        return false;
      }

      function installVideo(v) {
        if (!v || video === v) return;
        video = v;
        try { v.controls = false; } catch (_) {}
        ['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ratechange','ended','canplay'].forEach(name => {
          try { v.addEventListener(name, reportState, {passive:true}); } catch (_) {}
        });
        try { v.addEventListener('loadedmetadata', reportTracks, {passive:true}); } catch (_) {}
        hideEngineChrome(v);
        bridge({event:'xs:ready'});
        reportState();
        reportTracks();
        openServerMenuForScan();
      }

      function command(payload) {
        const v = video || findVideo();
        const action = payload && payload.action;
        try {
          if (action === 'play' && v) v.play();
          else if (action === 'pause' && v) v.pause();
          else if (action === 'seek' && v) v.currentTime = Math.max(0,Number(payload.time || 0));
          else if (action === 'seekBy' && v) v.currentTime = Math.max(0,Number(v.currentTime || 0) + Number(payload.seconds || 0));
          else if (action === 'mute' && v) v.muted = !!payload.muted;
          else if (action === 'rate' && v) v.playbackRate = Number(payload.rate || 1);
          else if (action === 'subtitleDelay') subtitleDelay = Number(payload.seconds || 0);
          else if (action === 'subtitle' && v && v.textTracks) {
            selectedSubtitle = Number(payload.index);
            for (let i=0; i<v.textTracks.length; i++) {
              try { v.textTracks[i].mode = (i === selectedSubtitle ? 'hidden' : 'disabled'); } catch (_) {}
            }
            reportTracks(); reportCaption();
          }
          else if (action === 'pip' && v) {
            if (typeof v.webkitSetPresentationMode === 'function') v.webkitSetPresentationMode('picture-in-picture');
            else if (v.requestPictureInPicture) v.requestPictureInPicture();
          }
          else if (action === 'metadata') { reportTracks(); openServerMenuForScan(); }
          else if (action === 'server') {
            const clicked = clickServer(payload.name);
            if (!clicked && payload.provider) {
              window.postMessage({action:'setProvider',provider:payload.provider}, '*');
            }
            setTimeout(scanServers, 600);
          }
        } catch (_) {}
        reportState();
      }

      window.addEventListener('message', function(event){
        try {
          if (event && event.data && event.data.__xsCommand) command(event.data.__xsCommand);
        } catch (_) {}
      }, true);

      const observer = new MutationObserver(function(){
        const v = findVideo();
        if (v) installVideo(v);
        if (video) hideEngineChrome(video);
      });
      try { observer.observe(document.documentElement || document.body,{subtree:true,childList:true,attributes:false}); } catch (_) {}

      setInterval(function(){
        const v = findVideo();
        if (v) installVideo(v);
        if (video) {
          hideEngineChrome(video);
          reportState();
          reportTracks();
          reportCaption();
        }
      }, 250);

      setTimeout(function(){ if (!findVideo()) bridge({event:'xs:error',message:'Waiting for the playback engine…'}); }, 9000);
    })();
    """#

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let model: XSTVPlayerModel
        init(model: XSTVPlayerModel) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "xsTelemetry",
                  let payload = message.body as? [String: Any] else { return }
            Task { @MainActor in model.receive(payload) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
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

struct XSAirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = true
        view.activeTintColor = .white
        view.tintColor = .white
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

    @StateObject private var playerModel = XSTVPlayerModel()
    @State private var activePlayback: FrameXTVPlayback
    @State private var queuedNextPlayback: FrameXTVPlayback?
    @State private var queuedNextLabel: String?
    @State private var didAdvance = false
    @State private var isResolvingNext = false
    @State private var controlsVisible = true
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var showSubtitles = false
    @State private var showServers = false
    @State private var showSettings = false
    @State private var hideTask: Task<Void, Never>?

    @AppStorage("XSTV.autoNextEpisode") private var autoNextEpisode = true
    @AppStorage("XSTV.subtitleFontScale") private var subtitleFontScale = 1.0
    @AppStorage("XSTV.subtitleBottomPadding") private var subtitleBottomPadding = 74.0
    @AppStorage("XSTV.subtitleDelay") private var subtitleDelay = 0.0
    @AppStorage("XSTV.subtitleBackground") private var subtitleBackground = true

    init(item: MediaItem, playback: FrameXTVPlayback, nextPlayback: FrameXTVPlayback? = nil, nextLabel: String? = nil) {
        self.item = item
        self.playback = playback
        self.nextPlayback = nextPlayback
        self.nextLabel = nextLabel
        var clean = playback
        clean.showEmbeddedControls = false
        _activePlayback = State(initialValue: clean)
        _queuedNextPlayback = State(initialValue: nextPlayback)
        _queuedNextLabel = State(initialValue: nextLabel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                FrameXTVWebView(
                    playback: activePlayback,
                    title: playbackTitle,
                    posterURL: item.imageURL(backdrop: true, width: 1280) ?? item.imageURL(width: 780),
                    model: playerModel
                )
                .id(activePlayback.id)
                .ignoresSafeArea()

                if !playerModel.captionText.isEmpty {
                    captionOverlay(width: proxy.size.width)
                }

                if controlsVisible {
                    controlsOverlay(proxy: proxy)
                        .transition(.opacity)
                }

                if !playerModel.isReady {
                    loadingOverlay
                }

                if shouldShowNextPrompt {
                    VStack {
                        Spacer()
                        HStack { Spacer(); nextEpisodePrompt }
                            .padding(.trailing, 28)
                            .padding(.bottom, 96)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() }
                if controlsVisible { scheduleHide() }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onAppear {
            installTelemetry()
            playerModel.setSubtitleDelay(subtitleDelay)
            scheduleHide()
            Task { await resolveNextEpisodeIfNeeded() }
        }
        .onChange(of: playerModel.currentTime) { _ in handlePlaybackProgress() }
        .onChange(of: subtitleDelay) { newValue in playerModel.setSubtitleDelay(newValue) }
        .onDisappear {
            hideTask?.cancel()
            playerModel.pause()
            playerModel.onTelemetry = nil
        }
        .sheet(isPresented: $showServers) { serverSheet }
        .sheet(isPresented: $showSubtitles) { subtitleSheet }
        .sheet(isPresented: $showSettings) { settingsSheet }
    }

    private var playbackTitle: String {
        if let season = activePlayback.season, let episode = activePlayback.episode {
            return "\(item.title) · S\(season) E\(episode)"
        }
        return item.title
    }

    private func controlsOverlay(proxy: GeometryProxy) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.58), .clear, .black.opacity(0.66)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    controlCircle("xmark", action: { dismiss() })

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.headline.bold()).lineLimit(1)
                        if let season = activePlayback.season, let episode = activePlayback.episode {
                            Text("S\(season) · E\(episode)").font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                    }

                    Spacer()

                    Button { showServers = true; playerModel.requestMetadata() } label: {
                        Text(playerModel.activeQuality.isEmpty ? "AUTO" : playerModel.activeQuality)
                            .font(.caption.bold())
                            .padding(.horizontal, 12).frame(height: 42)
                            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)

                    Button { showSubtitles = true; playerModel.requestMetadata() } label: {
                        Image(systemName: "captions.bubble.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .frame(width: 44, height: 42)
                            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)

                    ZStack {
                        RoundedRectangle(cornerRadius: 13).fill(.black.opacity(0.42))
                        XSAirPlayButton().padding(9)
                    }
                    .frame(width: 44, height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16)))

                    Button { showSettings = true } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 20, weight: .bold))
                            .frame(width: 44, height: 42)
                            .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.top, max(proxy.safeAreaInsets.top, 14))

                Spacer()

                HStack(spacing: 50) {
                    Button { playerModel.seekBy(-10); bumpControls() } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 38, weight: .medium))
                    }
                    Button { playerModel.togglePlayback(); bumpControls() } label: {
                        Image(systemName: playerModel.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44, weight: .bold))
                            .frame(width: 88, height: 88)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.22)))
                    }
                    Button { playerModel.seekBy(10); bumpControls() } label: {
                        Image(systemName: "goforward.10").font(.system(size: 38, weight: .medium))
                    }
                }
                .foregroundStyle(.white)

                Spacer()

                VStack(spacing: 11) {
                    HStack(spacing: 12) {
                        Text(formatTime(isScrubbing ? scrubValue : playerModel.currentTime))
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 54, alignment: .leading)

                        Slider(
                            value: Binding(
                                get: { isScrubbing ? scrubValue : playerModel.currentTime },
                                set: { value in scrubValue = value }
                            ),
                            in: 0...max(playerModel.duration, 1),
                            onEditingChanged: { editing in
                                isScrubbing = editing
                                if editing { scrubValue = playerModel.currentTime }
                                else { playerModel.seek(to: scrubValue); bumpControls() }
                            }
                        )
                        .tint(.white)

                        Text("−" + formatTime(max(playerModel.duration - (isScrubbing ? scrubValue : playerModel.currentTime), 0)))
                            .font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
                            .frame(width: 60, alignment: .trailing)
                    }

                    HStack {
                        Button {
                            playerModel.setMuted(!playerModel.isMuted)
                            bumpControls()
                        } label: {
                            Image(systemName: playerModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 19, weight: .semibold))
                        }

                        Text(playerModel.activeServerName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.64))

                        Spacer()

                        Button { playerModel.requestPictureInPicture(); bumpControls() } label: {
                            Label("PiP", systemImage: "pip.enter").labelStyle(.iconOnly)
                        }
                    }
                    .foregroundStyle(.white)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
            }
        }
    }

    private func captionOverlay(width: CGFloat) -> some View {
        VStack {
            Spacer()
            Text(playerModel.captionText)
                .font(.system(size: max(18, min(width * 0.028, 34)) * subtitleFontScale, weight: .semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, subtitleBackground ? 7 : 0)
                .background(subtitleBackground ? Color.black.opacity(0.68) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: .black.opacity(0.9), radius: 2)
                .padding(.horizontal, width * 0.12)
                .padding(.bottom, subtitleBottomPadding)
        }
        .allowsHitTesting(false)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white).scaleEffect(1.15)
            Text(playerModel.engineError ?? "Loading video…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(22)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20))
    }

    private var serverSheet: some View {
        NavigationStack {
            List {
                if playerModel.servers.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                ForEach(playerModel.servers) { server in
                    Button {
                        playerModel.selectServer(server)
                        showServers = false
                    } label: {
                        HStack(spacing: 13) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name).font(.headline)
                                Text(server.isSelected ? "Connected" : "Available")
                                    .font(.caption).foregroundStyle(server.isSelected ? .green : .secondary)
                            }
                            Spacer()
                            if let quality = server.quality, !quality.isEmpty {
                                Text(quality).font(.caption.bold())
                                    .padding(.horizontal, 9).padding(.vertical, 5)
                                    .background(.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
                                    .foregroundStyle(.orange)
                            }
                            if server.isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Servers & Quality")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .task { playerModel.requestMetadata() }
        }
        .presentationDetents([.medium, .large])
    }

    private var subtitleSheet: some View {
        NavigationStack {
            Form {
                Section("Subtitles") {
                    Button {
                        playerModel.selectSubtitle(nil)
                        showSubtitles = false
                    } label: {
                        HStack { Text("Off"); Spacer(); if playerModel.selectedSubtitleIndex == nil { Image(systemName: "checkmark") } }
                    }
                    ForEach(playerModel.subtitleTracks) { track in
                        Button {
                            playerModel.selectSubtitle(track.id)
                            showSubtitles = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.displayName)
                                    if !track.language.isEmpty && track.displayName.lowercased() != track.language.lowercased() {
                                        Text(track.language.uppercased()).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if playerModel.selectedSubtitleIndex == track.id { Image(systemName: "checkmark") }
                            }
                        }
                    }
                    if playerModel.subtitleTracks.isEmpty {
                        Text("This server has not exposed subtitle tracks yet. Try another server.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Subtitle Appearance") {
                    VStack(alignment: .leading) {
                        Text("Size · \(Int(subtitleFontScale * 100))%")
                        Slider(value: $subtitleFontScale, in: 0.7...1.6, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("Position")
                        Slider(value: $subtitleBottomPadding, in: 38...180, step: 4)
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
            .task { playerModel.requestMetadata() }
        }
        .presentationDetents([.medium, .large])
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Playback Speed") {
                    Picker("Speed", selection: Binding(get: { playerModel.playbackRate }, set: { playerModel.setRate($0) })) {
                        Text("0.5×").tag(0.5)
                        Text("1×").tag(1.0)
                        Text("1.25×").tag(1.25)
                        Text("1.5×").tag(1.5)
                        Text("2×").tag(2.0)
                    }
                    .pickerStyle(.segmented)
                }
                Section("Episodes") { Toggle("Auto Play Next Episode", isOn: $autoNextEpisode) }
                Section("Playback") {
                    Button { playerModel.requestPictureInPicture() } label: { Label("Picture in Picture", systemImage: "pip.enter") }
                }
            }
            .navigationTitle("Player Settings")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
        .presentationDetents([.medium])
    }

    private func controlCircle(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.44), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false } }
            }
        }
    }

    private func bumpControls() {
        if !controlsVisible { withAnimation(.easeInOut(duration: 0.16)) { controlsVisible = true } }
        scheduleHide()
    }

    private var shouldShowNextPrompt: Bool {
        queuedNextPlayback != nil && playerModel.duration > 0 && playerModel.remaining <= 22 && playerModel.remaining > 0
    }

    private var nextEpisodePrompt: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("UP NEXT").font(.caption2.bold()).tracking(1.8).foregroundStyle(.white.opacity(0.58))
            Text(queuedNextLabel ?? "Next Episode").font(.subheadline.bold()).lineLimit(1)
            HStack(spacing: 10) {
                if autoNextEpisode { Text("Playing in \(max(Int(ceil(playerModel.remaining)), 1))s").font(.caption).foregroundStyle(.white.opacity(0.66)) }
                Button("Play Now") { playQueuedEpisode() }
                    .font(.caption.bold()).buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .frame(maxWidth: 330, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
    }

    private func installTelemetry() {
        playerModel.onTelemetry = { current, duration in
            library.updateProgress(item: item, season: activePlayback.season, episode: activePlayback.episode, current: current, duration: duration)
        }
    }

    @MainActor
    private func resolveNextEpisodeIfNeeded() async {
        guard queuedNextPlayback == nil, !isResolvingNext, item.kind != .movie,
              let season = activePlayback.season, let episode = activePlayback.episode else { return }
        isResolvingNext = true
        defer { isResolvingNext = false }

        do {
            let current = try await app.episodes(tmdbID: item.tmdbID, season: season)
            if let index = current.firstIndex(where: { $0.episodeNumber == episode }), current.indices.contains(index + 1) {
                let next = current[index + 1]
                queuedNextPlayback = FrameXTVPlayback(tmdbID: item.tmdbID, season: season, episode: next.episodeNumber)
                queuedNextLabel = "S\(season) · E\(next.episodeNumber)  \(next.name)"
                return
            }
            let seasons = try await app.seasons(for: item)
            guard let nextSeason = seasons.map(\.seasonNumber).filter({ $0 > season }).sorted().first else { return }
            let episodes = try await app.episodes(tmdbID: item.tmdbID, season: nextSeason)
            guard let first = episodes.first else { return }
            queuedNextPlayback = FrameXTVPlayback(tmdbID: item.tmdbID, season: nextSeason, episode: first.episodeNumber)
            queuedNextLabel = "S\(nextSeason) · E\(first.episodeNumber)  \(first.name)"
        } catch { }
    }

    private func handlePlaybackProgress() {
        guard autoNextEpisode, queuedNextPlayback != nil, playerModel.duration > 0,
              playerModel.remaining <= 1.2, !didAdvance else { return }
        playQueuedEpisode()
    }

    private func playQueuedEpisode() {
        guard var next = queuedNextPlayback else { return }
        didAdvance = true
        next.showEmbeddedControls = false
        playerModel.pause()
        playerModel.reset()
        activePlayback = next
        queuedNextPlayback = nil
        queuedNextLabel = nil
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await resolveNextEpisodeIfNeeded()
            await MainActor.run { didAdvance = false }
        }
    }
}
