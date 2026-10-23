import SwiftUI
import WebKit
import SafariServices

// MARK: - Site-owned playback / native diagnostics
// No IPTV VOD, token interception, stream scraping, or fabricated subtitle cues.
// Playback and quality are controlled by the provider's authorized web player.
// Keep HTML video and the caption DOM in the same WKWebView, not a separate
// AVPlayer fullscreen view that strips overlay subtitles.

struct XSWorldSitePlayer: View {
    let url: URL
    let title: String
    var episode: Int? = nil
    var season: Int? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var monitor = XSWorldVideoMonitor()
    @State private var showSafari = false
    @State private var showInfo = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            XSWorldWebPlayer(url: url, episode: episode, season: season,
                             monitor: monitor)
                .ignoresSafeArea(edges: .bottom)
            VStack {
                HStack(spacing: 11) {
                    control("xmark", title: "إغلاق") { dismiss() }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        Text(monitor.message)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.69))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 3)
                    control(monitor.cinemaMode
                            ? "arrow.down.right.and.arrow.up.left"
                            : "arrow.up.left.and.arrow.down.right",
                            title: "وضع سينمائي مع الترجمة") {
                        monitor.toggleCinema()
                    }
                    control("arrow.clockwise", title: "إعادة المحاولة") {
                        monitor.reload()
                    }
                    control("ellipsis.circle", title: "المعلومات") {
                        showInfo = true
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(LinearGradient(colors: [.black.opacity(0.91),
                                                    .black.opacity(0.42), .clear],
                                           startPoint: .top, endPoint: .bottom))
                Spacer()
                if monitor.unavailable {
                    failurePanel
                        .padding(.horizontal, 14)
                        .padding(.bottom, 26)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(monitor.cinemaMode)
        .onAppear { monitor.begin() }
        .onDisappear { monitor.stop() }
        .sheet(isPresented: $showSafari) {
            XSWorldSafariFallback(url: url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showInfo) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Playback diagnostics", systemImage: "waveform.path")
                        .font(.title3.bold())
                    Text("المشغل والترجمة والجودات تابعة لموقع ETWatch. وضع السينما يبقي الفيديو والترجمة داخل صفحة WebKit نفسها متى كان ذلك ممكناً.")
                        .font(.subheadline)
                    Text(monitor.diagnostic)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = monitor.diagnostic
                    } label: {
                        Label("نسخ تقرير التشخيص", systemImage: "doc.on.doc")
                    }
                    Spacer()
                }
                .padding(22)
                .navigationTitle("Player Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("إغلاق") { showInfo = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func control(_ systemName: String, title: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 39, height: 39)
                .background(.black.opacity(0.62), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.14)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var failurePanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("تعذر بدء تشغيل الفيديو", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(XSCinemaStyle.gold)
            Text("المشغل ما أكد وصول بيانات الفيديو. ممكن يكون المصدر ما يدعم المشاهدة عبر WebKit، أو السيرفر متوقف أو الرابط يحتاج تحديث.")
                .font(.caption)
                .lineSpacing(4)
                .foregroundStyle(.white.opacity(0.81))
            HStack(spacing: 10) {
                Button { monitor.reload() } label: {
                    Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity, minHeight: 43)
                }
                .buttonStyle(.bordered)
                Button { showSafari = true } label: {
                    Label("Safari", systemImage: "safari")
                        .frame(maxWidth: .infinity, minHeight: 43)
                }
                .buttonStyle(.borderedProminent)
                .tint(XSCinemaStyle.accent)
            }
        }
        .padding(19)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .stroke(.white.opacity(0.15)))
    }
}

@MainActor
final class XSWorldVideoMonitor: ObservableObject {
    @Published var message = "Connecting to player..."
    @Published var unavailable = false
    @Published var cinemaMode = false
    @Published var playbackStarted = false
    @Published var pageLoaded = false
    @Published var nativeArabicTrackFound = false
    @Published var nativeSubtitleCount = 0
    @Published var embeddedVideo = false

    weak var webView: WKWebView?
    private var timeout: Task<Void, Never>?
    private var generation = 0

