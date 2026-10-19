"""V19: route the proven R5 interface to a Febbox-only catalog after the
legacy R5 build scripts have completed their mandatory compatibility checks.
The existing Sports player and IPTV integrations are deliberately untouched.
"""
from pathlib import Path

root = Path("FrameNative/Views/EnhancedRootView.swift")
assert root.exists(), "Missing XS TV root view"
original = root.read_text(encoding="utf-8")
assert 'XSCinematicHomeView(showSettings: $showSettings)' in original
assert 'XSSportsLiveViewV33()' in original
assert 'XSFebboxLibraryView()' in original

root.write_text(r'''import SwiftUI

// Febbox is the exclusive source of movies, series and search results.
// The AR Sports player remains independent and unchanged.
struct EnhancedRootView: View {
    @StateObject private var febbox = XSFebboxCatalogStore()
    @State private var selectedTab = 0
    @State private var showSplash = true

    var body: some View {
        ZStack {
            mainTabs
                .opacity(showSplash ? 0 : 1)

            if showSplash {
                V19FebboxSplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environmentObject(febbox)
        .task {
            febbox.startIfNeeded()
            try? await Task.sleep(nanoseconds: 280_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                showSplash = false
            }
        }
        .preferredColorScheme(.dark)
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                XSFebboxPremiumHomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                XSFebboxPremiumBrowseView(shelf: .movies)
            }
            .tabItem { Label("Movies", systemImage: "film.stack") }
            .tag(1)

            NavigationStack {
                XSFebboxPremiumBrowseView(shelf: .series)
            }
            .tabItem { Label("Series", systemImage: "play.tv") }
            .tag(2)

            NavigationStack {
                XSSportsLiveViewV33()
            }
            .tabItem { Label("الرياضة", systemImage: "sportscourt.fill") }
            .tag(3)
        }
        .tint(XSCinemaStyle.accent)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct V19FebboxSplashView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [Color.purple.opacity(0.20),
                                    Color.pink.opacity(0.11), .clear],
                           center: .center, startRadius: 10, endRadius: 320)
                .ignoresSafeArea()
            VStack(spacing: 13) {
                XSBrandMark(size: 140)
                XSWordmark()
                Text("POWERED BY FEBBOX")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2.4)
                    .foregroundStyle(.white.opacity(0.51))
            }
        }
    }
}
''', encoding="utf-8")
print("V19 applied: Febbox-primary native Home, Movies, Series, Search; R5 Sports preserved.")
