import Foundation
import SwiftUI
import WebKit

@MainActor
private final class SitePlayerMessageRelay: NSObject, WKScriptMessageHandler {
    weak var owner: SitePlayerModel?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

@MainActor
final class SitePlayerModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let request: SitePlaybackRequest
    let webView: WKWebView
    @Published private(set) var loading = true
    @Published private(set) var error: String?
    var onClose: (() -> Void)?
    var onProgress: ((Double, Double, Int?, Int?) -> Void)?
    private let relay = SitePlayerMessageRelay()
    private let preview: Bool
    private var started = false
    private var closed = false
    private var lastWatchURL: URL
    private var urlObservation: NSKeyValueObservation?

    init(request: SitePlaybackRequest, preview: Bool = false) {
        self.request = request; self.preview = preview; lastWatchURL = request.url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(WKUserScript(source: Self.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        relay.owner = self
        configuration.userContentController.add(relay, name: "watchedPlayer")
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.backgroundColor = .black; webView.scrollView.backgroundColor = .black
        webView.isOpaque = true; webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.accessibilityIdentifier = "site-player-webview"
        // Next.js can change routes without a navigation delegate callback.
        urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
            guard let self, !self.closed, let url = webView.url else { return }
            switch SitePlayerNavigation.action(for: url) {
            case .play: self.lastWatchURL = url
            case .returnToApp: self.close()
            case .block: break
            }
        }
    }

    func start() {
        guard !started, !closed else { return }
        started = true; load()
    }

    func load() {
        guard !closed else { return }
        error = nil; loading = true
        #if DEBUG
        if preview {
            webView.loadHTMLString(Self.previewHTML(request: request), baseURL: request.url)
            return
        }
        #endif
        webView.load(URLRequest(url: lastWatchURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60))
    }

    func close() {
        guard !closed else { return }
        let callback = onClose
        stop()
        callback?()
    }

    func stop() {
        guard !closed else { return }
        closed = true
        onClose = nil; onProgress = nil
        urlObservation?.invalidate(); urlObservation = nil
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "watchedPlayer")
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.stopLoading()
        // Unload the document and its media, including any fullscreen/PiP playback.
        webView.loadHTMLString("", baseURL: nil)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard !closed, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == "watched.cx",
              let value = message.body as? [String: Any], let type = value["type"] as? String else { return }
        if type == "close" { close(); return }
        guard type == "progress", let rawURL = value["page"] as? String, let url = URL(string: rawURL),
              let route = SitePlayerRoute(url: url), route.tmdbID == request.title.tmdbID, route.kind == request.title.kind,
              let position = value["position"] as? Double, let duration = value["duration"] as? Double,
              position.isFinite, duration.isFinite, position >= 0, duration > 0 else { return }
        onProgress?(position, duration, route.season, route.episode)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !closed, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false {
            // Preserve the site's normal provider and security-check frames.
            decisionHandler(url.scheme == "https" || url.absoluteString == "about:blank" ? .allow : .cancel)
            return
        }
        switch SitePlayerNavigation.action(for: url) {
        case .play:
            if navigationAction.targetFrame == nil {
                decisionHandler(.cancel); webView.load(navigationAction.request)
            } else { decisionHandler(.allow) }
        case .returnToApp:
            decisionHandler(.cancel); close()
        case .block:
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard !closed else { return }; loading = true; error = nil
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { if !closed { loading = false } }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ failure: Error) {
        guard !closed, (failure as NSError).code != NSURLErrorCancelled else { return }
        loading = false; error = failure.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard !closed else { return }; loading = false; error = "توقف المشغّل. اضغط إعادة المحاولة."
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

    /// Only app navigation/progress is bridged. Source playback, subtitles and verification stay with the site.
    static let bridge = #"""
    (() => {
      if (location.protocol !== 'https:' || location.hostname !== 'watched.cx') return;
      const send = body => window.webkit.messageHandlers.watchedPlayer.postMessage(body);
      const isWatch = url => url.origin === location.origin && /^\/(movie|tv)\/\d+\/?$/.test(url.pathname);
      const report = () => {
        const video = document.querySelector('video');
        if (video && Number.isFinite(video.currentTime) && Number.isFinite(video.duration) && video.duration > 0)
          send({type:'progress', page:location.href, position:video.currentTime, duration:video.duration});
      };
      const close = () => { report(); send({type:'close'}); };
      document.addEventListener('click', event => {
        const target = event.target instanceof Element ? event.target : null;
        if (!target) return;
        const back = target.closest('button[aria-label="Back"]');
        const link = target.closest('a[href]');
        let leavesPlayer = false;
        if (link) { try { const url = new URL(link.href, location.href); leavesPlayer = url.origin === location.origin && !isWatch(url); } catch (_) {} }
        if (back || leavesPlayer) { event.preventDefault(); event.stopImmediatePropagation(); close(); }
      }, true);
      for (const key of ['pushState','replaceState']) {
        const original = history[key];
        history[key] = function(state, title, url) {
          if (url != null) {
            try { const destination = new URL(url, location.href); if (destination.origin === location.origin && !isWatch(destination)) { close(); return; } } catch (_) {}
          }
          return original.apply(this, arguments);
        };
      }
      addEventListener('popstate', () => { if (!isWatch(new URL(location.href))) close(); });
      // iPhone's video fullscreen Done button should also return to the app.
      document.addEventListener('webkitendfullscreen', close, true);
      const attached = new WeakSet();
      const attach = () => document.querySelectorAll('video').forEach(video => {
        if (attached.has(video)) return;
        attached.add(video);
        let last = 0;
        video.addEventListener('timeupdate', () => { if (Date.now() - last > 5000) { last = Date.now(); report(); } });
        video.addEventListener('pause', report); video.addEventListener('ended', report);
      });
      document.addEventListener('DOMContentLoaded', () => { attach(); new MutationObserver(attach).observe(document.documentElement, {childList:true, subtree:true}); });
    })();
    """#

    #if DEBUG
    private static func previewHTML(request: SitePlaybackRequest) -> String {
        // Offline UI fixture. No sample film or substitute live stream is used.
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{background:#090909;color:white;font:18px system-ui;padding:30px}button{display:block;padding:18px;margin:20px 0;color:white;background:#303030;border:0;border-radius:12px}</style></head>
        <body><h2>Offline player navigation test</h2><p>\(request.url.path)\(request.url.query.map { "?" + $0 } ?? "")</p>
        <button aria-label="Back" onclick="location.href='/browse/\(request.title.kind.rawValue)/\(request.title.tmdbID)'">Site Back</button>
        <button onclick="history.pushState({},'', '/browse/\(request.title.kind.rawValue)/\(request.title.tmdbID)')">SPA Back</button>
        <button onclick="document.dispatchEvent(new Event('webkitendfullscreen'))">Fullscreen Done</button>
        </body></html>
        """
    }
    #endif
}

private struct SitePlayerSurface: UIViewRepresentable {
    let model: SitePlayerModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) { uiView.stopLoading() }
}

