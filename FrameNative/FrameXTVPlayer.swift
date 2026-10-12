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

    var id: String { "\(tmdbID)-\(season ?? 0)-\(episode ?? 0)-\(Int(startAt))" }

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
    let languageCode: String?
    var id: Int { index }

    var displayName: String {
        let cleaned = SubtitleLanguageResolver.clean(label)
        if let resolved = SubtitleLanguageResolver.displayName(from: languageCode ?? cleaned) { return resolved }
        return cleaned
    }
}

struct PlayerOption: Identifiable, Hashable {
    let value: String
    let label: String
    var id: String { value }
}

struct IntroRange: Equatable {
    let start: Double
    let end: Double
}

enum SubtitleLanguageResolver {
    private static let aliases: [String: String] = [
        "ar": "ar", "ara": "ar", "arabic": "ar", "العربية": "ar", "عربي": "ar",
        "en": "en", "eng": "en", "english": "en", "انجليزي": "en", "إنجليزي": "en",
        "es": "es", "spa": "es", "spanish": "es", "español": "es",
        "fr": "fr", "fre": "fr", "fra": "fr", "french": "fr", "français": "fr",
        "de": "de", "ger": "de", "deu": "de", "german": "de", "deutsch": "de",
        "it": "it", "ita": "it", "italian": "it", "italiano": "it",
        "pt": "pt", "por": "pt", "portuguese": "pt", "português": "pt",
        "tr": "tr", "tur": "tr", "turkish": "tr", "türkçe": "tr",
        "ja": "ja", "jpn": "ja", "japanese": "ja", "日本語": "ja",
        "ko": "ko", "kor": "ko", "korean": "ko", "한국어": "ko",
        "zh": "zh", "chi": "zh", "zho": "zh", "chinese": "zh", "中文": "zh",
        "ru": "ru", "rus": "ru", "russian": "ru",
        "hi": "hi", "hin": "hi", "hindi": "hi", "हिन्दी": "hi",
        "ur": "ur", "urd": "ur", "urdu": "ur",
        "id": "id", "ind": "id", "indonesian": "id",
        "ms": "ms", "msa": "ms", "malay": "ms",
        "th": "th", "tha": "th", "thai": "th",
        "vi": "vi", "vie": "vi", "vietnamese": "vi",
        "nl": "nl", "dut": "nl", "nld": "nl", "dutch": "nl",
        "pl": "pl", "pol": "pl", "polish": "pl",
        "sv": "sv", "swe": "sv", "swedish": "sv",
        "no": "no", "nor": "no", "norwegian": "no",
        "da": "da", "dan": "da", "danish": "da",
        "fi": "fi", "fin": "fi", "finnish": "fi",
        "he": "he", "heb": "he", "hebrew": "he"
    ]

    static func clean(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedCode(from raw: String?) -> String? {
        guard let raw else { return nil }
        let cleaned = clean(raw).lowercased()
        if let direct = aliases[cleaned] { return direct }
        for token in cleaned.split(separator: " ").map(String.init) {
            if let code = aliases[token] { return code }
        }
        if cleaned.count == 2 { return cleaned }
        return nil
    }

    static func displayName(from raw: String?) -> String? {
        guard let code = normalizedCode(from: raw) else { return nil }
        return Locale.current.localizedString(forLanguageCode: code)?.capitalized
            ?? Locale(identifier: "en").localizedString(forLanguageCode: code)?.capitalized
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
    @Published var qualityOptions: [PlayerOption] = []
    @Published var audioOptions: [PlayerOption] = []
    @Published var selectedQuality: String?
    @Published var selectedAudio: String?
    @Published var introRange: IntroRange?
    @Published var playerReady = false
    @Published var lastEvent: String?

    weak var webView: WKWebView?
    var onTelemetry: ((Double, Double) -> Void)?
    private var didApplyPreferredSubtitle = false

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(currentTime / duration, 0), 1)
    }
    var remaining: Double { max(duration - currentTime, 0) }
    var canSkipIntro: Bool {
        guard let introRange else { return false }
        return currentTime >= max(0, introRange.start - 2) && currentTime < introRange.end
    }

