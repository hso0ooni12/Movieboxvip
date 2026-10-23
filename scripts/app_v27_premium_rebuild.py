"""Switch to V27 cinematic UI and disconnect superseded V24 components.

Runs after old baseline regression gates, before Swift parse and XcodeGen.
The user-facing application has only four tabs. The sports module and
pre-existing video engines remain unchanged and isolated from UI.
"""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift")
existing=root.read_text(encoding="utf-8")
assert "XSSportsLiveViewV33()" in existing
assert "XSCinemaNativeHomeView()" in existing
root.write_text(r'''import SwiftUI

struct EnhancedRootView: View {
    @StateObject private var library = XSCinemaNativeStore()
    @State private var selection = 0
    @State private var splash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            tabs.opacity(splash ? 0 : 1)
            if splash {
                XSPremiumSplashV27()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .environmentObject(library)
        .task {
            Task { await library.boot() }
            try? await Task.sleep(nanoseconds: 440_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                splash = false
            }
        }
        .preferredColorScheme(.dark)
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            NavigationStack { XSPremiumCinemaHome() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

            NavigationStack { XSPremiumBrowse(kind: .movie) }
                .tabItem { Label("Movies", systemImage: "film.stack.fill") }
                .tag(1)

            NavigationStack { XSPremiumBrowse(kind: .series) }
                .tabItem { Label("Series", systemImage: "play.tv.fill") }
                .tag(2)

            NavigationStack { XSSportsLiveViewV33() }
                .tabItem { Label("Sports", systemImage: "sportscourt.fill") }
                .tag(3)
        }
        .tint(XSCinemaStyle.accent)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct XSPremiumSplashV27: View {
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [
                Color(red: 0.60, green: 0.16, blue: 0.42).opacity(0.30),
                .purple.opacity(0.08), .clear
            ], center: .center, startRadius: 1, endRadius: 290)
            .ignoresSafeArea()

            VStack(spacing: 18) {
                XSBrandMark(size: 143)
                    .scaleEffect(animate ? 1.0 : 0.89)
                XSWordmark()
                Text("ENTERTAINMENT, REIMAGINED")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.3)
                    .foregroundStyle(.white.opacity(0.50))
            }
            .opacity(animate ? 1 : 0)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.52)) {
                animate = true
            }
        }
    }
}
''',encoding="utf-8")

path=Path("project-native.yml")
spec=path.read_text(encoding="utf-8")
anchor="          - Views/XSFebboxPremiumCatalog.swift"
assert anchor in spec
for retired in (
    "          - Views/XSCinemaNativeExperience.swift",
    "          - Views/XSETWatchPortalView.swift",
    "          - Views/XSVODPremiumExperience.swift",
    "          - Services/XSVODService.swift",
    "          - Services/XSVODRedirectResolver.swift",
):
    if retired not in spec:
        spec=spec.replace(anchor,anchor+"\n"+retired)
# Critically, old V24 defines XSVODPlaybackSelection; after exclusion,
# V27 defines it exactly once. Player and Sports are still compiled.
assert "- Views/XSCinemaNativeExperience.swift" in spec
assert "- Views/XSPremiumCinemaV27.swift" not in spec
assert "- Views/XSETWatchNativeDetailPlayer.swift" not in spec
assert "- Views/XSVODVLCPlayerView.swift" not in spec
path.write_text(spec,encoding="utf-8")
print("V27 UI isolation: superseded movie browse and VOD services excluded; R5 sports preserved.")
