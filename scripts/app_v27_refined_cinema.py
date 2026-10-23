"""Apply V27 premium native layout *after* protected prior-version tests.

V27 changes view structure only; it does not rewrite Sports R5, IPTV access,
provider clients, signed links, native VLC or the underlying film catalog.
"""
from pathlib import Path

file=Path("FrameNative/Views/EnhancedRootView.swift")
s=file.read_text(encoding="utf-8")
assert "XSSportsLiveViewV33()" in s, "R5 Sports routing must be preserved"
assert "XSCinemaNativeHomeView()" in s, "Expected native V26 shell"
file.write_text(r'''import SwiftUI

struct EnhancedRootView: View {
    @StateObject private var cinema = XSCinemaNativeStore()
    @State private var selection = 0
    @State private var splash = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            mainTabs
                .opacity(splash ? 0 : 1)
                .allowsHitTesting(!splash)
            if splash {
                VStack(spacing: 11) {
                    XSBrandMark(size: 128)
                    XSWordmark()
                    Text("YOUR CINEMA. REIMAGINED.")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(.white.opacity(0.53))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(red: 0.027, green: 0.030, blue: 0.047))
                .transition(.opacity)
                .zIndex(5)
            }
        }
        .environmentObject(cinema)
        .task {
            Task { await cinema.boot() }
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                splash = false
            }
        }
        .preferredColorScheme(.dark)
    }

    private var mainTabs: some View {
        TabView(selection: $selection) {
            NavigationStack { XSHomeV27() }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { XSBrowseV27(kind: .movie) }
                .tabItem { Label("Movies", systemImage: "film.stack.fill") }.tag(1)
            NavigationStack { XSBrowseV27(kind: .series) }
                .tabItem { Label("Series", systemImage: "play.tv.fill") }.tag(2)
            NavigationStack { XSSportsLiveViewV33() }
                .tabItem { Label("الرياضة", systemImage: "sportscourt.fill") }.tag(3)
        }
        .tint(Color(red: 0.93, green: 0.28, blue: 0.44))
        .toolbarBackground(Color(red: 0.027, green: 0.030, blue: 0.047),
                           for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
''',encoding="utf-8")

project=Path("project-native.yml")
assert "FrameNative" in project.read_text()
print("XS TV V27 premium UI enabled. R5 Sports unchanged.")