    func attach(_ webView: WKWebView) { self.webView = webView }
    func resetForNewPlayback() {
        currentTime = 0; duration = 0; subtitleOptions = []; selectedSubtitleIndex = nil
        qualityOptions = []; audioOptions = []; selectedQuality = nil; selectedAudio = nil
        introRange = nil; playerReady = false; didApplyPreferredSubtitle = false
    }

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
        if provider != "auto" { send(["action": "setProvider", "provider": provider]) }
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

    func setQuality(_ option: PlayerOption) {
        selectedQuality = option.value
        send(["action": "setQuality", "quality": option.value])
    }

    func setAudio(_ option: PlayerOption) {
        selectedAudio = option.value
        send(["action": "setAudio", "audio": option.value])
    }

    func skipIntro() {
        guard let introRange else { return }
        seek(to: introRange.end)
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
                if let value = number(payload["currentTime"]) { currentTime = value }
                if let value = number(payload["duration"]) { duration = value }
                playerReady = true
                onTelemetry?(currentTime, duration)
            }
        }

        let subtitles = extractSubtitleOptions(from: payload)
        if !subtitles.isEmpty {
            subtitleOptions = subtitles
            applyPreferredSubtitleIfPossible()
        }
        let qualities = extractGenericOptions(from: payload, keyHints: ["quality", "qualities", "resolution", "resolutions"])
        if !qualities.isEmpty { qualityOptions = qualities }
        let audios = extractGenericOptions(from: payload, keyHints: ["audio", "audios", "audioTracks", "audio_tracks"])
        if !audios.isEmpty { audioOptions = audios }
        if let range = extractIntroRange(from: payload) { introRange = range }
        if let index = integer(payload["subtitleIndex"] ?? payload["selectedSubtitle"] ?? payload["trackIndex"]) {
            selectedSubtitleIndex = index >= 0 ? index : nil
        }
    }

    private func applyPreferredSubtitleIfPossible() {
        guard !didApplyPreferredSubtitle else { return }
        let preferred = UserDefaults.standard.string(forKey: "FrameNative.preferredSubtitleLanguage") ?? "auto"
        guard preferred != "auto", preferred != "off" else {
            if preferred == "off" { setSubtitle(index: -1) }
            didApplyPreferredSubtitle = true
            return
        }
        if let option = subtitleOptions.first(where: {
            SubtitleLanguageResolver.normalizedCode(from: $0.languageCode ?? $0.label) == preferred
        }) {
            setSubtitle(index: option.index)
            didApplyPreferredSubtitle = true
        }
    }

    private func extractSubtitleOptions(from payload: [String: Any]) -> [SubtitleOption] {
        var found: [SubtitleOption] = []
        func parseArray(_ array: [Any]) {
            for (offset, value) in array.enumerated() {
                if let dict = value as? [String: Any] {
                    let index = integer(dict["index"] ?? dict["trackIndex"] ?? dict["id"]) ?? offset
                    let rawLabel = string(dict["label"] ?? dict["name"] ?? dict["title"] ?? dict["language"] ?? dict["lang"] ?? dict["code"])
                    let rawCode = string(dict["language"] ?? dict["lang"] ?? dict["code"])
                    guard let rawLabel else { continue }
                    let cleaned = SubtitleLanguageResolver.clean(rawLabel)
                    guard !cleaned.isEmpty, !looksLikeGenericNumberedTrack(cleaned) else { continue }
                    found.append(SubtitleOption(index: index, label: cleaned, languageCode: rawCode))
                } else if let text = value as? String {
                    let cleaned = SubtitleLanguageResolver.clean(text)
                    guard !looksLikeGenericNumberedTrack(cleaned) else { continue }
                    found.append(SubtitleOption(index: offset, label: cleaned, languageCode: cleaned))
                }
            }
        }
        func walk(_ value: Any, keyHint: String?) {
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    let lower = key.lowercased()
                    let subtitleKey = lower.contains("subtitle") || lower.contains("caption") || lower.contains("track")
                    if subtitleKey, let array = child as? [Any] { parseArray(array) }
                    else { walk(child, keyHint: subtitleKey ? key : keyHint) }
                }
            } else if let array = value as? [Any], keyHint != nil { parseArray(array) }
        }
        walk(payload, keyHint: nil)
        var seen = Set<Int>()
        return found.filter { seen.insert($0.index).inserted }.sorted { $0.index < $1.index }
    }

    private func extractGenericOptions(from payload: [String: Any], keyHints: [String]) -> [PlayerOption] {
        var found: [PlayerOption] = []
        let hints = keyHints.map { $0.lowercased() }
        func parseArray(_ array: [Any]) {
            for value in array {
                if let dict = value as? [String: Any] {
                    let rawValue = string(dict["value"] ?? dict["id"] ?? dict["key"] ?? dict["quality"] ?? dict["label"] ?? dict["name"])
                    let rawLabel = string(dict["label"] ?? dict["name"] ?? dict["title"] ?? dict["value"]) ?? rawValue
                    if let rawValue, let rawLabel { found.append(PlayerOption(value: rawValue, label: rawLabel)) }
                } else if let text = value as? String, !text.isEmpty {
                    found.append(PlayerOption(value: text, label: text))
                } else if let number = value as? NSNumber {
                    found.append(PlayerOption(value: number.stringValue, label: number.stringValue))
                }
            }
        }
        func walk(_ value: Any) {
            guard let dict = value as? [String: Any] else { return }
            for (key, child) in dict {
                let lower = key.lowercased()
                if hints.contains(where: { lower == $0 || lower.contains($0) }), let array = child as? [Any] { parseArray(array) }
                else if child is [String: Any] { walk(child) }
            }
        }
        walk(payload)
        var seen = Set<String>()
        return found.filter { seen.insert($0.value.lowercased()).inserted }
    }

    private func extractIntroRange(from payload: [String: Any]) -> IntroRange? {
        func scan(_ dict: [String: Any]) -> IntroRange? {
            let start = number(dict["introStart"] ?? dict["intro_start"] ?? dict["start"])
            let end = number(dict["introEnd"] ?? dict["intro_end"] ?? dict["end"])
            if let start, let end, end > start, end - start < 600 { return IntroRange(start: start, end: end) }
            for (key, child) in dict where key.lowercased().contains("intro") || key.lowercased().contains("skip") {
                if let nested = child as? [String: Any], let range = scan(nested) { return range }
            }
            return nil
        }
        return scan(payload)
    }

    private func looksLikeGenericNumberedTrack(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.range(of: #"^(subtitle|caption|track)\s*\d+$"#, options: .regularExpression) != nil { return true }
        return lower.range(of: #"^\d+$"#, options: .regularExpression) != nil
    }
    private func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }
    private func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }
    private func string(_ value: Any?) -> String? {
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
        load(webView)
        return webView
    }
    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func load(_ webView: WKWebView) {
        guard let embedURL = playback.embedURL(title: title, posterURL: posterURL) else { return }
        let escaped = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover, user-scalable=no">
        <style>html,body{margin:0;padding:0;width:100%;height:100%;background:#000;overflow:hidden}iframe{position:fixed;inset:0;width:100%;height:100%;border:0;background:#000}</style>
        </head><body>
        <iframe id="framePlayer" src="\(escaped)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
        <script>
        const player=document.getElementById('framePlayer');
        window.sendToFrameXTV=function(payload){if(player&&player.contentWindow)player.contentWindow.postMessage(payload,'*');};
        window.addEventListener('message',function(event){try{if(event&&event.data&&typeof event.data==='object'){window.webkit.messageHandlers.frameTelemetry.postMessage(event.data);}}catch(_){}},true);
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://framextv.tech"))
    }

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
            guard navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else { decisionHandler(.allow); return }
            if url.scheme == "about" || url.host == "framextv.tech" || url.host == "www.framextv.tech" { decisionHandler(.allow) }
            else { decisionHandler(.cancel) }
        }
    }
}

