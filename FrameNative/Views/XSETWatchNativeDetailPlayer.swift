import SwiftUI
import WebKit
import SafariServices

/// Presents the source's dedicated watch page. The same WKWebView remains
/// mounted when the player expands, so HTML captions never leave the video.
struct XSETWatchNativeDetailPlayer: View {
    let url: URL
    let title: String
    var season: Int? = nil
    var episode: Int? = nil
    var resumePosition: Double = 0
    var onProgress: ((Double, Double) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var state = XSETWatchPlaybackHealth()
    @State private var presentSafari = false

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            // Stable identity: expanding changes padding only, not hierarchy.
            XSETWatchVideoWebView(url: url, state: state, resumePosition: resumePosition)
                .padding(.top, state.theaterMode ? 0 : 58)
                .overlay(alignment: .bottom) {
                    if state.stalled { recoveryCard.padding(18) }
                }
            if !state.theaterMode {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("إغلاق المشغل")
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.subheadline.bold()).lineLimit(1)
                        Text(state.subtitle).font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { state.toggleTheater() } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("تكبير مع الترجمة")
                    Menu {
                        Button { state.reload() } label: { Label("إعادة الاتصال", systemImage: "arrow.clockwise") }
                        Button { presentSafari = true } label: { Label("فتح في Safari", systemImage: "safari") }
                        Button { UIPasteboard.general.string = state.safeDiagnostic } label: {
                            Label("نسخ تقرير التشخيص", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("خيارات المشغل")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).frame(height: 58)
                .background(.black)
            } else {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("إغلاق المشغل")
                    Spacer()
                    Button { state.toggleTheater() } label: {
                        Image(systemName: "arrow.down.right.and.arrow.up.left")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("تصغير")
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .background(LinearGradient(colors: [.black.opacity(0.45), .clear],
                                           startPoint: .top, endPoint: .bottom))
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(state.theaterMode)
        .sheet(isPresented: $presentSafari) {
            XSETWatchSafariFallback(url: url).ignoresSafeArea()
        }
        .onAppear { state.onProgress = onProgress; state.beginWatch() }
        .onDisappear { state.endWatch() }
        .onChange(of: scenePhase) { phase in
            if phase == .background { state.pause() }
        }
    }

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("تعذر بدء الفيديو", systemImage: "exclamationmark.triangle")
                .font(.subheadline.bold()).foregroundStyle(.yellow)
            Text("جرّب سيرفراً آخر من زر Servers داخل المشغل، أو أعد الاتصال.")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
            HStack {
                Button("إعادة الاتصال") { state.reload() }
                    .buttonStyle(.borderedProminent)
                Button("إخفاء التنبيه") { state.stalled = false }
                    .buttonStyle(.bordered)
            }
            .tint(Color(red: 0.50, green: 0.77, blue: 0.67))
        }
        .padding(18)
        .frame(maxWidth: 450, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

@MainActor
final class XSETWatchPlaybackHealth: ObservableObject {
    @Published var subtitle = "جاري فتح صفحة المشاهدة…"
    @Published var stalled = false
    @Published var pageLoaded = false
    @Published var theaterMode = false
    @Published var playbackSeen = false
    @Published var siteError: String?
    weak var web: WKWebView?
    var onProgress: ((Double, Double) -> Void)?
    private var timeout: Task<Void, Never>?
    private var lastActivity = Date()
    private var paused = false
    private var lastPosition: Double = 0
    private var duration: Double = 0

    var safeDiagnostic: String {
        "XS TV V27 | pageLoaded=\(pageLoaded) | playbackDetected=\(playbackSeen) | stalled=\(stalled) | diagnostic=\(siteError ?? "none") | iOS WebKit"
    }

    func beginWatch() {
        lastActivity = Date()
        timeout?.cancel()
        timeout = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled, let self else { return }
                if !self.paused && Date().timeIntervalSince(self.lastActivity) >= 35 {
                    self.stalled = true
                    self.subtitle = self.playbackSeen ? "توقف وصول الفيديو" : "لم يبدأ تشغيل الفيديو"
                }
            }
        }
    }
    func pause() {
        paused = true
        web?.evaluateJavaScript("window.__xstvPause && window.__xstvPause();", completionHandler: nil)
        if lastPosition > 5 { onProgress?(lastPosition, duration) }
    }
    func endWatch() { pause(); timeout?.cancel(); timeout = nil }
    func toggleTheater() {
        let enter = !theaterMode
        let function = enter ? "__xstvEnterTheater" : "__xstvExitTheater"
        web?.evaluateJavaScript("window.\(function) ? window.\(function)() : false;") { [weak self] result, _ in
            guard let self else { return }
            if (result as? Bool) == true { self.theaterMode = enter }
            else { self.subtitle = "انتظر حتى يظهر مشغل الفيديو ثم جرّب التكبير" }
        }
    }
    func reload() {
        playbackSeen = false; stalled = false; pageLoaded = false
        siteError = nil; paused = false; theaterMode = false
        subtitle = "إعادة الاتصال بالمشغل…"
        web?.reload()
        beginWatch()
    }
    func notePlayer(_ event: String, time: Double, total: Double) {
        if event == "theaterStarted" { theaterMode = true; return }
        if event == "theaterStopped" { theaterMode = false; return }
        if event == "pause" || event == "ended" {
            paused = true
            if time > 5 { onProgress?(time, total) }
            return
        }
        if event == "playing" || event == "timeupdate" {
            guard time > 0.15 else { return }
            playbackSeen = true; stalled = false; paused = false
            lastActivity = Date(); lastPosition = time; duration = total
            subtitle = "الفيديو قيد التشغيل"
            onProgress?(time, total)
        } else if event == "error" {
            siteError = "html_video_error"; stalled = true
            subtitle = "حدث خطأ في مشغل الفيديو"
        } else if event == "waiting" || event == "stalled" {
            paused = false
            subtitle = "جارٍ تحميل الفيديو…"
        } else if event == "loadedmetadata" {
            lastActivity = Date()
            subtitle = "تم العثور على بيانات الفيديو"
        }
    }
}

private struct XSETWatchVideoWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: XSETWatchPlaybackHealth
    let resumePosition: Double
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        let position = resumePosition.isFinite ? max(0, resumePosition) : 0
        let config = "window.__xstvPlaybackConfig={resumePosition:\(position)};\n"
        if let path = Bundle.main.url(forResource: "xstv-cinema", withExtension: "js"),
           let source = try? String(contentsOf: path, encoding: .utf8) {
            content.addUserScript(WKUserScript(source: config + source,
                                              injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        content.add(context.coordinator, name: "xstvVideoStatus")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = content
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        state.web = web
        web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 25))
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {}
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.evaluateJavaScript("window.__xstvPause && window.__xstvPause();", completionHandler: nil)
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "xstvVideoStatus")
        web.navigationDelegate = nil; web.uiDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let state: XSETWatchPlaybackHealth
        private var recoveredProcess = false
        init(state: XSETWatchPlaybackHealth) { self.state = state }
        func webView(_ web: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.pageLoaded = false
        }
        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            state.pageLoaded = true
            if !state.playbackSeen { state.subtitle = "جارٍ توصيل مشغل الفيديو…" }
        }
        private func failed(_ error: Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            state.siteError = "navigation_failed"; state.stalled = true
            state.subtitle = "فشل فتح صفحة المشاهدة"
        }
        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webView(_ web: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
        func webViewWebContentProcessDidTerminate(_ web: WKWebView) {
            if !recoveredProcess { recoveredProcess = true; state.reload() }
            else { state.siteError = "web_process_terminated"; state.stalled = true }
        }
        func userContentController(_ content: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "xstvVideoStatus", let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            let seconds = (body["seconds"] as? NSNumber)?.doubleValue ?? 0
            let total = (body["duration"] as? NSNumber)?.doubleValue ?? 0
            guard seconds.isFinite, total.isFinite else { return }
            state.notePlayer(event, time: seconds, total: total)
        }
        func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard action.targetFrame == nil, action.navigationType == .linkActivated,
                  let target = action.request.url, target.scheme == "https" else { return nil }
            if target.host == "www.etwatch.net" || target.host == "etwatch.net" { web.load(action.request) }
            return nil
        }
    }
}

private struct XSETWatchSafariFallback: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