struct SitePlayerScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: SitePlayerModel

    init(request: SitePlaybackRequest, preview: Bool = false) {
        _model = StateObject(wrappedValue: SitePlayerModel(request: request, preview: preview))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.close() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44) }
                    .accessibilityLabel(store.t("إغلاق المشغّل", "Close player")).accessibilityIdentifier("close-site-player")
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.request.title.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(store.t("مشغّل الموقع", "Website player")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if model.loading { ProgressView().tint(.white).padding(.trailing, 10) }
                Button { model.load() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                    .accessibilityLabel(store.t("إعادة تحميل المشغّل", "Reload player"))
            }.padding(.horizontal, 6).frame(height: 52).background(.black)
            ZStack {
                SitePlayerSurface(model: model)
                if let error = model.error {
                    VStack(spacing: 18) {
                        Text(store.t("تعذّر فتح المشغّل", "Couldn’t open the player")).font(.headline)
                        Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button(store.t("إعادة المحاولة", "Try again")) { model.load() }.buttonStyle(PrimaryAction())
                    }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                }
            }
        }
        .foregroundStyle(.white).background(.black).ignoresSafeArea(edges: .bottom)
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            let close = dismiss
            let appStore = store
            let title = model.request.title
            model.onClose = { close() }
            model.onProgress = { position, duration, season, episode in
                appStore.updateProgress(title: title, position: position, duration: duration, season: season, episode: episode)
            }
            model.start()
        }
        .onDisappear { model.stop() }
    }
}
