"""V22 runtime source separation: sports Xtream only, free/open cinema else.
Runs AFTER protected player tests; updates target compilation sources so the
former Xtream VOD, FrameXTV and Febbox screens cannot be opened at runtime.
"""
from pathlib import Path
root = Path("FrameNative/Views/EnhancedRootView.swift")
current = root.read_text(encoding="utf-8")
assert "XSSportsLiveViewV33()" in current
assert "XSVODHomeView()" in current

root.write_text(r'''import SwiftUI

struct EnhancedRootView: View {
    @StateObject private var cinema = XSOpenCinemaStore()
    @State private var activeTab = 0
    @State private var splash = true

    var body: some View {
        ZStack {
            mainTabs.opacity(splash ? 0 : 1)
            if splash {
                OpenCinemaSplash()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environmentObject(cinema)
        .task {
            Task { await cinema.start() }
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.easeOut(duration: 0.22)) { splash = false }
        }
        .preferredColorScheme(.dark)
    }

    private var mainTabs: some View {
        TabView(selection: $activeTab) {
            NavigationStack { XSOpenCinemaHomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { XSOpenCinemaBrowseView(shelf: .movies) }
                .tabItem { Label("Movies", systemImage: "film.stack") }
                .tag(1)

            NavigationStack { XSOpenCinemaBrowseView(shelf: .series) }
                .tabItem { Label("Series", systemImage: "play.tv") }
                .tag(2)

            NavigationStack { XSSportsLiveViewV33() }
                .tabItem { Label("الرياضة", systemImage: "sportscourt.fill") }
                .tag(3)
        }
        .tint(XSCinemaStyle.accent)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct OpenCinemaSplash: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [.purple.opacity(0.22), .pink.opacity(0.09), .clear],
                           center: .center, startRadius: 10, endRadius: 310)
                .ignoresSafeArea()
            VStack(spacing: 15) {
                XSBrandMark(size: 145)
                XSWordmark()
                Text("YOUR CINEMA. YOUR WORLD.")
                    .font(.caption2.bold()).tracking(2.1)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}
''', encoding="utf-8")

project = Path("project-native.yml")
text = project.read_text(encoding="utf-8")
anchor = "          - Views/XSFebboxPremiumCatalog.swift"
assert anchor in text
text = text.replace(anchor, anchor + """
          - Views/XSVODPremiumExperience.swift
          - Services/XSVODService.swift
          - Services/XSVODRedirectResolver.swift""")
project.write_text(text, encoding="utf-8")
print("Open Cinema V22 active: no IPTV VOD or old website screens; protected sports only.")
