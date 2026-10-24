import SwiftUI
import WebKit
import AVFoundation
import UniformTypeIdentifiers

// The catalog is 100% SwiftUI. Some streaming providers only publish an
// interactive embed, not an authorized, stable HLS/MP4 URL. Those titles use a
// confined in-app WebKit playback surface; direct streams still use VLC.
struct EmbeddedSelection: Identifiable {
    let id = UUID()
    let title: String
    let mediaID: String
    let kind: MediaKind
    let season: Int
    let episode: Int

    var servers: [EmbeddedServer] {
        let rawID = mediaID.replacingOccurrences(of: "tmdb:", with: "")
        let safeID = rawID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawID
        let path = kind == .movie
            ? "movie/\(safeID)"
            : "tv/\(safeID)/\(max(1, season))/\(max(1, episode))"
        let vidSrc = "https://embed.vidsrc.pk/\(path)"
        let vidLink = "https://vidlink.pro/\(path)"

        let auto = EmbeddedServer(id: "auto", title: "تلقائي", subtitle: "VidSrc · اختيار ذكي", url: URL(string: vidSrc)!)
        let mirror = EmbeddedServer(id: "mirror", title: "سيرفر بديل", subtitle: "VidSrc · NetMirror", url: URL(string: vidSrc + "?p=netmirror")!)
        let primary = EmbeddedServer(id: "primary", title: "السيرفر الأساسي", subtitle: "VidSrc · Primary", url: URL(string: vidSrc + "?p=primary")!)
        let link = EmbeddedServer(id: "vidlink", title: "VidLink", subtitle: "مشغّل احتياطي", url: URL(string: vidLink)!)
        // NetMirror was observed playing both movies and a TV episode; keep
        // automatic discovery and primary as one-tap fallbacks.
        return [mirror, auto, primary, link]
    }
}

struct EmbeddedServer: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL
}

@MainActor
final class EmbeddedPlayerModel: ObservableObject {
    let selection: EmbeddedSelection
    let servers: [EmbeddedServer]
    @Published var sourceIndex = 0
    @Published var pageLoaded = false
    @Published var playing = false
    @Published var playbackError: String?
    @Published var currentTime: Double = 0
    @Published var captionText = ""
    @Published var captionFileName: String?
    @Published var captionDelay: Double = 0
    @Published var captionSize: CGFloat = 22
    @Published var captionBottom: CGFloat = 10
    @Published var captionOpacity: Double = 0.5

    weak var webView: WKWebView?
    private var monitorTask: Task<Void, Never>?
    private var cues: [CaptionCue] = []
    private var automaticRetries = Set<Int>()

