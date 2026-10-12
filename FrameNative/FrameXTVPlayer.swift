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
    var showEmbeddedControls: Bool = true

    func embedURL(title: String? = nil, posterURL: URL? = nil) -> URL? {
        var path = "https://framextv.tech/embed/\(tmdbID)"
        if let season, let episode { path += "/\(season)/\(episode)" }
        guard var components = URLComponents(string: path) else { return nil }

        var query: [URLQueryItem] = [
            .init(name: "autoplay", value: autoplay ? "1" : "0"),
            .init(name: "muted", value: muted ? "1" : "0"),
            .init(name: "controls", value: showEmbeddedControls ? "1" : "0"),
            .init(name: "speed", value: String(speed))
        ]

        if startAt > 0 { query.append(.init(name: "start", value: String(Int(startAt)))) }
        if let provider, provider != "auto" { query.append(.init(name: "provider", value: provider)) }
        if let title, !title.isEmpty { query.append(.init(name: "title", value: title)) }
        if let posterURL { query.append(.init(name: "poster", value: posterURL.absoluteString)) }
        components.queryItems = query
        return components.url
    }
}

struct SubtitleOption: Identifiable, Hashable {
    let index: Int
    let label: String
    let language: String?

    var id: Int { index }
    var displayName: String {
        if let language, !language.isEmpty, language.lowercased() != label.lowercased() {
            return "\(label) · \(language.uppercased())"
        }
        return label
    }
}

@MainActor
final class FrameXTVPlayerModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isMuted = false
    @Published var selectedProvider = "auto"
    @Published var selectedSpeed: Double = 1
    @Published var subtitleOptions: [SubtitleOption] = []
    @Published var selectedSubtitleIndex: Int? = nil
    @Published var lastEvent: String?

    weak var webView: WKWebView?
    var onTelemetry: ((Double, Double) -> Void)?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var subtitleChoices: [SubtitleOption] {
        if !subtitleOptions.isEmpty { return subtitleOptions }
        return (0..<10).map { SubtitleOption(index: $0, label: "Subtitle \($0 + 1)", language: nil) }
    }

    func attach(_ webView: WKWebView) { self.webView = webView }
    func play() { send(["action": "play"]) }
    func pause() { send(["action": "pause"]) }
    func seek(to seconds: Double) { send(["action": "seek", "time": seconds]) }
    func seek(by seconds: Double) { send(["action": "seekBy", "seconds": seconds]) }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { send(["action": "mute"]) }
        else { send(["action": "setVolume", "volume": 1.0]) }
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
        selectedSubtitleIndex = index >= 0 ? index : nil
        send(["action": "setSubtitle", "index": index])
    }

    private func send(_ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.sendToFrameXTV && window.sendToFrameXTV(\(json));")
    }

    func receive(_ payload: [String: Any]) {
        if let event = payload["event"] as? String {
            lastEvent = event

            if event == "frameXTV:timeupdate" {
                if let value = payload["currentTime"] as? NSNumber { currentTime = value.doubleValue }
                if let value = payload["duration"] as? NSNumber { duration = value.doubleValue }
                onTelemetry?(currentTime, duration)
            }
        }

        let tracks = extractSubtitleOptions(from: payload)
        if !tracks.isEmpty {
            subtitleOptions = tracks
        }

        if let index = integerValue(payload["subtitleIndex"] ?? payload["selectedSubtitle"] ?? payload["trackIndex"]) {
            selectedSubtitleIndex = index >= 0 ? index : nil
        }
    }

    private func extractSubtitleOptions(from payload: [String: Any]) -> [SubtitleOption] {
        var found: [SubtitleOption] = []

        func parseArray(_ array: [Any]) {
            for (offset, value) in array.enumerated() {
                if let dict = value as? [String: Any] {
                    let index = integerValue(dict["index"] ?? dict["trackIndex"] ?? dict["id"]) ?? offset
                    let label = stringValue(dict["label"] ?? dict["name"] ?? dict["title"] ?? dict["language"] ?? dict["lang"])
                        ?? "Subtitle \(index + 1)"
                    let language = stringValue(dict["language"] ?? dict["lang"] ?? dict["code"])
                    found.append(SubtitleOption(index: index, label: label, language: language))
                } else if let text = value as? String {
                    found.append(SubtitleOption(index: offset, label: text, language: nil))
                }
            }
        }

        func walk(_ value: Any, keyHint: String?) {
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    let lower = key.lowercased()
                    let isSubtitleKey = lower.contains("subtitle") || lower.contains("caption")
                    if isSubtitleKey, let array = child as? [Any] {
                        parseArray(array)
                    } else {
                        walk(child, keyHint: isSubtitleKey ? key : keyHint)
                    }
                }
            } else if let array = value as? [Any], keyHint != nil {
                parseArray(array)
            }
        }

        walk(payload, keyHint: nil)

        var seen = Set<Int>()
        return found
            .filter { seen.insert($0.index).inserted }
            .sorted { $0.index < $1.index }
    }

    private func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
        init(model: FrameXTVPlayerModel) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "frameTelemetry", let payload = message.body as? [String: Any] else { return }
            Task { @MainActor in model.receive(payload) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else {
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

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerModel = FrameXTVPlayerModel()
    @State private var isPlaying = true
    @State private var showControls = true
    @State private var showSubtitleSheet = false
    @State private var hideTask: Task<Void, Never>?

    private let providers = ["auto", "barbarian", "archer", "goblin"]
    private let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FrameXTVWebView(
                playback: playback,
                title: item.title,
                posterURL: item.imageURL(backdrop: true, width: 1280) ?? item.imageURL(width: 780),
                model: playerModel
            )
            .ignoresSafeArea()
            .onTapGesture { revealControls() }

            if showControls {
                LinearGradient(
                    colors: [.black.opacity(0.72), .clear, .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack {
                    topControls
                    Spacer()
                    centerControls
                    Spacer()
                }
                .padding(.bottom, 86)
                .transition(.opacity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(false)
        .sheet(isPresented: $showSubtitleSheet) {
            SubtitlePickerSheet(model: playerModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .onAppear {
            playerModel.isMuted = playback.muted
            playerModel.selectedProvider = playback.provider ?? "auto"
            playerModel.selectedSpeed = playback.speed
            playerModel.onTelemetry = { current, duration in
                library.updateProgress(
                    item: item,
                    season: playback.season,
                    episode: playback.episode,
                    current: current,
                    duration: duration
                )
            }
            scheduleAutoHide()
        }
        .onDisappear {
            hideTask?.cancel()
            playerModel.pause()
            playerModel.onTelemetry = nil
        }
    }

    private var topControls: some View {
        HStack(spacing: 10) {
            PlayerCircleButton(systemImage: "chevron.left") {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(episodeLabel ?? item.kind.title)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
            }

            Spacer(minLength: 10)

            Button {
                showSubtitleSheet = true
                scheduleAutoHide()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "captions.bubble.fill")
                    Text(subtitleButtonTitle)
                        .lineLimit(1)
                }
                .font(.caption.bold())
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Menu {
                ForEach(providers, id: \.self) { provider in
                    Button {
                        playerModel.setProvider(provider)
                        scheduleAutoHide()
                    } label: {
                        if playerModel.selectedProvider == provider {
                            Label(provider.capitalized, systemImage: "checkmark")
                        } else {
                            Text(provider.capitalized)
                        }
                    }
                }
            } label: {
                PlayerCircleLabel(systemImage: "server.rack")
            }

            Menu {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        playerModel.setSpeed(speed)
                        scheduleAutoHide()
                    } label: {
                        if playerModel.selectedSpeed == speed {
                            Label(speedText(speed), systemImage: "checkmark")
                        } else {
                            Text(speedText(speed))
                        }
                    }
                }
            } label: {
                Text(speedText(playerModel.selectedSpeed))
                    .font(.caption.bold())
                    .frame(width: 44, height: 38)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var centerControls: some View {
        HStack(spacing: 32) {
            Button {
                playerModel.seek(by: -10)
                scheduleAutoHide()
            } label: {
                Image(systemName: "gobackward.10")
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.48), in: Circle())
            }

            Button {
                if isPlaying { playerModel.pause() } else { playerModel.play() }
                isPlaying.toggle()
                scheduleAutoHide()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 76, height: 76)
                    .background(.white, in: Circle())
                    .foregroundStyle(.black)
            }

            Button {
                playerModel.seek(by: 10)
                scheduleAutoHide()
            } label: {
                Image(systemName: "goforward.10")
                    .font(.system(size: 27, weight: .semibold))
                    .frame(width: 58, height: 58)
                    .background(.black.opacity(0.48), in: Circle())
            }
        }
        .foregroundStyle(.white)
    }

    private var subtitleButtonTitle: String {
        guard let index = playerModel.selectedSubtitleIndex else { return "CC" }
        return playerModel.subtitleChoices.first(where: { $0.index == index })?.label ?? "CC \(index + 1)"
    }

    private var episodeLabel: String? {
        guard let season = playback.season, let episode = playback.episode else { return nil }
        return "Season \(season) • Episode \(episode)"
    }

    private func speedText(_ speed: Double) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed)
    }

    private func revealControls() {
        withAnimation(.easeInOut(duration: 0.16)) { showControls = true }
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { showControls = false }
            }
        }
    }
}

