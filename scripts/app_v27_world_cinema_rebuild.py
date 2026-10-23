"""V27 clean rebuild: app shell, startup, and surgical source allowlist.

Old players, old site scrapers, FebBox experiments, and V20-V26 view stacks
are left in git history but EXCLUDED from the delivered IPA target.
Protected R5 Sports code and embedded live-channel credentials are retained.
"""
from pathlib import Path
import re

root=Path("FrameNative/Views/EnhancedRootView.swift")
root.write_text(r'''import SwiftUI

struct EnhancedRootView: View {
    @EnvironmentObject private var cinema: XSCinemaNativeStore
    @State private var selectedTab = 0
    @State private var opening = true

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    XSWorldHome()
                }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

                NavigationStack {
                    XSWorldBrowse(kind: .movie)
                }
                .tabItem { Label("Movies", systemImage: "film.stack") }
                .tag(1)

                NavigationStack {
                    XSWorldBrowse(kind: .series)
                }
                .tabItem { Label("Series", systemImage: "play.tv") }
                .tag(2)

                NavigationStack {
                    XSSportsLiveViewV33()
                }
                .tabItem { Label("Sports", systemImage: "sportscourt.fill") }
                .tag(3)
            }
            .tint(XSCinemaStyle.accent)
            .toolbarBackground(XSCinemaStyle.background.opacity(0.95), for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .opacity(opening ? 0 : 1)
            if opening {
                XSPremiumLaunch()
                    .transition(.opacity)
                    .zIndex(9)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            Task { await cinema.boot() }
            try? await Task.sleep(nanoseconds: 500_000_000)
            withAnimation(.easeOut(duration: 0.36)) { opening = false }
        }
    }
}

private struct XSPremiumLaunch: View {
    @State private var animate = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [XSCinemaStyle.lavender.opacity(0.24),
                                    XSCinemaStyle.accent.opacity(0.14), .clear],
                           center: .center, startRadius: 10, endRadius: 360)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                XSBrandMark(size: 135)
                    .scaleEffect(animate ? 1 : 0.82)
                XSWordmark()
                    .font(.headline)
                Text("YOUR CINEMA. YOUR WORLD.")
                    .font(.caption2.bold())
                    .tracking(2.3)
                    .foregroundStyle(.white.opacity(0.54))
            }
            .opacity(animate ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.48)) { animate = true }
        }
    }
}
''',encoding="utf-8")

app=Path("FrameNative/FrameNativeApp.swift")
app.write_text(r'''import SwiftUI
import UIKit
import Foundation

@main
struct XSTVApp: App {
    @StateObject private var cinema = XSCinemaNativeStore()

    init() {
        URLCache.shared = URLCache(
            memoryCapacity: 128 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "xs-world-cinema-cache")
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(red: 0.026, green: 0.031, blue: 0.051, alpha: 0.98)
        tab.stackedLayoutAppearance.normal.iconColor = UIColor(white: 0.61, alpha: 1)
        tab.stackedLayoutAppearance.normal.titleTextAttributes =
            [.foregroundColor: UIColor(white: 0.65, alpha: 1)]
        tab.stackedLayoutAppearance.selected.iconColor =
            UIColor(red: 0.99, green: 0.29, blue: 0.43, alpha: 1)
        tab.stackedLayoutAppearance.selected.titleTextAttributes =
            [.foregroundColor: UIColor(red: 0.99, green: 0.29, blue: 0.43, alpha: 1)]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            EnhancedRootView()
                .environmentObject(cinema)
                .preferredColorScheme(.dark)
        }
    }
}
''',encoding="utf-8")

# Retain exactly the files needed by the rewritten cinema and protected sports
# stack. Every obsolete player, FebBox screen and old TMDB browser is excluded.
allow={
 "FrameNativeApp.swift",
 "Core/IPTVEmbeddedConfig.swift",
 "Services/IPTVService.swift",
 "Services/XSIPTVCatalogDiskCache.swift",
 "Services/XSCinemaNativeSource.swift",
 "Services/XSCinemaNativeSeed.swift",
 "Views/EnhancedRootView.swift",
 "Views/Branding.swift",
 "Views/SportsLiveViewV33.swift",
 "Views/XSWorldCinemaUI.swift",
 "Views/XSWorldCinemaBrowse.swift",
 "Views/XSWorldSitePlayer.swift",
}
allFiles={p.relative_to(Path("FrameNative")).as_posix()
          for p in Path("FrameNative").rglob("*.swift")}
missing=allow-allFiles
assert not missing, f"Required V27 sources missing: {missing}"
excluded=sorted(allFiles-allow)
project=Path("project-native.yml")
doc=project.read_text(encoding="utf-8")
pattern=r"(      - path: FrameNative\n        excludes:\n)(.*?)(    dependencies:\n)"
m=re.search(pattern,doc,re.S)
assert m, "Source group not found in project-native.yml"
doc=doc[:m.start(2)]+"".join(f"          - {item}\n" for item in excluded)+doc[m.end(2):]
project.write_text(doc,encoding="utf-8")

assert "- Views/SportsLiveViewV33.swift" not in doc
assert "- Services/XSVODService.swift" in doc
assert "- Views/XSETWatchNativeDetailPlayer.swift" in doc
assert "- Views/XSCinematicHomeView.swift" in doc
print("V27 world-cinema rebuild: compiled active Swift files:",len(allow))
print("V27 obsolete historical/experimental source files removed from binary:",len(excluded))
print("Only sport uses IPTV. No movie account credentials or old website player.")