    init(selection: EmbeddedSelection) {
        self.selection = selection
        self.servers = selection.servers
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    func switchTo(_ index: Int) {
        guard servers.indices.contains(index), index != sourceIndex else { return }
        monitorTask?.cancel()
        webView?.stopLoading()
        webView = nil
        sourceIndex = index
        pageLoaded = false
        playing = false
        playbackError = nil
        currentTime = 0
        captionText = ""
    }

    func nextSource() { switchTo((sourceIndex + 1) % servers.count) }

    func attach(_ view: WKWebView) {
        webView = view
        monitorTask?.cancel()
        monitorTask = Task { [weak self, weak view] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 950_000_000)
                guard let self, let view, self.webView === view else { break }
                await self.inspect(view)
            }
        }
    }

    func loaded() { pageLoaded = true }

    func failed(_ message: String) {
        pageLoaded = true
        playbackError = message
        tryAutomaticFallback()
    }

    private func inspect(_ view: WKWebView) async {
        let script = """
        (function () {
          const videos = Array.from(document.querySelectorAll('video'));
          const v = videos.find(x => x.readyState > 1) || videos[0];
          return { t: v ? (v.currentTime || 0) : 0,
                   ready: v ? v.readyState : 0,
                   paused: v ? v.paused : true,
                   err: v && v.error ? v.error.code : 0,
                   text: (document.body ? document.body.innerText : '').slice(0, 2500) };
        })()
        """
        guard let data = try? await view.evaluateJavaScript(script) as? [String: Any],
              self.webView === view else { return }
        let time = (data["t"] as? NSNumber)?.doubleValue ?? 0
        let ready = (data["ready"] as? NSNumber)?.intValue ?? 0
        let paused = data["paused"] as? Bool ?? true
        let error = (data["err"] as? NSNumber)?.intValue ?? 0
        let body = (data["text"] as? String ?? "").lowercased()
        currentTime = max(0, time)
        if time > 0.2 && ready >= 2 {
            playing = !paused
            playbackError = nil
        } else if error > 0 || body.contains("this title will not play") || body.contains("no source returned a stream") {
            playing = false
            playbackError = "هذا السيرفر ما قدر يشغّل العنوان. جرّب السيرفر التالي."
            tryAutomaticFallback()
        }
        updateCaption()
    }

    private func tryAutomaticFallback() {
        let previousIndex = sourceIndex
        guard previousIndex < 2, automaticRetries.insert(previousIndex).inserted else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard let self, self.sourceIndex == previousIndex, !self.playing else { return }
            self.nextSource()
        }
    }

    func installCaptions(_ content: String, fileName: String) {
        cues = CaptionParser.parse(content)
        captionFileName = cues.isEmpty ? nil : fileName
        captionDelay = 0
        updateCaption()
    }

    func clearCaptions() {
        cues = []
        captionFileName = nil
        captionText = ""
    }

    func shiftCaptions(_ seconds: Double) {
        captionDelay += seconds
        updateCaption()
    }

    private func updateCaption() {
        let target = currentTime + captionDelay
        captionText = cues.first(where: { target >= $0.start && target < $0.end })?.text ?? ""
    }

    func stop() {
        monitorTask?.cancel()
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

private struct EmbeddedWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: EmbeddedPlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let inlineScript = WKUserScript(source: """
          document.addEventListener('DOMContentLoaded', function() {
            document.querySelectorAll('video').forEach(v => {
              v.setAttribute('playsinline', '');
              v.setAttribute('webkit-playsinline', '');
            });
          });
          """, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(inlineScript)

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.backgroundColor = .black
        web.isOpaque = false
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        model.attach(web)
        web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 24))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: EmbeddedPlayerModel
        init(model: EmbeddedPlayerModel) { self.model = model }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.loaded()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            model.failed("تعذر الاتصال بالمشغّل. يمكنك تجربة سيرفر ثاني.")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Third-party embeds sometimes ask to open unrelated ad pages or
            // new browser windows. Playback must stay inside this app.
            if action.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }
            guard action.targetFrame?.isMainFrame == true,
                  let destination = action.request.url else {
                decisionHandler(.allow)
                return
            }
            if destination.scheme == "about" || destination.scheme == "blob" {
                decisionHandler(.allow)
                return
            }
            let host = destination.host?.lowercased() ?? ""
            let trusted = ["embed.vidsrc.pk", "vidlink.pro", "www.vidlink.pro"]
            decisionHandler(destination.scheme == "https" && trusted.contains(host) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}

