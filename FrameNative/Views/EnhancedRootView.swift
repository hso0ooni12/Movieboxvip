import SwiftUI

struct EnhancedRootView: View {
    @EnvironmentObject private var app: AppState
    @State private var showSettings = false
    @State private var showSplash = true
    @State private var selectedTab = 0

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
            try? await Task.sleep(nanoseconds: 650_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.24)) { showSplash = false }
            }
        }
    }

    private var mainTabs: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    XSCinematicHomeView(showSettings: $showSettings)
                        .xsGlobalSearchToolbar()
                }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)

                NavigationStack {
                    XSReferenceCatalogView(kind: .movie, title: "Movies")
                        .xsGlobalSearchToolbar()
                }
                .tabItem { Label("Movies", systemImage: "film.fill") }
                .tag(1)

                NavigationStack {
                    XSReferenceCatalogView(kind: .tv, title: "Series")
                        .xsGlobalSearchToolbar()
                }
                .tabItem { Label("Series", systemImage: "play.tv.fill") }
                .tag(2)

                NavigationStack {
                    XSSportsLiveViewV33()
                        .xsGlobalSearchToolbar()
                }
                .tabItem { Label("Sports", systemImage: "sportscourt.fill") }
                .tag(3)
            }
            .tint(XSCinemaStyle.accent)
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 76)
            }

            HStack(spacing: 4) {
                tabControl("Home", icon: "house.fill", index: 0)
                tabControl("Movies", icon: "film.stack", index: 1)
                tabControl("Series", icon: "play.tv", index: 2)
                tabControl("Sports", icon: "sportscourt.fill", index: 3)
            }
            .padding(7)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .background(XSCinemaStyle.background.opacity(0.75), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.15)))
            .shadow(color: .black.opacity(0.48), radius: 21, y: 9)
            .frame(maxWidth: 520)
            .padding(.horizontal, 18)
            .padding(.bottom, 4)
        }
    }

    private func tabControl(_ title: String, icon: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button {
            withAnimation(.easeInOut(duration: 0.20)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
            .frame(maxWidth: .infinity)
            .frame(height: 53)
            .background(isSelected ? XSCinemaStyle.accent.opacity(0.24) : .clear,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

}

private struct XSGlobalSearchToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        XSGlobalSearchView()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Search XS TV")
                }
            }
    }
}

private extension View {
    func xsGlobalSearchToolbar() -> some View {
        modifier(XSGlobalSearchToolbarModifier())
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
