import Combine
import Network
import SafariServices
import UIKit
import WebKit

@MainActor
final class BrowserModel: ObservableObject {
    @Published private(set) var currentURL: URL?
    @Published private(set) var pageTitle = ""
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var isConnected = true
    @Published private(set) var hasLoadedContent = false
    @Published private(set) var blockingErrorMessage: String?

    weak var webView: WKWebView?

    private let configuration = AppConfiguration.shared
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "StreamWeb.NetworkMonitor")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied

                if self.isConnected,
                   self.blockingErrorMessage != nil,
                   !self.hasLoadedContent {
                    self.retry()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        currentURL = webView.url
        updateNavigationState()
    }

    func loadInitialPageIfNeeded() {
        guard let webView, webView.url == nil else { return }
        load(configuration.homeURL)
    }

    func load(_ url: URL) {
        guard let webView else { return }
        blockingErrorMessage = nil

        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 30
        webView.load(request)
    }

    func goHome() {
        load(configuration.homeURL)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        blockingErrorMessage = nil
        if webView?.url == nil {
            goHome()
        } else {
            webView?.reload()
        }
    }

    func retry() {
        blockingErrorMessage = nil
        reload()
    }

    func stopLoading() {
        webView?.stopLoading()
    }

    func openCurrentPageInSafari() {
        let url = currentURL ?? configuration.homeURL
        UIApplication.shared.open(url)
    }

    func updateFromWebView(_ webView: WKWebView) {
        currentURL = webView.url
        pageTitle = webView.title ?? configuration.appName
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
    }

    func navigationDidFinish(_ webView: WKWebView) {
        hasLoadedContent = true
        blockingErrorMessage = nil
        updateFromWebView(webView)
    }

    func navigationDidFail(_ error: Error, webView: WKWebView) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }

        updateFromWebView(webView)
        if !hasLoadedContent {
            blockingErrorMessage = isConnected
                ? error.localizedDescription
                : String(localized: "No internet connection")
        }
    }

    private func updateNavigationState() {
        guard let webView else { return }
        updateFromWebView(webView)
    }
}
