"""Run only after protected R5/V39 QA: replace the movie/series UI
with subscribed Xtream VOD, preserving the live Sports VLC backend.
"""
from pathlib import Path

path = Path("FrameNative/Views/EnhancedRootView.swift")
root = path.read_text(encoding="utf-8")
assert "XSSportsLiveViewV33()" in root, "Protected sports tab unavailable"

path.write_text(r'''import SwiftUI

// All movie and series browsing/playback is Xtream VOD from the user's
// already configured provider. The unrelated live Sports stack is retained.
struct EnhancedRootView: View {
    @StateObject private var vod = XSVODCatalogStore()
    @State private var activeTab = 0
    @State private var splashVisible = true

    var body: some View {
        ZStack {
            mainTabs.opacity(splashVisible ? 0 : 1)
            if splashVisible {
                XSVODPremiumSplash()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environmentObject(vod)
        .task {
            async let loading: Void = vod.load()
            try? await Task.sleep(nanoseconds: 330_000_000)
            withAnimation(.easeOut(duration: 0.25)) { splashVisible = false }
            _ = await loading
        }
        .preferredColorScheme(.dark)
    }

    private var mainTabs: some View {
        TabView(selection: $activeTab) {
            NavigationStack {
                XSVODHomeView()
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                XSVODBrowseView(kind: .movie)
            }
            .tabItem { Label("Movies", systemImage: "film.stack") }
            .tag(1)

            NavigationStack {
                XSVODBrowseView(kind: .series)
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
        .toolbarBackground(XSCinemaStyle.background.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct XSVODPremiumSplash: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [.purple.opacity(0.24), .pink.opacity(0.12), .clear],
                           center: .center, startRadius: 10, endRadius: 330)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                XSBrandMark(size: 138)
                XSWordmark()
                Text("ENTERTAINMENT. REIMAGINED.")
                    .font(.caption2.bold())
                    .tracking(2.1)
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
    }
}
''', encoding="utf-8")
print("V20: subscribed VOD is exclusive movie/series provider; sports kept unchanged.")
