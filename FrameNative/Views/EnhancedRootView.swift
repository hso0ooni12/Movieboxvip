import SwiftUI

struct EnhancedRootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showSettings = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            mainTabs
                .opacity(showSplash ? 0 : 1)
                .scaleEffect(showSplash ? 1.012 : 1)

            if showSplash {
                EnhancedXSTVSplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.025)))
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
            await app.loadHome()
        }
        .task {
            try? await Task.sleep(nanoseconds: 1_550_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.42)) {
                    showSplash = false
                }
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack {
                HomeView(showSettings: $showSettings)
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                GenreCatalogView(kind: .movie, title: "Movies")
            }
            .tabItem {
                Label("Movies", systemImage: "film.fill")
            }

            NavigationStack {
                GenreCatalogView(kind: .tv, title: "Series")
            }
            .tabItem {
                Label("Series", systemImage: "play.tv.fill")
            }

            NavigationStack {
                CatalogView(kind: .anime, title: "Anime")
            }
            .tabItem {
                Label("Anime", systemImage: "sparkles")
            }

            NavigationStack {
                SearchView()
            }
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
        }
        .tint(.pink)
        .toolbarBackground(Color.black.opacity(0.94), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct EnhancedXSTVSplashView: View {
    @State private var animate = false
    @State private var sweep = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.purple.opacity(0.25),
                    Color.pink.opacity(0.13),
                    Color.orange.opacity(0.05),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 340
            )
            .ignoresSafeArea()
            .scaleEffect(animate ? 1.14 : 0.88)
            .opacity(animate ? 1 : 0.42)

            LinearGradient(
                colors: [.clear, .white.opacity(0.055), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .rotationEffect(.degrees(-18))
            .offset(x: sweep ? 460 : -460)
            .ignoresSafeArea()

            VStack(spacing: 19) {
                XSBrandMark(size: 158)
                    .scaleEffect(animate ? 1 : 0.80)
                    .opacity(animate ? 1 : 0)

                VStack(spacing: 6) {
                    XSWordmark()
                    Text("ENTERTAINMENT · REIMAGINED")
                        .font(.caption2.bold())
                        .tracking(2.7)
                        .foregroundStyle(.white.opacity(0.48))
                }
                .opacity(animate ? 1 : 0)
                .offset(y: animate ? 0 : 10)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.78, dampingFraction: 0.82)) {
                animate = true
            }
            withAnimation(.linear(duration: 1.15).delay(0.15)) {
                sweep = true
            }
        }
    }
}
