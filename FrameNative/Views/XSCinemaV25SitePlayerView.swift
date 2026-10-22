import SwiftUI
import WebKit

/// Site-owned playback view: the home/library/search UI remains 100% SwiftUI.
/// Open the actual ETWatch watch route only after a user taps a title/episode.
/// No stream URL extraction, proxy bypass, DOM scraping, or hidden API calls.
struct XSCinemaV25PlayerSelection: Identifiable {
    let tmdbID: Int
    let kind: XSCinemaMediaKind
    let title: String
    let season: Int
    let episode: Int
    var id: String { "\(kind.rawValue):\(tmdbID):\(season):\(episode)" }
    var watchURL: URL? {
        guard tmdbID > 0 else { return nil }
        let route = kind == .movie
            ? "watch/movie/\(tmdbID)"
            : "watch/tv/\(tmdbID)/\(max(1,season))/\(max(1,episode))"
        return URL(string: "https://www.etwatch.net/\(route)")
    }
}

struct XSCinemaV25SitePlayerView: View {
    let selection: XSCinemaV25PlayerSelection
    @Environment(\.dismiss) private var dismiss
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let url = selection.watchURL {
                XSCinemaV25SiteWebView(url: url, loaded: $loaded, failed: $failed)
                    .ignoresSafeArea(edges: .bottom)
            }

            if !loaded && !failed {
                VStack(spacing: 11) {
                    ProgressView().tint(.white)
                    Text("نفتح مشغل الموقع")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                }
            }

            if failed || selection.watchURL == nil {
                VStack(spacing: 14) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size:26))
                    Text("تعذر فتح صفحة المشاهدة")
                        .font(.headline)
                    Text("قد يكون الموقع غير متاح أو يمنع التشغيل داخل التطبيقات.")
                        .multilineTextAlignment(.center)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    if let url = selection.watchURL {
                        Button("جرب في Safari") { UIApplication.shared.open(url) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(22)
                .background(Color.black.opacity(0.92), in: RoundedRectangle(cornerRadius:18))
                .frame(maxWidth:330)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size:15,weight:.bold))
                    .foregroundStyle(.white)
                    .frame(width:41,height:41)
                    .background(.black.opacity(0.84),in:Circle())
            }
            .padding(.leading,16)
            .padding(.top,8)
        }
        .preferredColorScheme(.dark)
    }
}

private struct XSCinemaV25SiteWebView: UIViewRepresentable {
    let url: URL
    @Binding var loaded: Bool
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(loaded: $loaded, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.allowsInlineMediaPlayback = true
        cfg.allowsAirPlayForMediaPlayback = true
        cfg.allowsPictureInPictureMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame:.zero, configuration:cfg)
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.isOpaque = false
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        view.load(URLRequest(url:url,cachePolicy:.useProtocolCachePolicy,timeoutInterval:25))
        return view
    }
    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var loaded:Bool
        @Binding var failed:Bool
        init(loaded:Binding<Bool>,failed:Binding<Bool>) {
            _loaded=loaded
            _failed=failed
        }
        func webView(_ view: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            failed = false
        }
        func webView(_ view: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            loaded = true
            failed = true
        }
        func webView(_ view: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            loaded = true
            failed = true
        }
        func webView(_ view: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if let http = response.response as? HTTPURLResponse, http.statusCode >= 400,
               http.response?.url?.host == "www.etwatch.net" {
                failed = true
            }
            decisionHandler(.allow)
        }
    }
}
