import SwiftUI

@main
struct WatchedNativeApp: App {
    @StateObject private var store = AppStore()
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: store.language))
                .environment(\.layoutDirection, store.language == "ar" ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark)
                .tint(WatchedTheme.accent)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var settings = false
    var body: some View {
        TabView {
            stack {
                HomeView()
            }.tabItem { Label(store.t("الرئيسية", "Home"), systemImage: "house.fill") }.tag(0)
            stack { CatalogView(kind: .movie) }
                .tabItem { Label(store.t("الأفلام", "Movies"), systemImage: "film.fill") }.tag(1)
            stack { CatalogView(kind: .tv) }
                .tabItem { Label(store.t("المسلسلات", "Shows"), systemImage: "rectangle.stack.fill") }.tag(2)
            stack { SearchScreen() }
                .tabItem { Label(store.t("البحث", "Search"), systemImage: "magnifyingglass") }.tag(3)
            stack { SavedScreen() }
                .tabItem { Label(store.t("قائمتي", "My List"), systemImage: "bookmark.fill") }.tag(4)
        }
        .toolbarBackground(WatchedTheme.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $settings) { SettingsScreen() }
    }
    private func stack<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Wordmark() }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { settings = true } label: {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 17)).frame(width: 36, height: 36)
                        }.foregroundStyle(.white.opacity(0.75)).accessibilityLabel(store.t("الإعدادات", "Settings"))
                    }
                }
                .toolbarBackground(WatchedTheme.background.opacity(0.94), for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: MediaTitle.self) { DetailScreen(item: $0) }
        }
    }
}
