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
    @Published var playerReady = false
    @Published var lastEvent: String?

    weak var webView: WKWebView?
    var onTelemetry: ((Double, Double) -> Void)?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }

    var subtitleChoices: [SubtitleOption] {
        if !subtitleOptions.isEmpty { return subtitleOptions }
        return (0..<12).map { SubtitleOption(index: $0, label: "Subtitle \($0 + 1)", language: nil) }
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
        UserDefaults.standard.set(provider, forKey: "FrameNative.preferredProvider")
        guard provider != "auto" else { return }
        send(["action": "setProvider", "provider": provider])
    }

    func setSpeed(_ speed: Double) {
        selectedSpeed = speed
        UserDefaults.standard.set(speed, forKey: "FrameNative.preferredSpeed")
        send(["action": "setSpeed", "speed": speed])
    }

    func setSubtitle(index: Int) {
        selectedSubtitleIndex = index >= 0 ? index : nil
        send(["action": "setSubtitle", "index": index])
    }

    func openEmbeddedSubtitleMenu(completion: @escaping (Bool) -> Void) {
        guard let webView else {
            completion(false)
            return
        }

        let script = #"""
        (() => {
          const visible = el => !!(el && (el.offsetWidth || el.offsetHeight || el.getClientRects().length));
          const text = el => [
            el?.innerText || '',
            el?.textContent || '',
            el?.getAttribute?.('aria-label') || '',
            el?.getAttribute?.('title') || '',
            el?.getAttribute?.('data-testid') || '',
            el?.getAttribute?.('data-tooltip') || ''
          ].join(' ').replace(/\s+/g, ' ').trim();

          const nodes = [...document.querySelectorAll('button,[role="button"],[aria-label],[title]')]
            .filter(visible);

          const exact = nodes.find(el => /^(cc|subtitles?|captions?|closed captions)$/i.test(text(el)));
          const broad = nodes.find(el => /(subtitle|caption|closed caption|\bcc\b)/i.test(text(el)));
          const target = exact || broad;

          if (target) {
            target.click();
            return true;
          }
          return false;
        })();
        """#

        webView.evaluateJavaScript(script) { result, _ in
            Task { @MainActor in
                completion((result as? Bool) == true)
            }
        }
    }

    func discoverSubtitleOptionsFromDOM() {
        guard let webView else { return }

        let script = #"""
        (() => {
          const visible = el => !!(el && (el.offsetWidth || el.offsetHeight || el.getClientRects().length));
          const candidates = [...document.querySelectorAll('[role="menuitem"],[role="option"],button,li')].filter(visible);
          const languageWords = /(arabic|english|spanish|french|german|italian|portuguese|turkish|japanese|korean|hindi|chinese|indonesian|thai|vietnamese|russian|polish|dutch|swedish|norwegian|finnish|danish|hebrew|urdu|bengali|malay|filipino|subtitle|caption|العربية|عربي|إنجليزي|english)/i;
          const rows = [];
          for (const el of candidates) {
            const label = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
            if (!label || label.length > 80 || !languageWords.test(label)) continue;
            const indexAttr = el.getAttribute('data-index') || el.getAttribute('data-track-index') || el.dataset?.index || el.dataset?.trackIndex;
            rows.push({ label, index: indexAttr == null ? null : Number(indexAttr) });
          }
          return rows.slice(0, 40);
        })();
        """#

        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let rows = result as? [[String: Any]], !rows.isEmpty else { return }
            Task { @MainActor in
                guard let self else { return }
                var options: [SubtitleOption] = []
                var seen = Set<String>()
                for (offset, row) in rows.enumerated() {
                    guard let raw = row["label"] as? String else { continue }
                    let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !label.isEmpty, seen.insert(label.lowercased()).inserted else { continue }
                    let index = (row["index"] as? NSNumber)?.intValue ?? offset
                    options.append(SubtitleOption(index: index, label: label, language: nil))
                }
                if !options.isEmpty { self.subtitleOptions = options }
            }
        }
    }

    func markReady() {
        playerReady = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            Task { @MainActor in self?.discoverSubtitleOptionsFromDOM() }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }

        let script = """
        (() => {
          const payload = \(json);
          try { window.postMessage(payload, '*'); } catch (_) {}
          try {
            const frame = document.querySelector('iframe');
            if (frame && frame.contentWindow) frame.contentWindow.postMessage(payload, '*');
          } catch (_) {}
        })();
        """
        webView.evaluateJavaScript(script)
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
        if !tracks.isEmpty { subtitleOptions = tracks }

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

        let bridgeSource = #"""
        window.addEventListener('message', function(event) {
          try {
            if (event && event.data && typeof event.data === 'object') {
              window.webkit.messageHandlers.frameTelemetry.postMessage(event.data);
            }
          } catch (_) {}
        }, true);
        """#
        controller.addUserScript(WKUserScript(source: bridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: false))

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
        var request = URLRequest(url: embedURL)
        request.timeoutInterval = 30
        request.setValue("FrameNative/3.0", forHTTPHeaderField: "User-Agent")
        webView.load(request)
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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in model.markReady() }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "about" || url.scheme == "blob" || url.host == "framextv.tech" || url.host == "www.framextv.tech" {
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
    @State private var showSubtitleSheet = false
    @State private var showQuickControls = true
    @State private var hideTask: Task<Void, Never>?

    private let providers = ["auto", "barbarian", "archer", "goblin"]
    private let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                FrameXTVWebView(
                    playback: resolvedPlayback,
                    title: item.title,
                    posterURL: item.imageURL(backdrop: true, width: 1280) ?? item.imageURL(width: 780),
                    model: playerModel
                )
                .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.66), .clear, .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(height: 165)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    premiumTopBar
                        .padding(.top, max(proxy.safeAreaInsets.top, 8))
                        .padding(.horizontal, 12)

                    Spacer()

                    if showQuickControls {
                        quickTransport
                            .padding(.bottom, 118 + proxy.safeAreaInsets.bottom)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
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
            playerModel.selectedProvider = resolvedPlayback.provider ?? "auto"
            playerModel.selectedSpeed = resolvedPlayback.speed
            playerModel.onTelemetry = { current, duration in
                library.updateProgress(
                    item: item,
                    season: playback.season,
                    episode: playback.episode,
                    current: current,
                    duration: duration
                )
            }
            scheduleQuickControlsHide()
        }
        .onDisappear {
            hideTask?.cancel()
            playerModel.pause()
            playerModel.onTelemetry = nil
        }
    }

    private var resolvedPlayback: FrameXTVPlayback {
        var value = playback
        if value.provider == nil,
           let savedProvider = UserDefaults.standard.string(forKey: "FrameNative.preferredProvider"),
           !savedProvider.isEmpty {
            value.provider = savedProvider
        }
        let savedSpeed = UserDefaults.standard.double(forKey: "FrameNative.preferredSpeed")
        if savedSpeed > 0 { value.speed = savedSpeed }
        value.showEmbeddedControls = true
        return value
    }

    private var premiumTopBar: some View {
        HStack(spacing: 10) {
            PlayerCircleButton(systemImage: "chevron.left") { dismiss() }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                Text(episodeLabel ?? item.kind.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                playerModel.openEmbeddedSubtitleMenu { opened in
                    if opened {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            playerModel.discoverSubtitleOptionsFromDOM()
                        }
                    } else {
                        showSubtitleSheet = true
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "captions.bubble.fill")
                    Text("Subtitles")
                        .lineLimit(1)
                }
                .font(.caption.bold())
                .padding(.horizontal, 11)
                .frame(height: 38)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)

            Menu {
                Section("Server") {
                    ForEach(providers, id: \.self) { provider in
                        Button {
                            playerModel.setProvider(provider)
                        } label: {
                            if playerModel.selectedProvider == provider {
                                Label(provider.capitalized, systemImage: "checkmark")
                            } else {
                                Text(provider.capitalized)
                            }
                        }
                    }
                }

                Section("Playback speed") {
                    ForEach(speeds, id: \.self) { speed in
                        Button {
                            playerModel.setSpeed(speed)
                        } label: {
                            if playerModel.selectedSpeed == speed {
                                Label(speedText(speed), systemImage: "checkmark")
                            } else {
                                Text(speedText(speed))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        playerModel.setMuted(!playerModel.isMuted)
                    } label: {
                        Label(playerModel.isMuted ? "Unmute" : "Mute", systemImage: playerModel.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { showQuickControls.toggle() }
                        if showQuickControls { scheduleQuickControlsHide() }
                    } label: {
                        Label(showQuickControls ? "Hide quick controls" : "Show quick controls", systemImage: "play.circle")
                    }
                }
            } label: {
                PlayerCircleLabel(systemImage: "ellipsis")
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
    }

    private var quickTransport: some View {
        HStack(spacing: 18) {
            QuickControlButton(systemImage: "gobackward.10") {
                playerModel.seek(by: -10)
                scheduleQuickControlsHide()
            }

            QuickControlButton(systemImage: "play.fill", prominent: true) {
                playerModel.play()
                scheduleQuickControlsHide()
            }

            QuickControlButton(systemImage: "pause.fill", prominent: true) {
                playerModel.pause()
                scheduleQuickControlsHide()
            }

            QuickControlButton(systemImage: "goforward.10") {
                playerModel.seek(by: 10)
                scheduleQuickControlsHide()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var episodeLabel: String? {
        guard let season = playback.season, let episode = playback.episode else { return nil }
        return "S\(season) · E\(episode)"
    }

    private func speedText(_ speed: Double) -> String {
        speed == 1 ? "1×" : String(format: "%g×", speed)
    }

    private func scheduleQuickControlsHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.22)) { showQuickControls = false }
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
            .background(.black.opacity(0.28), in: Circle())
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

private struct QuickControlButton: View {
    let systemImage: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: prominent ? 17 : 20, weight: .bold))
                .frame(width: prominent ? 44 : 40, height: prominent ? 44 : 40)
                .background(prominent ? Color.white : Color.black.opacity(0.28), in: Circle())
                .foregroundStyle(prominent ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}

private struct SubtitlePickerSheet: View {
    @ObservedObject var model: FrameXTVPlayerModel
    @Environment(\.dismiss) private var dismiss
    @State private var openingNativeMenu = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        openingNativeMenu = true
                        model.openEmbeddedSubtitleMenu { opened in
                            openingNativeMenu = false
                            if opened {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    model.discoverSubtitleOptionsFromDOM()
                                }
                                dismiss()
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "captions.bubble.fill")
                                .frame(width: 24)
                                .foregroundStyle(.cyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Open FrameXTV subtitle menu")
                                    .font(.body.weight(.semibold))
                                Text("Best option — shows the exact languages available on this server")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if openingNativeMenu { ProgressView() }
                            else { Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Recommended")
                }

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
                    Text(model.subtitleOptions.isEmpty ? "Direct Track Selection" : "Available Subtitles")
                } footer: {
                    if model.subtitleOptions.isEmpty {
                        Text("If language names are not exposed by the active provider, use the recommended FrameXTV subtitle menu above. Direct Track Selection remains available as a fallback.")
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
