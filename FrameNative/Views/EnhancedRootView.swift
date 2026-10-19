import SwiftUI

struct EnhancedRootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showSettings = false
    @State private var showSplash = true
    @State private var selectedTab = 0
    @StateObject private var febboxCatalog = XSFebboxCatalogStore()
    @StateObject private var febboxSaved = XSFebboxSavedItems()

    var body: some View {
        ZStack {
            mainTabs
                .opacity(showSplash ? 0 : 1)
                .scaleEffect(showSplash ? 1.006 : 1)

            if showSplash {
                EnhancedXSTVSplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
            }
            .preferredColorScheme(.dark)
        }
        .task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) { showSplash = false }
            }
        }
    }

    private var mainTabs: some View {
        // Navigation chrome MUST belong to TabView, never to a root ZStack.
        // The former root overlay leaked over pushed fullscreen movie players
        // and VLC fullScreenCover, obscuring subtitles and scrub controls.
        TabView(selection: $selectedTab) {
            NavigationStack {
                XSFebboxPremiumHomeView(showSettings: $showSettings)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }
            .tag(0)

            NavigationStack {
                XSFebboxPremiumCatalogView(shelf: .movies)
            }
            .tabItem { Label("Movies", systemImage: "film.stack") }
            .tag(1)

            NavigationStack {
                XSFebboxPremiumCatalogView(shelf: .series)
            }
            .tabItem { Label("Series", systemImage: "play.tv") }
            .tag(2)

            NavigationStack {
                XSSportsLiveViewV33()
            }
            .tabItem { Label("Sports", systemImage: "sportscourt.fill") }
            .tag(3)

        }
        .environmentObject(febboxCatalog)
        .environmentObject(febboxSaved)
        .tint(XSCinemaStyle.accent)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

}

private struct EnhancedXSTVSplashView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(
                colors: [Color.purple.opacity(0.20), Color.pink.opacity(0.10), .clear],
                center: .center,
                startRadius: 10,
                endRadius: 300
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                XSBrandMark(size: 148)
                    .scaleEffect(animate ? 1 : 0.90)
                    .opacity(animate ? 1 : 0)
                VStack(spacing: 5) {
                    XSWordmark()
                    Text("YOUR CINEMA. YOUR WORLD.")
                        .font(.caption2.bold())
                        .tracking(2.5)
                        .foregroundStyle(.white.opacity(0.46))
                }
                .opacity(animate ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) { animate = true }
        }
    }
}
