import SwiftUI
import UIKit
import WebKit

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel
    let configuration: AppConfiguration

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model, configuration: configuration)
    }

    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        preferences.preferredContentMode = .mobile

        let userContentController = WKUserContentController()
        AdBlocker.addCosmeticFilters(
            to: userContentController,
            enabled: configuration.adBlockingEnabled
        )

        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.userContentController = userContentController
        webConfiguration.defaultWebpagePreferences = preferences
        webConfiguration.websiteDataStore = .default()
        webConfiguration.allowsAirPlayForMediaPlayback = true
        webConfiguration.allowsInlineMediaPlayback = true
        webConfiguration.allowsPictureInPictureMediaPlayback = true
        webConfiguration.mediaTypesRequiringUserActionForPlayback = []
        webConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let webView = WKWebView(frame: .zero, configuration: webConfiguration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(context.coordinator, action: #selector(Coordinator.refresh(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        context.coordinator.observe(webView)
        context.coordinator.prepare(webView)

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        model.updateFromWebView(webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: BrowserModel
        private let configuration: AppConfiguration
        private var observations: [NSKeyValueObservation] = []

        init(model: BrowserModel, configuration: AppConfiguration) {
            self.model = model
            self.configuration = configuration
        }

        func prepare(_ webView: WKWebView) {
            model.attach(webView)

            AdBlocker.installNetworkRules(
                into: webView.configuration.userContentController,
                enabled: configuration.adBlockingEnabled
            ) { [weak self] in
                self?.model.loadInitialPageIfNeeded()
            }
        }

        func observe(_ webView: WKWebView) {
            observations = [
                webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                    Task { @MainActor in self?.model.updateFromWebView(webView) }
                },
                webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                    Task { @MainActor in self?.model.updateFromWebView(webView) }
                },
                webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                    Task { @MainActor in self?.model.updateFromWebView(webView) }
                },
                webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                    Task { @MainActor in self?.model.updateFromWebView(webView) }
                },
                webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                    Task { @MainActor in self?.model.updateFromWebView(webView) }
                }
            ]
        }

        func stopObserving() {
            observations.removeAll()
        }

        @objc func refresh(_ sender: UIRefreshControl) {
            model.reload()
            sender.endRefreshing()
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            model.updateFromWebView(webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            model.updateFromWebView(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.navigationDidFinish(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.navigationDidFail(error, webView: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            webView.scrollView.refreshControl?.endRefreshing()
            model.navigationDidFail(error, webView: webView)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""

            if configuration.adBlockingEnabled,
               AdBlocker.shouldBlockNavigation(to: url) {
                decisionHandler(.cancel)
                return
            }

            if ["tel", "mailto", "sms", "facetime", "facetime-audio"].contains(scheme) {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            guard ["http", "https", "about", "blob", "data"].contains(scheme) else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            if configuration.opensExternalHostsInSafari,
               configuration.isExternal(url),
               navigationAction.navigationType == .linkActivated {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            if navigationAction.targetFrame == nil {
                let isScriptedExternalPopup = configuration.adBlockingEnabled
                    && configuration.isExternal(url)
                    && navigationAction.navigationType != .linkActivated

                if isScriptedExternalPopup {
                    decisionHandler(.cancel)
                    return
                }

                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }

            if self.configuration.adBlockingEnabled,
               AdBlocker.shouldBlockNavigation(to: url) {
                return nil
            }

            let isScriptedExternalPopup = self.configuration.adBlockingEnabled
                && self.configuration.isExternal(url)
                && navigationAction.navigationType != .linkActivated

            guard !isScriptedExternalPopup else { return nil }

            webView.load(URLRequest(url: url))
            return nil
        }
    }
}
