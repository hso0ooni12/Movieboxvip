"""V24: native cinema, never a full-page WKWebView.

Cinemeta supplies independent browse metadata. Video only plays from
explicit CC-licensed direct sources. R5 Sports remains unchanged.
"""
from pathlib import Path
root=Path("FrameNative/Views/EnhancedRootView.swift")
original=root.read_text(encoding="utf-8")
assert "XSSportsLiveViewV33()" in original
root.write_text(r'''import SwiftUI

struct EnhancedRootView:View {
    @StateObject private var cinema=XSCinemaNativeStore()
    @State private var selection=0
    @State private var splash=true
    var body:some View {
        ZStack {
            mainTabs.opacity(splash ? 0 : 1)
            if splash {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing:15) {
                        XSBrandMark(size:120)
                        XSWordmark()
                        Text("XS TV  •  CINEMA").font(.caption2.bold())
                            .tracking(2.2).foregroundStyle(.white.opacity(0.6))
                    }
                }
                .transition(.opacity)
            }
        }
        .environmentObject(cinema)
        .task {
            Task { await cinema.boot() }
            try? await Task.sleep(nanoseconds:260_000_000)
            withAnimation(.easeOut(duration:0.2)) { splash=false }
        }
        .preferredColorScheme(.dark)
    }

    private var mainTabs:some View {
        TabView(selection:$selection) {
            NavigationStack { XSCinemaNativeHomeView() }
                .tabItem { Label("Home",systemImage:"house.fill") }.tag(0)
            NavigationStack { XSCinemaNativeBrowseView(kind:.movie) }
                .tabItem { Label("Movies",systemImage:"film.stack") }.tag(1)
            NavigationStack { XSCinemaNativeBrowseView(kind:.series) }
                .tabItem { Label("Series",systemImage:"play.tv") }.tag(2)
            NavigationStack { XSSportsLiveViewV33() }
                .tabItem { Label("الرياضة",systemImage:"sportscourt.fill") }.tag(3)
        }
        .tint(XSCinemaStyle.accent)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.97),for:.tabBar)
        .toolbarBackground(.visible,for:.tabBar)
    }
}
''',encoding="utf-8")

project=Path("project-native.yml")
spec=project.read_text(encoding="utf-8")
anchor="          - Views/XSFebboxPremiumCatalog.swift"
assert anchor in spec
spec=spec.replace(anchor,anchor+"""
          - Views/XSETWatchPortalView.swift
          - Views/XSVODPremiumExperience.swift
          - Services/XSVODService.swift
          - Services/XSVODRedirectResolver.swift""")
# Keep original-style VLC player compiled, use native cinema's source-neutral selection.
# The V23 bridge excluded VLC. V24 compiles it again for licensed streams.
spec=spec.replace("          - Views/XSVODVLCPlayerView.swift\n","")
project.write_text(spec,encoding="utf-8")
print("V24: true native SwiftUI catalog, native source-owned VLC playback, unchanged R5 Sports.")
