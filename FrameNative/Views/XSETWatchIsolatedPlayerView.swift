import SwiftUI
import WebKit
import SafariServices

// The host app remains entirely native; a separate full-screen provider
// handoff appears only after the user actively presses "Try player".
// This does not scrape, intercept or download provider media.
struct XSETWatchPlaybackRequest: Identifiable {
    let url: URL
    let title: String
    let episodeHint: String?
    var id: String { url.absoluteString + (episodeHint ?? "") }

    static func forTitle(_ item: XSCinemaMedia,
                         episode: XSCinemaEpisode? = nil) -> XSETWatchPlaybackRequest? {
        guard let number = item.tmdbID, number > 0 else { return nil }
        let rawSlug = item.title.folding(options: [.diacriticInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-",
                                  options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let slug = rawSlug.isEmpty ? "title" : rawSlug
        let year = item.year.range(of: #"(?:19|20)\d{2}"#, options: .regularExpression)
            .map { String(item.year[$0]) } ?? ""
        let suffix = year.isEmpty ? slug : "\(slug)-\(year)"
        let path = item.kind == .movie ? "movie" : "series"
        guard let url = URL(string: "https://www.etwatch.net/\(path)/\(number)-\(suffix)")
        else { return nil }
        let hint: String?
        if let episode {
            hint = "اختر الموسم \(episode.season)، الحلقة \(episode.number) داخل مشغل الموقع."
        } else {
            hint = nil
        }
        return XSETWatchPlaybackRequest(url: url, title: item.title, episodeHint: hint)
    }
}

@MainActor
final class XSETWatchPlaybackState: ObservableObject {
    @Published var pageLoading = true
    @Published var failed = false
    @Published var hintVisible = false
    @Published var issue: String?
    @Published var showSafari = false
    weak var webView: WKWebView?
    func reload() { failed=false;issue=nil;hintVisible=false;webView?.reload() }
}

struct XSETWatchIsolatedPlayerView: View {
    let request: XSETWatchPlaybackRequest
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = XSETWatchPlaybackState()
    @State private var healthCheck: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            XSETWatchPlaybackWebView(url: request.url, state: state)
                .ignoresSafeArea(edges: .bottom)

            if state.pageLoading && !state.failed {
                ProgressView("جاري فتح مشغّل المصدر…")
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(17)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 14))
            }

            if state.failed {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.orange)
                    Text("تعذر فتح مشغّل الموقع").font(.headline)
                    Text(state.issue ?? "ما قدرنا نحمّل الصفحة من المصدر.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                    Button("إعادة المحاولة") { state.reload() }
                        .buttonStyle(.borderedProminent)
                    Button("فتح المصدر في Safari") {
                        UIApplication.shared.open(request.url)
                    }
                        .buttonStyle(.bordered)
                }
                .foregroundStyle(.white)
                .padding(25)
                .frame(maxWidth: 320)
                .background(.black.opacity(0.95), in: RoundedRectangle(cornerRadius: 19))
            }

            VStack {
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.78), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.title)
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        Text("مشغّل ETWatch")
                            .font(.caption2).foregroundStyle(.white.opacity(0.67))
                    }
                    Spacer()
                    Button { state.hintVisible.toggle() } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 20))
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.78), in: Circle())
                    }
                    Button {
                        UIApplication.shared.open(request.url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 19))
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.78), in: Circle())
                    }
                    .accessibilityLabel("تشغيل عبر Safari")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .background(LinearGradient(
                    colors: [.black.opacity(0.86), .black.opacity(0)],
                    startPoint: .top, endPoint: .bottom))

                if state.hintVisible {
                    VStack(alignment: .leading, spacing: 11) {
                        if let hint = request.episodeHint {
                            Text(hint).font(.subheadline.bold())
                        }
                        Text("لو الفيديو وقف على 0:00، ممكن سيرفر الموقع ما يستجيب أو المشغّل ما يدعم WebKit. جرب إعادة فتحه، أو Safari للتأكد.")
                            .font(.footnote)
                        HStack {
                            Button("إعادة تحميل") { state.reload() }
                            Spacer()
                            Button("فتح Safari") { UIApplication.shared.open(request.url) }
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(17)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Spacer()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.hintVisible)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear {
            healthCheck?.cancel()
            healthCheck = Task {
                try? await Task.sleep(nanoseconds: 28_000_000_000)
                guard !Task.isCancelled, !state.failed else { return }
                // Page loaded != movie playing. Never declare video success
                // based only on document navigation.
                state.hintVisible = true
            }
        }
        .onDisappear { healthCheck?.cancel(); state.webView?.stopLoading() }
    }
}

private struct XSETWatchPlaybackWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: XSETWatchPlaybackState

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        state.webView = web
        web.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData,
                            timeoutInterval: 25))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let state: XSETWatchPlaybackState
        init(state: XSETWatchPlaybackState) { self.state = state }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.pageLoading = true
            state.failed = false
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.pageLoading = false
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            state.pageLoading = false
            state.failed = true
            state.issue = "تعذر الاتصال بموقع التشغيل. افحص الشبكة أو جرب Safari."
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            state.pageLoading = false
            state.failed = true
            state.issue = "صفحة التشغيل ما اكتملت."
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            state.pageLoading = false
            state.failed = true
            state.issue = "توقف مشغل الويب عن العمل."
        }
        // A provider may open content in target=_blank. Preserve internal
        // navigation without redirecting to random advertisement domains.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil,
               let url = navigationAction.request.url,
               ["etwatch.net", "www.etwatch.net"].contains(url.host ?? "") {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
