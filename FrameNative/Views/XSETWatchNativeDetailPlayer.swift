import SwiftUI
import WebKit
import SafariServices

/// Opens an individual ETWatch detail page, never embeds the website's
/// Home/Movies navigation into the native XS TV interface. Playback remains
/// completely owned by the website: no token interception or HLS extraction.
struct XSETWatchNativeDetailPlayer: View {
    let url: URL
    let title: String
    var season: Int? = nil
    var episode: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = XSETWatchPlaybackHealth()
    @State private var presentSafari = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if !state.theaterMode {
                HStack(spacing: 13) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .frame(width: 43, height: 42)
                            .background(.white.opacity(0.11), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.subheadline.bold()).lineLimit(1)
                        Text(state.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button { state.reload() } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 42, height: 42)
                    }
                    Button { state.toggleTheater() } label: {
                        Image(systemName: state.theaterMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .frame(width: 42, height: 42)
                    }
                    .accessibilityLabel("وضع سينمائي يحافظ على الترجمة")
                    Button { presentSafari = true } label: {
                        Image(systemName: "safari")
                            .frame(width: 42, height: 42)
                    }
                    .accessibilityLabel("فتح في Safari")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

                }
                XSETWatchVideoWebView(url: url, state: state, season: season, episode: episode)
                    .background(.black)
                    .overlay(alignment: .bottom) {
                        if state.stalled {
                            VStack(alignment: .leading, spacing: 11) {
                                Label("تعليق في تشغيل الفيديو", systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.yellow)
                                Text("صفحة المصدر فتحت، لكن ما وصلنا تأكيد أن الفيديو بدأ. قد يكون السيرفر أو الاتصال بالمشغل محجوباً على هذه الشبكة.")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.78))
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 8) {
                                    Button {
                                        state.reload()
                                    } label: {
                                        Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                                            .frame(maxWidth: .infinity, minHeight: 39)
                                    }
                                    .buttonStyle(.bordered)
                                    Button {
                                        presentSafari = true
                                    } label: {
                                        Label("Safari", systemImage: "safari")
                                            .frame(maxWidth: .infinity, minHeight: 39)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                                .tint(Color(red: 1.0, green: 0.29, blue: 0.40))
                                Button("نسخ تقرير التشخيص") {
                                    UIPasteboard.general.string = state.safeDiagnostic
                                }
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.65))
                            }
                            .padding(18)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 22)
                        }
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if state.theaterMode {
                Button {
                    state.toggleTheater()
                } label: {
                    Label("تصغير", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 11)
                        .background(.black.opacity(0.78), in: Capsule())
                }
                .padding(.trailing, 11)
                .padding(.top, 4)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $presentSafari) {
            XSETWatchSafariFallback(url: url)
                .ignoresSafeArea()
        }
        .onAppear { state.beginWatch() }
        .onDisappear { state.endWatch() }
    }
}

@MainActor
final class XSETWatchPlaybackHealth: ObservableObject {
    @Published var subtitle = "مشغل الموقع الأصلي"
    @Published var stalled = false
    @Published var pageLoaded = false
    @Published var theaterMode = false
    @Published var autoPlayAttempted = false
    @Published var playbackSeen = false
    @Published var siteError: String?
    weak var web: WKWebView?
    private var timeout: Task<Void, Never>?
    private var generation = 0

    var safeDiagnostic: String {
        "XS TV ETWatch playback | pageLoaded=\(pageLoaded) | playbackDetected=\(playbackSeen) | stalled=\(stalled) | diagnostic=\(siteError ?? "none") | iOS WebKit"
    }

    func beginWatch() {
        generation += 1
        let active = generation
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !Task.isCancelled, let self, active == self.generation,
                  !self.playbackSeen else { return }
            self.stalled = true
            self.subtitle = "لم يبدأ تشغيل الفيديو"
        }
    }

    func endWatch() {
        generation += 1
        timeout?.cancel()
    }

    func toggleTheater() {
        theaterMode.toggle()
        web?.evaluateJavaScript(theaterMode
            ? "window.__xstvEnterTheater && window.__xstvEnterTheater();"
            : "window.__xstvExitTheater && window.__xstvExitTheater();",
            completionHandler: nil)
    }

    func reload() {
        playbackSeen = false
        stalled = false
        siteError = nil
        subtitle = "إعادة الاتصال بالمشغل…"
        web?.reload()
        beginWatch()
    }

    func notePlayer(_ event: String, time: Double) {
        if event == "autoplayAttempted" { autoPlayAttempted = true; subtitle = "محاولة فتح مشغل الفيديو مباشرة…"; return }
        if event == "theaterStarted" { theaterMode = true; return }
        if event == "theaterStopped" { theaterMode = false; return }
        guard !playbackSeen else { return }
        if (event == "playing" || event == "timeupdate") && time > 0.15 {
            playbackSeen = true
            stalled = false
            subtitle = "الفيديو قيد التشغيل"
            timeout?.cancel()
        } else if event == "error" {
            siteError = "html_video_error"
            subtitle = "حدث خطأ في مشغل الفيديو"
            stalled = true
        } else if event == "waiting" || event == "stalled" {
            subtitle = "المشغل ينتظر وصول بيانات الفيديو…"
        } else if event == "loadedmetadata" {
            subtitle = "تم العثور على بيانات الفيديو"
        }
    }
}

