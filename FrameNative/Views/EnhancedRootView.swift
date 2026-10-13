import SwiftUI

struct EnhancedRootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showSettings = false
    @State private var showSplash = true

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
        .task { await app.loadHome() }
        .task {
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) { showSplash = false }
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                XSReferenceHomeView(showSettings: $showSettings)
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                XSReferenceCatalogView(kind: .movie, title: "Movies")
            }
            .tabItem { Label("Movies", systemImage: "film.fill") }

            NavigationStack {
                XSReferenceCatalogView(kind: .tv, title: "Series")
            }
            .tabItem { Label("Series", systemImage: "play.tv.fill") }

            NavigationStack {
                XSReferenceCatalogView(kind: .anime, title: "Anime")
            }
            .tabItem { Label("Anime", systemImage: "sparkles") }

            NavigationStack {
                XSSportsLiveView()
            }
            .tabItem { Label("Sports", systemImage: "sportscourt.fill") }
        }
        .tint(Color(red: 1.0, green: 0.12, blue: 0.38))
        .toolbarBackground(Color.black.opacity(0.97), for: .tabBar)
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
                    Text("ENTERTAINMENT · REIMAGINED")
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