struct EmbeddedPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: EmbeddedPlayerModel
    @State private var captionSheet = false
    @State private var fileImporter = false
    private let selection: EmbeddedSelection

    init(selection: EmbeddedSelection) {
        self.selection = selection
        _model = StateObject(wrappedValue: EmbeddedPlayerModel(selection: selection))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                EmbeddedWebView(url: model.servers[model.sourceIndex].url, model: model)
                    .id(model.servers[model.sourceIndex].id)
                    .ignoresSafeArea()

                if !model.captionText.isEmpty {
                    VStack {
                        Spacer()
                        Text(model.captionText)
                            .font(.system(size: model.captionSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black, radius: 4)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(model.captionOpacity), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 30)
                            .padding(.bottom, max(1, model.captionBottom + geometry.safeAreaInsets.bottom))
                    }
                    .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if let problem = model.playbackError {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(problem).font(.system(size: 11, weight: .medium)).lineLimit(2)
                            Button("التالي") { model.nextSource() }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CinemaPalette.accent)
                        }
                        .padding(12)
                        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 13))
                        .padding(.horizontal, 22)
                        .padding(.bottom, 12)
                    } else if !model.pageLoaded {
                        HStack(spacing: 9) {
                            ProgressView().tint(CinemaPalette.accent)
                            Text("جارٍ فتح المشغّل…")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.74), in: Capsule())
                        .padding(.bottom, 8)
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { PlayerOrientation.set(.landscape) }
        .onDisappear { model.stop(); PlayerOrientation.set(.portrait) }
        .sheet(isPresented: $captionSheet) { captionControls }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [
            .plainText,
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText
        ]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16) else { return }
            model.installCaptions(content, fileName: url.lastPathComponent)
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            Button {
                model.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.15), in: Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(model.servers[model.sourceIndex].subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.70))
            }
            Spacer(minLength: 3)
            Menu {
                ForEach(Array(model.servers.enumerated()), id: \.offset) { index, source in
                    Button {
                        model.switchTo(index)
                    } label: {
                        if model.sourceIndex == index {
                            Label("\(source.title) · \(source.subtitle)", systemImage: "checkmark")
                        } else {
                            Text("\(source.title) · \(source.subtitle)")
                        }
                    }
                }
            } label: {
                Label("السيرفر", systemImage: "server.rack")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            Button { captionSheet = true } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 17))
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("إعدادات الترجمة")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(LinearGradient(colors: [.black.opacity(0.90), .black.opacity(0.14)], startPoint: .top, endPoint: .bottom))
    }

    private var captionControls: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("الترجمة")
                            .font(.title3.bold())
                        Text("اختر لغة الترجمة من زر CC الموجود في المشغّل. ولضبط التوقيت والحجم والموقع، أضف ملف SRT أو VTT من تطبيق الملفات.")
                            .font(.system(size: 12))
                            .foregroundStyle(CinemaPalette.secondary)
                    }
                    Button { fileImporter = true } label: {
                        Label("إضافة ملف ترجمة SRT / VTT", systemImage: "doc.badge.plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 45)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CinemaPalette.accent)
                    if let name = model.captionFileName {
                        HStack {
                            Label(name, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(CinemaPalette.accent)
                            Spacer()
                            Button("إزالة") { model.clearCaptions() }
                        }
                    }
                    Divider()
                    Text("تزامن الترجمة · \(model.captionDelay.formatted(.number.precision(.fractionLength(1)))) ثانية")
                        .font(.system(size: 14, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 9) {
                        ForEach([-60.0, -10.0, -1.0, -0.5, 0.5, 1, 10, 60], id: \.self) { amount in
                            Button(amount > 0 ? "+\(amount.formatted())" : amount.formatted()) {
                                model.shiftCaptions(amount)
                            }
                            .font(.system(size: 11, weight: .bold))
                            .buttonStyle(.bordered)
                        }
                    }
                    Button("تصفير التوقيت") { model.shiftCaptions(-model.captionDelay) }
                        .font(.system(size: 12))
                        .foregroundStyle(CinemaPalette.accent)
                    Divider()
                    Text("حجم الترجمة · \(Int(model.captionSize)) pt")
                    Slider(value: $model.captionSize, in: 14...40, step: 1).tint(CinemaPalette.accent)
                    Text("موقع الترجمة · \(Int(model.captionBottom)) pt من الأسفل")
                    Slider(value: $model.captionBottom, in: 1...150, step: 1).tint(CinemaPalette.accent)
                    Text("خلفية الترجمة · \(Int(model.captionOpacity * 100))%")
                    Slider(value: $model.captionOpacity, in: 0...1).tint(CinemaPalette.accent)
                    Text("إعدادات التوقيت والشكل تؤثر على ملف الترجمة الخارجي فقط. ترجمات السيرفر الأصلية يتحكم بها مشغّله.")
                        .font(.system(size: 11))
                        .foregroundStyle(CinemaPalette.secondary)
                }
                .padding(21)
            }
            .background(CinemaPalette.base)
            .foregroundStyle(.white)
            .navigationTitle("الترجمة والشكل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") { captionSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
