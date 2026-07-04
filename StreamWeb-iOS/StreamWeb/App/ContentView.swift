import SwiftUI

struct ContentView: View {
    @StateObject private var browser = BrowserModel()
    @State private var isSharePresented = false

    private let configuration = AppConfiguration.shared

    var body: some View {
        ZStack {
            BrowserWebView(model: browser, configuration: configuration)
                .ignoresSafeArea(edges: .bottom)

            if let message = browser.blockingErrorMessage {
                ErrorStateView(message: message) {
                    browser.retry()
                }
                .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 0) {
                if browser.isLoading {
                    ProgressView(value: max(browser.progress, 0.04))
                        .progressViewStyle(.linear)
                        .tint(configuration.accentColor)
                }

                if !browser.isConnected && browser.hasLoadedContent {
                    OfflineBanner()
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BrowserToolbar(
                browser: browser,
                accentColor: configuration.accentColor,
                onShare: { isSharePresented = true },
                onOpenInSafari: browser.openCurrentPageInSafari
            )
        }
        .sheet(isPresented: $isSharePresented) {
            ActivityView(activityItems: [browser.currentURL ?? configuration.homeURL])
                .presentationDetents([.medium, .large])
        }
        .animation(.easeInOut(duration: 0.2), value: browser.blockingErrorMessage)
        .onOpenURL { url in
            browser.load(url)
        }
    }
}

private struct BrowserToolbar: View {
    @ObservedObject var browser: BrowserModel
    let accentColor: Color
    let onShare: () -> Void
    let onOpenInSafari: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ToolbarButton(systemName: "chevron.backward", accessibilityKey: "Back") {
                browser.goBack()
            }
            .disabled(!browser.canGoBack)

            ToolbarButton(systemName: "chevron.forward", accessibilityKey: "Forward") {
                browser.goForward()
            }
            .disabled(!browser.canGoForward)

            ToolbarButton(systemName: "house.fill", accessibilityKey: "Home") {
                browser.goHome()
            }

            ToolbarButton(
                systemName: browser.isLoading ? "xmark" : "arrow.clockwise",
                accessibilityKey: browser.isLoading ? "Stop" : "Reload"
            ) {
                browser.isLoading ? browser.stopLoading() : browser.reload()
            }

            ToolbarButton(systemName: "square.and.arrow.up", accessibilityKey: "Share", action: onShare)

            ToolbarButton(systemName: "safari", accessibilityKey: "Open in Safari", action: onOpenInSafari)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
        .tint(accentColor)
    }
}

private struct ToolbarButton: View {
    let systemName: String
    let accessibilityKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityKey)
    }
}

private struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline banner")
                .font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(.thinMaterial)
    }
}

private struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 7) {
                Text("Unable to load")
                    .font(.title3.bold())
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }

            Button(action: retry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(24)
    }
}

#Preview {
    ContentView()
}