private struct PlayerCircleLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.subheadline.weight(.semibold))
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: Circle())
            .foregroundStyle(.white)
    }
}

private struct PlayerCircleButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PlayerCircleLabel(systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct SubtitlePickerSheet: View {
    @ObservedObject var model: FrameXTVPlayerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.setSubtitle(index: -1)
                        dismiss()
                    } label: {
                        subtitleRow(title: "Off", selected: model.selectedSubtitleIndex == nil, systemImage: "captions.bubble")
                    }
                    .buttonStyle(.plain)

                    ForEach(model.subtitleChoices) { option in
                        Button {
                            model.setSubtitle(index: option.index)
                            dismiss()
                        } label: {
                            subtitleRow(
                                title: option.displayName,
                                selected: model.selectedSubtitleIndex == option.index,
                                systemImage: "captions.bubble.fill"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(model.subtitleOptions.isEmpty ? "Subtitle Tracks" : "Available Subtitles")
                } footer: {
                    if model.subtitleOptions.isEmpty {
                        Text("Subtitle names are supplied by the active FrameXTV server. The FrameXTV player controls remain enabled below the video for the exact tracks available on that server.")
                    }
                }
            }
            .navigationTitle("Subtitles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func subtitleRow(title: String, selected: Bool, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 24)
            Text(title)
                .foregroundStyle(.primary)
            Spacer()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.cyan)
            }
        }
        .contentShape(Rectangle())
    }
}
