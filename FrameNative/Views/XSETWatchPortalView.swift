import SwiftUI
import WebKit

/// Displays the original website, and intentionally never copies its media,
/// intercepts HLS requests or replaces the website's own subtitle player.
/// Movies and Series are discovered from actual page links at runtime:
/// no guessed URLs, scraping endpoints or duplicated third-party inventory.
enum XSETWatchSection: Int {
    case home = 0
    case movies = 1
    case series = 2

    var title: String {
        switch self {
        case .home: return "الرئيسية"
        case .movies: return "الأفلام"
        case .series: return "المسلسلات"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .movies: return "film.fill"
        case .series: return "play.rectangle.on.rectangle"
        }
    }
}

@MainActor
final class XSETWatchBrowserState: ObservableObject {
    @Published var isLoading = true
    @Published var progress = 0.0
    @Published var pageTitle = "ETWatch"
    @Published var error: String?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var missingSection = false
    weak var browser: WKWebView?

    func refresh() { browser?.reload() }
    func goBack() { browser?.goBack() }
    func goForward() { browser?.goForward() }

    func openOfficialSite() {
        guard let url = URL(string: "https://www.etwatch.net/") else { return }
        UIApplication.shared.open(url)
    }
}

struct XSETWatchPortalView: View {
    let section: XSETWatchSection
    @StateObject private var browserState = XSETWatchBrowserState()

    var body: some View {
        ZStack {
            XSCinemaStyle.background.ignoresSafeArea()
            VStack(spacing: 0) {
                toolbar
                if browserState.isLoading {
                    ProgressView(value: browserState.progress, total: 1)
                        .tint(XSCinemaStyle.accent)
                        .frame(height: 2)
                }
                XSETWatchWebView(section: section, state: browserState)
                    .background(Color.black)
                    .overlay {
                        if let error = browserState.error {
                            disconnected(error)
                        } else if browserState.missingSection {
                            missingSectionView
                        }
                    }
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear { /* Browser handles its own lifecycle. */ }
    }

    private var toolbar: some View {
        HStack(spacing: 11) {
            XSBrandMark(size: 29)
            Text("XS TV").font(.system(size: 18, weight: .heavy))
            Text("·").foregroundStyle(.white.opacity(0.5))
            Text(section.title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Spacer(minLength: 0)
            Button { browserState.goBack() } label: {
                Image(systemName: "chevron.backward")
                    .frame(width: 32, height: 36)
            }
            .disabled(!browserState.canGoBack)
            Button { browserState.refresh() } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 32, height: 36)
            }
            Button { browserState.openOfficialSite() } label: {
                Image(systemName: "arrow.up.right.square")
                    .frame(width: 32, height: 36)
            }
            .accessibilityLabel("فتح الموقع الأصلي")
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(XSCinemaStyle.background)
    }

    private func disconnected(_ message: String) -> some View {
        VStack(spacing: 13) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("تعذر فتح ETWatch").font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.69))
            Button("إعادة المحاولة") { browserState.refresh() }
                .buttonStyle(.borderedProminent)
            Button("فتح ETWatch في Safari") { browserState.openOfficialSite() }
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(maxWidth: 300)
        .background(Color.black.opacity(0.90), in: RoundedRectangle(cornerRadius: 18))
    }