struct FrameXTVPlayerScreen: View {
    let item: MediaItem
    let playback: FrameXTVPlayback
    let nextPlayback: FrameXTVPlayback?
    let nextLabel: String?

    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var playerModel = FrameXTVPlayerModel()
    @State private var activePlayback: FrameXTVPlayback
    @State private var pendingNextPlayback: FrameXTVPlayback?
    @State private var pendingNextLabel: String?
    @State private var showSubtitleSheet = false
    @State private var showQuickControls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var didAutoAdvance = false
    @AppStorage("FrameNative.autoNextEpisode") private var autoNextEpisode = true

    private let providers = ["auto", "barbarian", "archer", "goblin"]
    private let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    init(item: MediaItem, playback: FrameXTVPlayback, nextPlayback: FrameXTVPlayback? = nil, nextLabel: String? = nil) {
        self.item = item; self.playback = playback; self.nextPlayback = nextPlayback; self.nextLabel = nextLabel
        _activePlayback = State(initialValue: playback)
        _pendingNextPlayback = State(initialValue: nextPlayback)
        _pendingNextLabel = State(initialValue: nextLabel)
    }

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            ZStack {
                Color.black.ignoresSafeArea()
                FrameXTVWebView(
                    playback: resolvedPlayback(activePlayback),
                    title: item.title,
                    posterURL: item.imageURL(backdrop: true, width: 1280) ?? item.imageURL(width: 780),
                    model: playerModel
                )
                .id(activePlayback.id)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.18)) { showQuickControls.toggle() }
                    if showQuickControls { scheduleQuickControlsHide() }
                }

                LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .center)
                    .frame(height: landscape ? 100 : 150)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea().allowsHitTesting(false)

                VStack(spacing: 0) {
                    premiumTopBar(compact: landscape)
                        .padding(.top, max(proxy.safeAreaInsets.top, landscape ? 4 : 8))
                        .padding(.horizontal, landscape ? 18 : 12)
                    Spacer()
                    if playerModel.canSkipIntro {
                        HStack { Spacer(); Button { playerModel.skipIntro() } label: {
                            Label("Skip Intro", systemImage: "forward.end.fill")
                                .font(.subheadline.bold()).padding(.horizontal, 16).frame(height: 44)
                                .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.15)))
                        }.foregroundStyle(.white).padding(.trailing, landscape ? 28 : 16) }.padding(.bottom, 12)
                    }
                    if shouldShowNextEpisode { nextEpisodePrompt.padding(.horizontal, landscape ? 28 : 16).padding(.bottom, 12) }
                    if showQuickControls {
                        quickTransport
                            .padding(.bottom, (landscape ? 72 : 112) + proxy.safeAreaInsets.bottom)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showSubtitleSheet) {
            SubtitlePickerSheet(model: playerModel)
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).preferredColorScheme(.dark)
        }
        .onAppear { applyInitialPreferences(); installTelemetry(); scheduleQuickControlsHide() }
        .onChange(of: playerModel.currentTime) { _ in considerAutoAdvance() }
        .onDisappear { hideTask?.cancel(); playerModel.pause(); playerModel.onTelemetry = nil }
    }

    private func resolvedPlayback(_ source: FrameXTVPlayback) -> FrameXTVPlayback {
        var value = source
        if value.provider == nil, let saved = UserDefaults.standard.string(forKey: "FrameNative.preferredProvider"), !saved.isEmpty { value.provider = saved }
        let savedSpeed = UserDefaults.standard.double(forKey: "FrameNative.preferredSpeed")
        if savedSpeed > 0 { value.speed = savedSpeed }
        value.showEmbeddedControls = true
        return value
    }
    private func applyInitialPreferences() {
        let resolved = resolvedPlayback(activePlayback)
        playerModel.isMuted = resolved.muted; playerModel.selectedProvider = resolved.provider ?? "auto"; playerModel.selectedSpeed = resolved.speed
    }
    private func installTelemetry() {
        playerModel.onTelemetry = { current, duration in
            library.updateProgress(item: item, season: activePlayback.season, episode: activePlayback.episode, current: current, duration: duration)
        }
    }

    private func premiumTopBar(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            PlayerCircleButton(systemImage: "chevron.left") { dismiss() }
            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text(episodeLabel ?? item.kind.title).font(.caption2.weight(.medium)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Button { showSubtitleSheet = true } label: {
                HStack(spacing: 6) { Image(systemName: "captions.bubble.fill"); if !compact { Text(subtitleTopLabel).lineLimit(1) } }
                    .font(.caption.bold()).padding(.horizontal, compact ? 10 : 12).frame(height: 38)
                    .background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.12)))
            }.buttonStyle(.plain).foregroundStyle(.white)

            if !playerModel.qualityOptions.isEmpty {
                Menu { ForEach(playerModel.qualityOptions) { option in Button(option.label) { playerModel.setQuality(option) } } }
                label: { PlayerTextCapsule(text: playerModel.selectedQuality ?? "Quality") }
            }
            if !playerModel.audioOptions.isEmpty {
                Menu { ForEach(playerModel.audioOptions) { option in Button(option.label) { playerModel.setAudio(option) } } }
                label: { PlayerCircleLabel(systemImage: "waveform") }
            }
            Menu {
                Section("Server") {
                    ForEach(providers, id: \.self) { provider in
                        Button { playerModel.setProvider(provider) } label: {
                            let name = provider == "auto" ? "Automatic" : provider.capitalized
                            if playerModel.selectedProvider == provider { Label(name, systemImage: "checkmark") } else { Text(name) }
                        }
                    }
                }
                Section("Speed") {
                    ForEach(speeds, id: \.self) { speed in
                        Button { playerModel.setSpeed(speed) } label: {
                            if playerModel.selectedSpeed == speed { Label(speedText(speed), systemImage: "checkmark") } else { Text(speedText(speed)) }
                        }
                    }
                }
                Section { Button { playerModel.setMuted(!playerModel.isMuted) } label: {
                    Label(playerModel.isMuted ? "Unmute" : "Mute", systemImage: playerModel.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                } }
            } label: { PlayerCircleLabel(systemImage: "ellipsis") }
        }
        .padding(8).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
    }

    private var quickTransport: some View {
        HStack(spacing: 18) {
            QuickControlButton(systemImage: "gobackward.10") { playerModel.seek(by: -10); scheduleQuickControlsHide() }
            QuickControlButton(systemImage: "play.fill", prominent: true) { playerModel.play(); scheduleQuickControlsHide() }
            QuickControlButton(systemImage: "pause.fill", prominent: true) { playerModel.pause(); scheduleQuickControlsHide() }
            QuickControlButton(systemImage: "goforward.10") { playerModel.seek(by: 10); scheduleQuickControlsHide() }
        }
        .padding(.horizontal, 16).padding(.vertical, 11).background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10))).shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private var nextEpisodePrompt: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next").font(.caption.bold()).foregroundStyle(.cyan)
                Text(pendingNextLabel ?? "Next Episode").font(.subheadline.bold()).lineLimit(1)
            }
            Spacer()
            if autoNextEpisode, playerModel.remaining <= 12 {
                Text("\(max(Int(playerModel.remaining.rounded(.up)), 0))s").font(.caption.monospacedDigit().bold()).foregroundStyle(.secondary)
            }
            Button("Play Now") { advanceToNext() }
                .font(.subheadline.bold()).padding(.horizontal, 14).frame(height: 38).background(.white, in: Capsule()).foregroundStyle(.black)
        }
        .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.12))).foregroundStyle(.white)
    }

    private var shouldShowNextEpisode: Bool { pendingNextPlayback != nil && playerModel.duration > 0 && playerModel.remaining <= 35 }
    private func considerAutoAdvance() {
        guard autoNextEpisode, !didAutoAdvance, pendingNextPlayback != nil, playerModel.duration > 0, playerModel.remaining <= 1.5 else { return }
        didAutoAdvance = true; advanceToNext()
    }
    private func advanceToNext() {
        guard let next = pendingNextPlayback else { return }
        playerModel.pause(); playerModel.resetForNewPlayback(); activePlayback = next
        pendingNextPlayback = nil; pendingNextLabel = nil; didAutoAdvance = false
        applyInitialPreferences(); installTelemetry(); showQuickControls = true; scheduleQuickControlsHide()
    }
    private var subtitleTopLabel: String {
        if let index = playerModel.selectedSubtitleIndex, let option = playerModel.subtitleOptions.first(where: { $0.index == index }) { return option.displayName }
        return "Subtitles"
    }
    private var episodeLabel: String? {
        guard let season = activePlayback.season, let episode = activePlayback.episode else { return nil }
        return "S\(season) · E\(episode)"
    }
    private func speedText(_ speed: Double) -> String { speed == 1 ? "1×" : String(format: "%g×", speed) }
    private func scheduleQuickControlsHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(.easeInOut(duration: 0.22)) { showQuickControls = false } }
        }
    }
}

