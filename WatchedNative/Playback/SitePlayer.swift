import SafariServices
import SwiftUI

@MainActor
enum SystemSafariPlayerFactory {
    static func make(url: URL) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        let browser = SFSafariViewController(url: url, configuration: configuration)
        browser.dismissButtonStyle = .close
        browser.overrideUserInterfaceStyle = .dark
        return browser
    }
}

/// The host presents Safari modally; Safari itself is never embedded as a child or obscured.
@MainActor
struct SafariPlayerPresenter: UIViewControllerRepresentable {
    @Binding var request: SitePlaybackRequest?
    let preview: Bool

    func makeUIViewController(context: Context) -> SafariPlaybackHost { SafariPlaybackHost() }
    func updateUIViewController(_ host: SafariPlaybackHost, context: Context) {
        let selection = $request
        host.update(request: request, preview: preview) { closedID in
            if selection.wrappedValue?.id == closedID { selection.wrappedValue = nil }
        }
    }
    static func dismantleUIViewController(_ host: SafariPlaybackHost, coordinator: ()) { host.cancel() }
}

@MainActor
final class SafariPlaybackHost: UIViewController, SFSafariViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
    private var currentID: UUID?
    private var pendingURL: URL?
    private var browser: SFSafariViewController?
    private var dismissing = false
    private var onClosed: ((UUID) -> Void)?
    #if DEBUG
    private var fixture: SafariPlaybackFixtureServer?
    #endif

    override func loadView() {
        let surface = UIView()
        surface.backgroundColor = .clear; surface.isUserInteractionEnabled = false
        view = surface
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); presentIfReady() }

    func update(request: SitePlaybackRequest?, preview: Bool, onClosed: @escaping (UUID) -> Void) {
        self.onClosed = onClosed
        guard let request else { if currentID != nil { cancel() }; return }
        guard currentID == nil else { return } // One presentation even after a rapid repeated tap.
        currentID = request.id
        #if DEBUG
        if preview {
            let server = SafariPlaybackFixtureServer()
            fixture = server
            server.start(target: request.url) { [weak self] url in
                guard let self, self.currentID == request.id else { return }
                guard let url else { self.finish(); return }
                self.pendingURL = url; self.presentIfReady()
            }
            return
        }
        #endif
        pendingURL = request.url
        presentIfReady()
    }

    private func presentIfReady() {
        guard isViewLoaded, view.window != nil, currentID != nil,
              browser == nil, presentedViewController == nil, let url = pendingURL else { return }
        pendingURL = nil
        let controller = SystemSafariPlayerFactory.make(url: url)
        browser = controller
        controller.delegate = self
        // Use Apple's normal modal presentation and visible system controls.
        present(controller, animated: true) { [weak self, weak controller] in
            controller?.presentationController?.delegate = self
        }
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        guard browser === controller, !dismissing else { return }
        dismissing = true
        // Keep the presentation and its delegate alive until UIKit finishes closing.
        controller.dismiss(animated: true) { [weak self] in self?.finish() }
    }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard presentationController.presentedViewController === browser else { return }
        finish()
    }

    private func finish() {
        guard let id = currentID else { return }
        browser?.delegate = nil; browser = nil; currentID = nil; pendingURL = nil; dismissing = false
        #if DEBUG
        fixture?.stop(); fixture = nil
        #endif
        let callback = onClosed
        onClosed = nil
        callback?(id)
    }

    func cancel() {
        let controller = browser
        browser = nil; currentID = nil; pendingURL = nil; onClosed = nil; dismissing = false
        controller?.delegate = nil
        controller?.dismiss(animated: false)
        #if DEBUG
        fixture?.stop(); fixture = nil
        #endif
    }
}