    var diagnostic: String {
        "XS TV / WebKit V27\n"
        + "pageLoaded=\(pageLoaded), videoPlaying=\(playbackStarted), "
        + "playerFrame=\(embeddedVideo), unavailable=\(unavailable)\n"
        + "captionTracks=\(nativeSubtitleCount), ArabicTrackFound=\(nativeArabicTrackFound)\n"
        + "cinemaMode=\(cinemaMode)\n"
        + "sitePlayer=external, streamURL=not inspected"
    }

    func begin() {
        generation += 1
        let current = generation
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 38_000_000_000)
            guard !Task.isCancelled, let self,
                  self.generation == current && !self.playbackStarted else { return }
            self.unavailable = true
            self.message = "Video server did not respond"
        }
    }

    func stop() {
        generation += 1
        timeout?.cancel()
        webView?.stopLoading()
    }

    func reload() {
        playbackStarted = false
        unavailable = false
        pageLoaded = false
        message = "Reconnecting..."
        webView?.reload()
        begin()
    }

    func toggleCinema() {
        let command = cinemaMode
            ? "window.__xstvRestoreCinema && window.__xstvRestoreCinema();"
            : "window.__xstvExpandCinema && window.__xstvExpandCinema();"
        webView?.evaluateJavaScript(command, completionHandler: nil)
        cinemaMode.toggle()
    }

    func update(_ details: [String: Any]) {
        let event = details["event"] as? String ?? ""
        let seconds = (details["seconds"] as? NSNumber)?.doubleValue ?? 0
        if let count = details["captions"] as? Int { nativeSubtitleCount = max(nativeSubtitleCount, count) }
        if let arabic = details["arabic"] as? Bool {
            nativeArabicTrackFound = nativeArabicTrackFound || arabic
        }
        if event == "playback" && seconds > 0.15 {
            playbackStarted = true
            unavailable = false
            message = "Now playing"
            timeout?.cancel()
        } else if event == "buffering" && !playbackStarted {
            message = "Loading video..."
        } else if event == "trackDetected" {
            message = nativeArabicTrackFound ? "Arabic subtitles detected" : "Player is ready"
        } else if event == "error" {
            unavailable = true
            message = "Video playback error"
        } else if event == "frame" {
            embeddedVideo = true
        }
    }
}

private struct XSWorldWebPlayer: UIViewRepresentable {
    let url: URL
    let episode: Int?
    let season: Int?
    @ObservedObject var monitor: XSWorldVideoMonitor

    func makeCoordinator() -> Coordinator {
        Coordinator(monitor: monitor, episode: episode, season: season)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "xstvStatus")
        controller.addUserScript(WKUserScript(
            source: Self.playerScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = controller
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.backgroundColor = .black
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        monitor.webView = view
        view.load(URLRequest(url: url,
                             cachePolicy: .useProtocolCachePolicy,
                             timeoutInterval: 26))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "xstvStatus")
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
    }

