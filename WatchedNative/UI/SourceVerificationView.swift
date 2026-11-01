import Foundation
import SwiftUI
import WebKit

/// WebKit is confined to an explicit, user-controlled first-party security check.
/// The catalogue and film/episode playback never use this view.
@MainActor
final class SourceVerificationModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var loading = true
    @Published var syncing = false
    @Published var message: String?
    private var started = false
    private let home = URL(string: "https://watched.cx/home")!

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsInlineMediaPlayback = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
    }

    func start() {
        guard !started else { return }
        started = true
        webView.load(URLRequest(url: home))
    }

    func syncCompletedVerification() async -> Bool {
        guard !syncing else { return false }
        syncing = true; message = nil
        defer { syncing = false }
        let cookies: [HTTPCookie] = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
        guard !Task.isCancelled else { return false }
        let sourceCookies = cookies.filter { SourceCookiePolicy.isFirstParty(domain: $0.domain) }
        let now = Date().timeIntervalSince1970
        // This marker is the one read by the supplied site's own clearance script.
        // The real server still validates its own accompanying cookie on the next request.
        guard sourceCookies.contains(where: { $0.name == "wvc_until" && (Double($0.value) ?? 0) > now }) else {
            message = "أكمل التحقق الظاهر في صفحة المصدر أولاً، ثم اضغط الزر مرة ثانية."
            return false
        }
        await WatchedClient.shared.acceptVerifiedSourceCookies(sourceCookies)
        return true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    private func fail(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; message = error.localizedDescription
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank", navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard url.scheme == "https" else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame == false {
            let allowed = SourceCookiePolicy.isFirstParty(domain: url.host ?? "") || url.host == "challenges.cloudflare.com"
            decisionHandler(allowed ? .allow : .cancel); return
        }
        // Keep this sheet on the verification/home page, with no web film player or external windows.
        guard navigationAction.targetFrame != nil, url.host == "watched.cx", ["/", "/home"].contains(url.path) else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
}

private struct VerificationWebSurface: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

struct SourceVerificationView: View {
    let onVerified: () -> Void
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = SourceVerificationModel()
    @State private var syncTask: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(store.t("أكمل تحقق الأمان من watched.cx، ثم ارجع للتشغيل. الفيديو سيُفتح بالمشغّل النيتف.", "Complete watched.cx’s security check, then return. Video will play in the native player."))
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                ZStack(alignment: .top) {
                    if store.isPreview {
                        EmptyMessage(symbol: "lock.shield", title: store.t("تحقق المصدر", "Source verification"), message: store.t("معاينة واجهة التحقق فقط · لا يوجد اتصال بالموقع في هذا الاختبار", "Verification UI preview only · This test does not contact the site"))
                    } else { VerificationWebSurface(webView: model.webView) }
                    if model.loading { ProgressView().padding(14).background(.ultraThinMaterial, in: Capsule()).padding(.top, 10) }
                }
                if let message = model.message { Text(message).font(.footnote).foregroundStyle(WatchedTheme.accent).padding(.horizontal, 16).padding(.top, 12) }
                Button {
                    syncTask = Task {
                        if await model.syncCompletedVerification(), !Task.isCancelled { onVerified() }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if model.syncing { ProgressView().tint(.black) }
                        Text(store.t("تم التحقق، رجوع للتشغيل", "Verification done · Return to video"))
                    }
                }.buttonStyle(PrimaryAction()).disabled(model.syncing || store.isPreview).padding(16).accessibilityIdentifier("source-verification-complete")
            }
            .background(WatchedTheme.background)
            .navigationTitle(store.t("تحقق المصدر", "Source verification"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(store.t("إلغاء", "Cancel")) { dismiss() } } }
            .task { if store.isPreview { model.loading = false } else { model.start() } }
            .onDisappear { syncTask?.cancel(); model.webView.stopLoading() }
        }
    }
}
