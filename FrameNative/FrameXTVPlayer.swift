import SwiftUI
import WebKit

struct FrameXTVPlayback: Hashable, Codable {
    let tmdbID: Int
    var season: Int? = nil
    var episode: Int? = nil
    var autoplay: Bool = true
    var muted: Bool = false
    var provider: String? = nil
    var startAt: Double = 0
    var speed: Double = 1

    func embedURL(title: String? = nil, posterURL: URL? = nil) -> URL? {
        var path = "https://framextv.tech/embed/\(tmdbID)"
        if let season, let episode {
            path += "/\(season)/\(episode)"
        }

        guard var components = URLComponents(string: path) else { return nil }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "autoplay", value: autoplay ? "1" : "0"),
            URLQueryItem(name: "muted", value: muted ? "1" : "0"),
            URLQueryItem(name: "controls", value: "0"),
            URLQueryItem(name: "speed", value: String(speed))
        ]

        if startAt > 0 {
            query.append(URLQueryItem(name: "start", value: String(Int(startAt))))
        }
        if let provider, provider != "auto" {
            query.append(URLQueryItem(name: "provider", value: provider))
        }
        if let title, !title.isEmpty {
            query.append(URLQueryItem(name: "title", value: title))
        }
        if let posterURL {
            query.append(URLQueryItem(name: "poster", value: posterURL.absoluteString))
        }
        components.queryItems = query
        return components.url
    }
}

@MainActor
final class FrameXTVPlayerModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isMuted = false
    @Published var selectedProvider = "auto"
    @Published var selectedSpeed: Double = 1
    @Published var lastEvent: String?

    weak var webView: WKWebView?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func play() { send(["action": "play"]) }
    func pause() { send(["action": "pause"]) }
    func seek(to seconds: Double) { send(["action": "seek", "time": seconds]) }
    func seek(by seconds: Double) { send(["action": "seekBy", "seconds": seconds]) }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        send(["action": muted ? "mute" : "setVolume", muted ? "value" : "volume": muted ? 0 : 1])
    }

    func setProvider(_ provider: String) {
        selectedProvider = provider
        guard provider != "auto" else { return }
        send(["action": "setProvider", "provider": provider])
    }

    func setSpeed(_ speed: Double) {
        selectedSpeed = speed
        send(["action": "setSpeed", "speed": speed])
    }

    func setSubtitle(index: Int) {
        send(["action": "setSubtitle", "index": index])
    }

    private func send(_ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.sendToFrameXTV && window.sendToFrameXTV(\(json));")
    }

    func receive(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }
        lastEvent = event
        if event == "frameXTV:timeupdate" {
            if let value = payload["currentTime"] as? NSNumber { currentTime = value.doubleValue }
            if let value = payload["duration"] as? NSNumber { duration = value.doubleValue }
        }
    }
}

struct FrameXTVWebView: UIViewRepresentable {
    let playback: FrameXTVPlayback
    let title: String
    let posterURL: URL?
    @ObservedObject var model: FrameXTVPlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "frameTelemetry")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.allowsLinkPreview = false
        model.attach(webView)

        guard let embedURL = playback.embedURL(title: title, posterURL: posterURL) else { return webView }
        let escaped = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
          <style>
            html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}
            iframe{position:fixed;inset:0;width:100%;height:100%;border:0;background:#000}
          </style>
        </head>
        <body>
          <iframe id="framePlayer" src="\(escaped)" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>
          <script>
            const player = document.getElementById('framePlayer');
            window.sendToFrameXTV = function(payload) {
              if (player && player.contentWindow) player.contentWindow.postMessage(payload, '*');
            };
            window.addEventListener('message', function(event) {
              try {
                if (event && event.data && typeof event.data === 'object') {
                  window.webkit.messageHandlers.frameTelemetry.postMessage(event.data);
                }
              } catch (_) {}
            });
          </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://framextv.tech"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "frameTelemetry")
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        private let model: FrameXTVPlayerModel

        init(model: FrameXTVPlayerModel) {
            self.model = model
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "frameTelemetry", let payload = message.body as? [String: Any] else { return }
            Task { @MainActor in model.receive(payload) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if url.scheme == "about" || url.host == "framextv.tech" {
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

    @StateObject private var playerModel = FrameXTVPlayerModel()
    @State private var isPlaying = true
    @State private var showControls = true

    private let providers = ["auto", "barbarian", "archer", "goblin"]
    private let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            FrameXTVWebView(playback: playback, title: item.title, posterURL: item.posterURL, model: playerModel)
                .ignoresSafeArea(edges: .bottom)
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }

            if showControls {
                nativeControls
                    .transition(.opacity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            playerModel.isMuted = playback.muted
            playerModel.selectedProvider = playback.provider ?? "auto"
            playerModel.selectedSpeed = playback.speed
        }
        .onDisappear { playerModel.pause() }
    }

    private var nativeControls: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(playback.season.flatMap { s in playback.episode.map { "S\(s) · E\($0)" } } ?? item.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Menu {
                    ForEach(providers, id: \.self) { provider in
                        Button(provider.capitalized) { playerModel.setProvider(provider) }
                    }
                } label: {
                    Label(playerModel.selectedProvider.capitalized, systemImage: "server.rack")
                        .font(.caption.bold())
                }

                Menu {
                    ForEach(speeds, id: \.self) { speed in
                        Button(speed == 1 ? "1×" : "\(speed, specifier: "%g")×") { playerModel.setSpeed(speed) }
                    }
                } label: {
                    Text(playerModel.selectedSpeed == 1 ? "1×" : "\(playerModel.selectedSpeed, specifier: "%g")×")
                        .font(.caption.bold())
                        .frame(minWidth: 34)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)
            .background(.black.opacity(0.72))

            Spacer()

            HStack(spacing: 34) {
                Button { playerModel.seek(by: -10) } label: {
                    Image(systemName: "gobackward.10").font(.system(size: 30, weight: .semibold))
                }

                Button {
                    if isPlaying { playerModel.pause() } else { playerModel.play() }
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 38, weight: .bold))
                        .frame(width: 74, height: 74)
                        .background(.white.opacity(0.16), in: Circle())
                }

                Button { playerModel.seek(by: 10) } label: {
                    Image(systemName: "goforward.10").font(.system(size: 30, weight: .semibold))
                }
            }
            .foregroundStyle(.white)

            Spacer()

            VStack(spacing: 9) {
                ProgressView(value: playerModel.progress)
                    .tint(.white)
                HStack {
                    Text(formatTime(playerModel.currentTime))
                    Spacer()
                    Button {
                        playerModel.setMuted(!playerModel.isMuted)
                    } label: {
                        Image(systemName: playerModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    Text(formatTime(playerModel.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.black.opacity(0.72))
        }
        .foregroundStyle(.white)
    }

    private func formatTime(_ value: Double) -> String {
        guard value.isFinite && value >= 0 else { return "0:00" }
        let seconds = Int(value.rounded(.down))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