private struct XSETWatchVideoWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: XSETWatchPlaybackHealth
    let season: Int?
    let episode: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, season: season, episode: episode)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        let desiredEpisode = episode.map(String.init) ?? "null"
        let desiredSeason = season.map(String.init) ?? "null"
        let script = """
        (function() {
          if (window.__xstvVideoProbeReady) return;
          window.__xstvVideoProbeReady = true;
          const desiredSeason = \(desiredSeason);
          const desiredEpisode = \(desiredEpisode);
          const post = function(event, seconds) {
            try { window.webkit.messageHandlers.xstvVideoStatus.postMessage({
              event: event, seconds: Number(seconds)||0
            }); } catch(e) {}
          };
          const css = document.createElement("style");
          css.textContent =
            '.xstv-theater-player{position:fixed!important;inset:0!important;z-index:2147483000!important;width:100vw!important;height:100dvh!important;background:#000!important;max-width:none!important;max-height:none!important;transform:none!important;}' +
            '.xstv-theater-player video{max-height:100%!important;max-width:100%!important;width:100%!important;height:100%!important;object-fit:contain!important;}' +
            'html.xstv-cinema-on,html.xstv-cinema-on body{overflow:hidden!important;background:#000!important;}';
          (document.head || document.documentElement).appendChild(css);
          let activeContainer = null;
          function candidate() {
            const video = Array.from(document.querySelectorAll("video"))
              .find(v => v.readyState > 0 || v.clientWidth > 100) ||
              document.querySelector("video");
            if (video) {
              return video.closest('.jwplayer,.plyr,.video-js,.artplayer,.dplayer,[class*="player-container"],[class*="video-player"]')
                || video.parentElement;
            }
            return Array.from(document.querySelectorAll('iframe[allow*="fullscreen"],iframe[src]'))
              .find(el=>el.clientWidth>240 && el.clientHeight>100) || null;
          }
          window.__xstvEnterTheater = function() {
            const target = candidate();
            if (!target) return false;
            if (activeContainer && activeContainer!==target) activeContainer.classList.remove("xstv-theater-player");
            activeContainer=target;
            target.classList.add("xstv-theater-player");
            document.documentElement.classList.add("xstv-cinema-on");
            post("theaterStarted",0);
            return true;
          };
          window.__xstvExitTheater = function() {
            if(activeContainer) activeContainer.classList.remove("xstv-theater-player");
            document.documentElement.classList.remove("xstv-cinema-on");
            activeContainer=null;
            post("theaterStopped",0);
            return true;
          };
          function observeVideo() {
            document.querySelectorAll('video').forEach(function(v) {
              v.setAttribute("playsinline","");
              v.setAttribute("webkit-playsinline","");
              v.playsInline=true;
              if (v.__xstvObserved) return;
              v.__xstvObserved=true;
              ['playing','timeupdate','waiting','stalled','error','loadedmetadata'].forEach(function(event) {
                v.addEventListener(event,function(){
                  const seconds=Number(v.currentTime)||0;
                  post(event,seconds);
                  if ((event==="playing" || event==="timeupdate") && seconds>0.2) {
                    if(window.top===window)window.__xstvEnterTheater();
                    else window.parent.postMessage({type:"xstv-player-played"},"*");
                  }
                },{passive:true});
              });
            });
          }
          // The site's player may render its Arabic subtitles as an HTML layer,
          // outside <video>. Keep both in the same WKWebView visual hierarchy.
          window.addEventListener("message",function(e){
            if(e.data && e.data.type==="xstv-player-played"){
              if(window.top===window)window.__xstvEnterTheater();
              else window.parent.postMessage({type:"xstv-player-played"},"*");
            }
          });
          document.addEventListener("click",function(e) {
            const btn=e.target.closest && e.target.closest('button,[role="button"],a');
            if(!btn || !document.querySelector("video"))return;
            const label=((btn.getAttribute("aria-label")||"")+" "+(btn.title||"")+" "+(btn.className||"")+" "+(btn.innerText||"")).trim();
            if (/fullscreen|full.screen|ملء الشاشة|تكبير/i.test(label)) {
              const ok=window.__xstvEnterTheater();
              if(ok){e.preventDefault();e.stopImmediatePropagation();}
            }
          },true);
          let autoClicked = false;
          let episodeChosen = false;
          let count=0;
          function selectEpisodeIfVisible() {
            if(desiredEpisode===null || episodeChosen || window.top!==window)return false;
            const candidates=Array.from(document.querySelectorAll(
              '[data-episode], [class*="pisode"], button, a, [role="button"]'
            )).filter(el=>el.getBoundingClientRect().width>40);
            const target=candidates.find(el=>{
              const data=el.getAttribute("data-episode");
              if(data!==null && Number(data)===desiredEpisode)return true;
              const label=(el.getAttribute("aria-label")||"")+" "+(el.innerText||"");
              const compact=label.trim();
              return new RegExp("^E\\\\s*"+desiredEpisode+"(?:\\\\b|\\\\s)", "i").test(compact)
                || new RegExp("^Episode\\\\s*"+desiredEpisode+"(?:\\\\b|\\\\s)", "i").test(compact)
                || new RegExp("^حلقة\\\\s*"+desiredEpisode+"(?:\\\\b|\\\\s)").test(compact);
            });
            if(!target)return false;
            episodeChosen=true;
            autoClicked=true;
            post("autoplayAttempted",0);
            target.click();
            return true;
          }
          function findPlay() {
            if(autoClicked || window.top!==window)return;
            if(desiredEpisode!==null){
              selectEpisodeIfVisible();
              return;
            }
            if(document.querySelector('video[src],video source[src]'))return;
            const elements=Array.from(document.querySelectorAll("button,a,[role=button]"));
            const play=elements.find(el=>{
              const rect=el.getBoundingClientRect();
              if(rect.width<24 || rect.height<20)return false;
              const label=((el.getAttribute("aria-label")||"")+" "+(el.textContent||"")).trim().toLowerCase();
              return /^(play|watch now|watch|شاهد الآن|تشغيل|ابدأ المشاهدة)(\\s|$)/i.test(label)
                 && !/trailer|preview|اعلان/.test(label);
            });
            if(play){
              autoClicked=true;
              post("autoplayAttempted",0);
              play.click();
            }
          }
          const observer=new MutationObserver(function(){observeVideo();});
          observer.observe(document.documentElement,{childList:true,subtree:true});
          observeVideo();
          if(window.top===window){
            const timer=setInterval(function(){
              count++;findPlay();
              if(autoClicked||count>30)clearInterval(timer);
            },400);
          }
          window.addEventListener("pagehide",function(){observer.disconnect();});
        })();
        """
        userContent.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd,
                                             forMainFrameOnly: false))
        userContent.add(context.coordinator, name: "xstvVideoStatus")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.userContentController = userContent
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = context.coordinator
        browser.uiDelegate = context.coordinator
        browser.isOpaque = false
        browser.backgroundColor = .black
        browser.scrollView.backgroundColor = .black
        state.web = browser
        browser.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy,
                                timeoutInterval: 25))
        return browser
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: "xstvVideoStatus")
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let state: XSETWatchPlaybackHealth
        let season: Int?
        let episode: Int?
        init(state: XSETWatchPlaybackHealth, season: Int?, episode: Int?) {
            self.state = state
            self.season = season
            self.episode = episode
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.pageLoaded = false
            state.subtitle = "جاري فتح صفحة المشاهدة…"
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.pageLoaded = true
            state.subtitle = state.autoPlayAttempted
                ? "جارٍ توصيل مشغل الفيديو الأصلي…"
                : "المشغل جاهز، وسيتم محاولة بدء الفيديو تلقائياً"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            state.siteError = "navigation_failed"
            state.stalled = true
            state.subtitle = "فشل فتح صفحة المشاهدة"
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            state.siteError = "navigation_interrupted"
            state.stalled = true
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "xstvVideoStatus",
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            let time = (body["seconds"] as? NSNumber)?.doubleValue ?? 0
            state.notePlayer(event,time:time)
        }

        // Open legitimate same-frame site navigation, not unsolicited new
        // windows; provider popups remain external and under user's control.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard navigationAction.targetFrame == nil,
                  navigationAction.navigationType == .linkActivated,
                  let target = navigationAction.request.url,
                  target.scheme == "https" else { return nil }
            UIApplication.shared.open(target)
            return nil
        }
    }
}

private struct XSETWatchSafariFallback: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ viewController: SFSafariViewController, context: Context) {}
}