private struct PlayerCircleLabel: View {
    let systemImage: String
    var body: some View {
        Image(systemName: systemImage).font(.subheadline.weight(.semibold)).frame(width: 38, height: 38)
            .background(.black.opacity(0.28), in: Circle()).foregroundStyle(.white)
    }
}
private struct PlayerTextCapsule: View {
    let text: String
    var body: some View {
        Text(text).font(.caption.bold()).lineLimit(1).padding(.horizontal, 10).frame(height: 38)
            .background(.black.opacity(0.28), in: Capsule()).foregroundStyle(.white)
    }
}
private struct PlayerCircleButton: View {
    let systemImage: String; let action: () -> Void
    var body: some View { Button(action: action) { PlayerCircleLabel(systemImage: systemImage) }.buttonStyle(.plain) }
}
private struct QuickControlButton: View {
    let systemImage: String; var prominent = false; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: prominent ? 17 : 20, weight: .bold))
                .frame(width: prominent ? 44 : 40, height: prominent ? 44 : 40)
                .background(prominent ? Color.white : Color.black.opacity(0.28), in: Circle())
                .foregroundStyle(prominent ? .black : .white)
        }.buttonStyle(.plain)
    }
}

private struct SubtitlePickerSheet: View {
    @ObservedObject var model: FrameXTVPlayerModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if model.subtitleOptions.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Use the CC / Subtitles button in the FrameXTV player", systemImage: "captions.bubble.fill").font(.headline)
                            Text("This server has not exposed subtitle language names to the app. Numbered tracks are intentionally hidden so you never have to guess which language you are selecting. The embedded FrameXTV controls remain enabled and show the provider’s own subtitle menu.")
                                .font(.subheadline).foregroundStyle(.secondary).lineSpacing(3)
                        }.padding(.vertical, 6)
                    } header: { Text("Subtitles") }
                } else {
                    Section("Available Languages") {
                        Button { model.setSubtitle(index: -1); dismiss() } label: {
                            subtitleRow(title: "Off", selected: model.selectedSubtitleIndex == nil, systemImage: "captions.bubble")
                        }.buttonStyle(.plain)
                        ForEach(model.subtitleOptions) { option in
                            Button { model.setSubtitle(index: option.index); dismiss() } label: {
                                subtitleRow(title: option.displayName, selected: model.selectedSubtitleIndex == option.index, systemImage: "captions.bubble.fill")
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Subtitles").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
    private func subtitleRow(title: String, selected: Bool, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).frame(width: 24); Text(title).foregroundStyle(.primary); Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.cyan) }
        }.contentShape(Rectangle())
    }
}
