import SwiftUI
import WebKit

struct FrameXTVPlayback: Hashable, Codable, Identifiable {
    let tmdbID: Int
    var season: Int? = nil
    var episode: Int? = nil
    var autoplay: Bool = true
    var muted: Bool = false
    var provider: String? = nil
    var startAt: Double = 0
    var speed: Double = 1
    var showEmbeddedControls: Bool = true

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
            .init(name: "controls", value: "1"),
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

@MainActor
final class XSTVPlayerModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var didReceiveTelemetry = false

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
        didReceiveTelemetry = false
    }

    func pause() {
        send(["action": "pause"])
    }

    func receive(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }

        if event == "frameXTV:timeupdate" {
            if let value = doubleValue(payload["currentTime"]) {
                currentTime = value
            }
            if let value = doubleValue(payload["duration"]) {
                duration = value
            }
            didReceiveTelemetry = true
            onTelemetry?(currentTime, duration)
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        webView.evaluateJavaScript("window.sendToFrameXTV && window.sendToFrameXTV(\(json));")
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
}

struct FrameXTVWebView: UIViewRepresentable {
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
        loadPlayer(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) { }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "xsTelemetry")
        uiView.stopLoading()
    }

    private func loadPlayer(in webView: WKWebView) {
        guard let embedURL = playback.embedURL(title: title, posterURL: posterURL) else { return }

        let escapedURL = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        // XS TV deliberately leaves the official FrameXTV player untouched. That keeps
        // every server, subtitle, quality and audio option exposed by the provider available.
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
          <iframe id="framePlayer" src="\(escapedURL)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
          <script>
            const player = document.getElementById('framePlayer');
            window.sendToFrameXTV = function(payload) {
              try {
                if (player && player.contentWindow) player.contentWindow.postMessage(payload, '*');
              } catch (_) {}
            };
            window.addEventListener('message', function(event) {
              try {
                if (event && event.data && typeof event.data === 'object') {
                  window.webkit.messageHandlers.xsTelemetry.postMessage(event.data);
                }
              } catch (_) {}
            }, true);
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
            Task { @MainActor in
                model.receive(payload)
            }
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
    @AppStorage("XSTV.autoNextEpisode") private var autoNextEpisode = true

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
        _activePlayback = State(initialValue: playback)
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

                VStack {
                    HStack {
                        backButton
                        Spacer()
                    }
                    .padding(.top, max(proxy.safeAreaInsets.top, 8))
                    .padding(.horizontal, proxy.size.width > proxy.size.height ? 18 : 12)

                    Spacer()

                    if shouldShowNextPrompt {
                        HStack {
                            Spacer()
                            nextEpisodePrompt
                        }
                        .padding(.horizontal, proxy.size.width > proxy.size.height ? 26 : 14)
                        .padding(.bottom, proxy.size.width > proxy.size.height ? 72 : 112)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onAppear {
            installTelemetry()
            Task { await resolveNextEpisodeIfNeeded() }
        }
        .onChange(of: playerModel.currentTime) { _ in
            handlePlaybackProgress()
        }
        .onDisappear {
            playerModel.pause()
            playerModel.onTelemetry = nil
        }
    }

    private var playbackTitle: String {
        if let season = activePlayback.season, let episode = activePlayback.episode {
            return "\(item.title) · S\(season) E\(episode)"
        }
        return item.title
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 18, weight: .bold))
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.8), Color.pink.opacity(0.75), Color.orange.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back")
    }

    private var shouldShowNextPrompt: Bool {
        queuedNextPlayback != nil &&
        playerModel.didReceiveTelemetry &&
        playerModel.duration > 0 &&
        playerModel.remaining <= 22 &&
        playerModel.remaining > 0
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

                Button("Play Now") {
                    playQueuedEpisode()
                }
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
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, y: 8)
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
                queuedNextPlayback = FrameXTVPlayback(
                    tmdbID: item.tmdbID,
                    season: season,
                    episode: next.episodeNumber
                )
                queuedNextLabel = "S\(season) · E\(next.episodeNumber)  \(next.name)"
                return
            }

            let seasons = try await app.seasons(for: item)
            guard let nextSeasonNumber = seasons
                .map(\.seasonNumber)
                .filter({ $0 > season })
                .sorted()
                .first else { return }

            let nextSeasonEpisodes = try await app.episodes(tmdbID: item.tmdbID, season: nextSeasonNumber)
            guard let first = nextSeasonEpisodes.first else { return }

            queuedNextPlayback = FrameXTVPlayback(
                tmdbID: item.tmdbID,
                season: nextSeasonNumber,
                episode: first.episodeNumber
            )
            queuedNextLabel = "S\(nextSeasonNumber) · E\(first.episodeNumber)  \(first.name)"
        } catch {
            // Playback remains unaffected if catalog metadata for the next episode is unavailable.
        }
    }

    private func handlePlaybackProgress() {
        guard autoNextEpisode,
              queuedNextPlayback != nil,
              playerModel.didReceiveTelemetry,
              playerModel.duration > 0,
              playerModel.remaining <= 1.2,
              !didAdvance else { return }

        playQueuedEpisode()
    }

    private func playQueuedEpisode() {
        guard let next = queuedNextPlayback else { return }

        didAdvance = true
        playerModel.pause()
        playerModel.reset()
        activePlayback = next
        queuedNextPlayback = nil
        queuedNextLabel = nil

        Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            await resolveNextEpisodeIfNeeded()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            didAdvance = false
        }
    }
}
