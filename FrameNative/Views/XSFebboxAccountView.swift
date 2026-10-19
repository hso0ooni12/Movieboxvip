import SwiftUI
import WebKit

// Febbox authentication is isolated to the app and its own WebKit cookie store.
// The video catalog remains a native SwiftUI experience. No account secrets
// or cookie values are included in source, GitHub build logs, or the IPA.
struct XSFebboxAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isSignedIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("تسجيل الدخول إلى Febbox")
                        .font(.headline)
                    Text("سجّل الدخول من موقع Febbox الرسمي لمرة واحدة. الجلسة تبقى داخل التطبيق ولا نطلب منك نسخ أي رمز أو كلمة مرور.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if isSignedIn {
                        Label("تم اكتشاف جلسة Febbox. ارجع للحلقة لإعادة محاولة التشغيل.",
                              systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)

                XSFebboxAuthenticationBrowser { found in
                    isSignedIn = found
                }
                .background(Color.white)
            }
            .navigationTitle("حساب Febbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isSignedIn ? "متابعة" : "إغلاق") { dismiss() }
                }
            }
        }
        .task {
            isSignedIn = await XSFebboxLibraryService.shared.hasAccountSession()
        }
    }
}

private struct XSFebboxAuthenticationBrowser: UIViewRepresentable {
    let sessionChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionChanged: sessionChanged)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.navigationDelegate = context.coordinator
        browser.uiDelegate = context.coordinator
        browser.allowsBackForwardNavigationGestures = true
        browser.load(URLRequest(url: URL(string: "https://www.febbox.com")!))
        context.coordinator.checkSession()
        return browser
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let sessionChanged: (Bool) -> Void

        init(sessionChanged: @escaping (Bool) -> Void) {
            self.sessionChanged = sessionChanged
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkSession()
        }

        func checkSession() {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
                let found = cookies.contains {
                    let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                    return (domain == "febbox.com" || domain.hasSuffix(".febbox.com"))
                        && $0.name == "ui" && !$0.value.isEmpty
                }
                DispatchQueue.main.async { self?.sessionChanged(found) }
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Febbox's own login pages may open in a separate window; retain
            // them in the same in-app session, without intercepting credentials.
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