    // Main frame and third-party iframe each receive the same script. We do
    // not inspect media requests: only public DOM playback state and caption
    // track counts. Default WebKit fullscreen is NOT invoked by this script.
    private static let playerScript: String = #"""
    (() => {
      if (window.__xstvInstalled) return;
      window.__xstvInstalled = true;
      const emit = (event, seconds=0, captions=0, arabic=false) => {
        try {
          window.webkit.messageHandlers.xstvStatus.postMessage({
            event, seconds, captions, arabic
          });
        } catch(_) {}
      };
      const style = document.createElement('style');
      style.textContent = [
        '.xstv-cinema-container { position:fixed!important; inset:0!important;',
        'width:100vw!important; height:100dvh!important; max-height:none!important;',
        'max-width:none!important; z-index:2147483000!important;',
        'background:#000!important;transform:none!important;}',
        '.xstv-cinema-container video {width:100%!important;height:100%!important;',
        'max-width:100%!important;max-height:100%!important;object-fit:contain!important;}',
        'html.xstv-cinema-active, html.xstv-cinema-active body {',
        'background:#000!important;overflow:hidden!important;}'
      ].join('');
      let fullNode = null;
      function addCSS() {
        if(!style.isConnected) (document.head || document.documentElement).appendChild(style);
      }
      function findPlayer() {
        const v = document.querySelector('video');
        if (v) return v.closest('.jwplayer,.plyr,.video-js,.artplayer,.dplayer,[class*="player"],[id*="player"]')
                     || v.parentElement || v;
        return Array.from(document.querySelectorAll('iframe')).find(f =>
          f.getBoundingClientRect().width > 225 && f.getBoundingClientRect().height > 100
        ) || null;
      }
      function expand() {
        addCSS();
        let target=findPlayer();
        if (!target) return false;
        if(fullNode)fullNode.classList.remove('xstv-cinema-container');
        fullNode=target;
        target.classList.add('xstv-cinema-container');
        document.documentElement.classList.add('xstv-cinema-active');
        return true;
      }
      window.__xstvExpandCinema=expand;
      window.__xstvRestoreCinema=function(){
        if(fullNode)fullNode.classList.remove('xstv-cinema-container');
        fullNode=null;
        document.documentElement.classList.remove('xstv-cinema-active');
      };
      function applyTrackSelection(v) {
        let tracks=[];
        try { tracks=Array.from(v.textTracks||[]); } catch(_) {}
        let found=tracks.some(t=>/^(ar|ara|arabic)(-|$)/i.test(t.language||'') ||
            /arab|عرب/i.test(t.label||''));
        let showing=tracks.some(t=>t.mode==='showing');
        if(found && !showing) {
          const arabic=tracks.find(t=>/^(ar|ara|arabic)(-|$)/i.test(t.language||'') ||
              /arab|عرب/i.test(t.label||''));
          if(arabic) arabic.mode='showing';
        }
        if(tracks.length)emit('trackDetected',0,tracks.length,found);
      }
      function observe() {
        document.querySelectorAll('video').forEach(v=>{
          v.setAttribute('playsinline','');
          v.setAttribute('webkit-playsinline','');
          v.playsInline=true;
          if(v.__xstvAttached) return;
          v.__xstvAttached=true;
          applyTrackSelection(v);
          ['loadedmetadata','loadeddata','playing','timeupdate',
           'waiting','stalled','error'].forEach(name=>{
            v.addEventListener(name,()=>{
              let seconds=Number(v.currentTime)||0;
              if(name==='timeupdate' && seconds>0.15 || name==='playing' && seconds>0.15)
                emit('playback',seconds);
              else if(name==='waiting'||name==='stalled') emit('buffering',seconds);
              else if(name==='error')emit('error',seconds);
              else if(name==='loadedmetadata')applyTrackSelection(v);
            },{passive:true});
          });
        });
        if(document.querySelector('iframe'))emit('frame');
      }
      // Try to retain the site's own HTML controls/subtitle overlay when
      // fullscreen is pressed. If an iframe refuses DOM control, Safari is
      // still offered in the native UI.
      document.addEventListener('click',event=>{
        const btn=event.target.closest && event.target.closest('button,[role=button],a');
        if(!btn)return;
        const label=[btn.getAttribute('aria-label')||'', btn.title||'',
                     btn.textContent||''].join(' ');
        if(/full.?screen|ملء الشاشة|تكبير|expand/i.test(label)) {
          if(expand()) {
            event.preventDefault();
            event.stopImmediatePropagation();
          }
        }
      },true);

      // Deliberately do not synthesize clicks on unknown "Play" buttons:
      // iOS may reject them as non-user gestures, or they may be ads.
      function ready() {
        addCSS(); observe();
        const observer=new MutationObserver(observe);
        observer.observe(document.documentElement,{subtree:true,childList:true});
        setTimeout(observe,1800);setTimeout(observe,5000);
      }
      if(document.readyState==='loading')
        document.addEventListener('DOMContentLoaded',ready,{once:true});
      else ready();
    })();
    """#

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let monitor: XSWorldVideoMonitor
        let episode: Int?
        let season: Int?

        init(monitor: XSWorldVideoMonitor, episode: Int?, season: Int?) {
            self.monitor = monitor
            self.episode = episode
            self.season = season
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            monitor.message = "Opening provider player..."
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            monitor.pageLoaded = true
            monitor.message = "اختر Play من مشغل المصدر"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            monitor.message = "Website unavailable"
            monitor.unavailable = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            monitor.message = "Player page interrupted"
            monitor.unavailable = true
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "xstvStatus", let payload = message.body as? [String: Any] else {
                return
            }
            monitor.update(payload)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Suppress unsolicited popups rather than launching new tabs.
            return nil
        }
    }
}

private struct XSWorldSafariFallback: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ viewController: SFSafariViewController, context: Context) {}
}
