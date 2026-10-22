import SwiftUI
import WebKit
import SafariServices

/// Opens an individual ETWatch detail page, never embeds the website's
/// Home/Movies navigation into the native XS TV interface. Playback remains
/// completely owned by the website: no token interception or HLS extraction.
struct XSETWatchNativeDetailPlayer: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var state = XSETWatchPlaybackHealth()
    @State private var presentSafari = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
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
                    Button { presentSafari = true } label: {
                        Image(systemName: "safari")
                            .frame(width: 42, height: 42)
                    }
                    .accessibilityLabel("فتح في Safari")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)

                XSETWatchVideoWebView(url: url, state: state)
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

    func reload() {
        playbackSeen = false
        stalled = false
        siteError = nil
        subtitle = "إعادة الاتصال بالمشغل…"
        web?.reload()
        beginWatch()
    }

    func notePlayer(_ event: String, time: Double) {
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

    func makeCoordinator() -> Coordinator { Coordinator(state: state) }

    func makeUIView(context: Context) -> WKWebView {
        let userContent = WKUserContentController()
        let script = """
        (function() {
          if (window.__xstvVideoProbeReady) return;
          window.__xstvVideoProbeReady=true;
          function attach() {
            Array.from(document.querySelectorAll('video')).forEach(function(video) {
              if (video.__xstvObserved) return;
              video.__xstvObserved = true;
              ['playing','timeupdate','waiting','stalled','error','loadedmetadata'].forEach(function(event) {
                video.addEventListener(event, function(){
                  try {
                    window.webkit.messageHandlers.xstvVideoStatus.postMessage({
                      event:event, seconds:Number(video.currentTime)||0
                    });
                  } catch(e) {}
                }, {passive:true});
              });
            });
          }
          new MutationObserver(attach).observe(document.documentElement,{childList:true,subtree:true});
          attach();
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
        init(state: XSETWatchPlaybackHealth) { self.state = state }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.pageLoaded = false
            state.subtitle = "جاري فتح صفحة المشاهدة…"
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.pageLoaded = true
            state.subtitle = "اختر تشغيل الفيديو من صفحة الموقع"
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
