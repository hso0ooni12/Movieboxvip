"""Switch runtime movie/series tabs to original ETWatch website player.

The provider owns its playback UI, quality and subtitle controls.
No media extraction, download, video URL interception or catalog mirroring.
R5 Sports VLC and private IPTV channel-only credentials are preserved.
"""
from pathlib import Path

root = Path("FrameNative/Views/EnhancedRootView.swift")
source = root.read_text(encoding="utf-8")
assert "XSSportsLiveViewV33()" in source
root.write_text(r'''import SwiftUI

struct EnhancedRootView: View {
    @State private var selectedTab = 0
    @State private var showSplash = true

    var body: some View {
        ZStack {
            tabs.opacity(showSplash ? 0 : 1)
            if showSplash {
                XSETWatchSplash()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeOut(duration: 0.2)) { showSplash = false }
        }
        .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { XSETWatchPortalView(section: .home) }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { XSETWatchPortalView(section: .movies) }
                .tabItem { Label("Movies", systemImage: "film.stack") }
                .tag(1)

            NavigationStack { XSETWatchPortalView(section: .series) }
                .tabItem { Label("Series", systemImage: "play.tv") }
                .tag(2)

            NavigationStack { XSSportsLiveViewV33() }
                .tabItem { Label("الرياضة", systemImage: "sportscourt.fill") }
                .tag(3)
        }
        .tint(XSCinemaStyle.accent)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct XSETWatchSplash: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [.purple.opacity(0.24), .pink.opacity(0.10), .clear],
                           center: .center, startRadius: 10, endRadius: 330)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                XSBrandMark(size: 126)
                XSWordmark()
                Text("ENTERTAINMENT. REIMAGINED.")
                    .font(.caption2.bold())
                    .tracking(2.0)
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
    }
}
''',encoding="utf-8")

project=Path("project-native.yml")
spec=project.read_text(encoding="utf-8")
anchor="          - Views/XSFebboxPremiumCatalog.swift"
assert anchor in spec
spec=spec.replace(anchor,anchor + """
          - Views/XSVODPremiumExperience.swift
          - Views/XSVODVLCPlayerView.swift
          - Services/XSVODService.swift
          - Services/XSVODRedirectResolver.swift""")
project.write_text(spec,encoding="utf-8")
print("ETWatch original-site movie/series WKWebView active. IPTV exclusively for R5 Sports.")