    private var missingSectionView: some View {
        VStack(spacing: 14) {
            Image(systemName: section.symbol).font(.system(size: 28))
            Text("ما قدرت أحدد رابط \(section.title) من الموقع")
                .font(.subheadline.bold())
                .multilineTextAlignment(.center)
            Text("الموقع تغيّر أو ما يعرض روابط الأقسام لتطبيقات الويب. نقدر نفتح الصفحة الأصلية بدلاً من اختراع رابط.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.65))
            Button("فتح الصفحة الرئيسية") {
                browserState.missingSection = false
                browserState.browser?.load(URLRequest(
                    url: URL(string: "https://www.etwatch.net/")!))
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: 300)
        .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct XSETWatchWebView: UIViewRepresentable {
    let section: XSETWatchSection
    @ObservedObject var state: XSETWatchBrowserState

    func makeCoordinator() -> Coordinator { Coordinator(section: section, state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.backgroundColor = .black
        web.isOpaque = false
        web.scrollView.backgroundColor = .black
        web.allowsBackForwardNavigationGestures = true
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        state.browser = web
        if let url = URL(string: "https://www.etwatch.net/") {
            web.load(URLRequest(url: url,
                                cachePolicy: .returnCacheDataElseLoad,
                                timeoutInterval: 20))
        } else {
            state.error = "رابط الموقع غير صالح."
        }
        return web
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let section: XSETWatchSection
        let state: XSETWatchBrowserState
        private var sectionDiscoveryAttempted = false
        private var seriesHubAttempted = false

        init(section: XSETWatchSection, state: XSETWatchBrowserState) {
            self.section = section
            self.state = state
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.isLoading = true
            state.progress = 0.1
            state.error = nil
            state.missingSection = false
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            state.progress = 0.6
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.isLoading = false
            state.progress = 1
            state.pageTitle = webView.title ?? "ETWatch"
            state.canGoBack = webView.canGoBack
            state.canGoForward = webView.canGoForward

            guard section != .home, !sectionDiscoveryAttempted else { return }
            sectionDiscoveryAttempted = true
            let script: String
            switch section {
            case .movies:
                script = """
                (function(){
                  const links = Array.from(document.querySelectorAll('a[href]'));
                  const candidates = links.filter(a=>{
                    const s=(a.innerText+' '+a.getAttribute('href')).toLowerCase();
                    return (/movie|film|أفلام|افلام|الأفلام/.test(s) &&
                           !/anime|انمي|أنمي|episode|مسلسل/.test(s));
                  });
                  const link = candidates.find(a => /movie|film|أفلام|افلام/.test((a.innerText||'').toLowerCase())) || candidates[0];
                  return link ? link.href : null;
                })()
                """
            case .series:
                script = """
                (function(){
                  const links=Array.from(document.querySelectorAll('a[href]'));
                  const candidates=links.filter(a=>{
                    const s=(a.innerText+' '+a.getAttribute('href')).toLowerCase();
                    return (/series|tv.show|shows|مسلسل|مسلسلات/.test(s) &&
                           !/anime|انمي|أنمي|episode|حلقة/.test(s));
                  });
                  const link=candidates.find(a => /series|shows|مسلسل/.test((a.innerText||'').toLowerCase())) || candidates[0];
                  return link ? link.href : null;
                })()
                """
            case .home: return
            }
            webView.evaluateJavaScript(script) { [weak self, weak webView] value, error in
                guard let self, let webView else { return }
                let result = (value as? String).flatMap(URL.init(string:))
                let isSite = result.map { url in
                    ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                    && (url.host == "etwatch.net" || url.host == "www.etwatch.net")
                } ?? false
                if error == nil, let result, isSite {
                    if result != webView.url { webView.load(URLRequest(url: result)) }
                    return
                }
                // Homepage currently exposes /movies, not a TV/Series anchor.
                // Follow its real Movies link, then discover the Shows section
                // within that page; never fabricate a /series endpoint.
                if self.section == .series && !self.seriesHubAttempted {
                    self.seriesHubAttempted = true
                    self.sectionDiscoveryAttempted = false
                    webView.evaluateJavaScript("""
                        (function(){
                           const a=Array.from(document.querySelectorAll('a[href]')).find(x=>
                               (x.getAttribute('href')||'').replace(/\\/$/,'')==='/movies');
                           return a ? a.href : null;
                        })()
                        """) { [weak self, weak webView] destination, _ in
                            guard let self, let webView else { return }
                            if let text = destination as? String, let url = URL(string: text),
                               url.host == "www.etwatch.net" || url.host == "etwatch.net" {
                                webView.load(URLRequest(url: url))
                            } else {
                                self.state.missingSection = true
                            }
                        }
                } else {
                    self.state.missingSection = true
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
            state.error = "الموقع ما استجاب. تأكد أنه يفتح من Safari على نفس الشبكة."
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.isLoading = false
            state.error = "تعذر تحميل الصفحة أو المشغل من المصدر."
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.cancel);return
            }
            decisionHandler(["https", "http", "about", "blob"].contains(scheme) ? .allow : .cancel)
        }

        // Avoid opening advertising pop-up windows. Player links within the
        // existing window remain under the website's own logic.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures)
                     -> WKWebView? {
            nil
        }
    }
}
