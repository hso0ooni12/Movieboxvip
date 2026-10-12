import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @State private var showSettings = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            mainTabs
                .opacity(showSplash ? 0 : 1)
                .scaleEffect(showSplash ? 1.012 : 1)

            if showSplash {
                XSTVSplashView()
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
                CatalogView(kind: .movie, title: "Movies")
            }
            .tabItem {
                Label("Movies", systemImage: "film.fill")
            }

            NavigationStack {
                CatalogView(kind: .tv, title: "Series")
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

private struct XSTVSplashView: View {
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

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage = "en-US"
    @State private var showClearHistoryConfirmation = false
    @AppStorage("XSTV.autoNextEpisode") private var autoNextEpisode = true

    private let languages: [(String, String)] = [
        ("English", "en-US"),
        ("العربية", "ar-SA"),
        ("Français", "fr-FR"),
        ("Español", "es-ES"),
        ("Deutsch", "de-DE"),
        ("Italiano", "it-IT"),
        ("Português", "pt-BR"),
        ("Türkçe", "tr-TR"),
        ("हिन्दी", "hi-IN"),
        ("日本語", "ja-JP"),
        ("한국어", "ko-KR")
    ]

    var body: some View {
        ZStack {
            XSBackground()

            ScrollView {
                VStack(spacing: 18) {
                    brandHeader
                    preferencesCard
                    playbackCard
                    libraryCard
                    privacyCard
                    versionFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            selectedLanguage = app.language
        }
        .onChange(of: selectedLanguage) { newValue in
            guard newValue != app.language else { return }
            app.language = newValue
            Task {
                await app.loadHome(force: true)
            }
        }
        .confirmationDialog(
            "Clear Continue Watching history?",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                library.clearWatchHistory()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var brandHeader: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.28), Color.pink.opacity(0.16), Color.orange.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 14) {
                XSBrandMark(size: 62, showGlow: true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("XS TV")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                    Text("Premium entertainment for iPhone & iPad")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                }
                Spacer()
            }
            .padding(18)
        }
        .frame(height: 118)
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.08)))
    }

    private var preferencesCard: some View {
        SettingsCard(title: "Experience", systemImage: "slider.horizontal.3") {
            VStack(spacing: 0) {
                HStack {
                    Label("Metadata Language", systemImage: "globe")
                    Spacer()
                    Picker("Metadata Language", selection: $selectedLanguage) {
                        ForEach(languages, id: \.1) { language in
                            Text(language.0).tag(language.1)
                        }
                    }
                    .labelsHidden()
                }
                .padding(.vertical, 12)

                SettingsDivider()

                Toggle(isOn: $autoNextEpisode) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Auto Next Episode", systemImage: "forward.end.fill")
                        Text("Automatically continue a series when the current episode ends")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.pink)
                .padding(.vertical, 12)
            }
        }
    }

    private var playbackCard: some View {
        SettingsCard(title: "Playback", systemImage: "play.rectangle.fill") {
            VStack(spacing: 0) {
                XSTVSettingsFeature(icon: "server.rack", title: "All available servers", detail: "The official player keeps its full live server list")
                SettingsDivider()
                XSTVSettingsFeature(icon: "captions.bubble.fill", title: "Real subtitle languages", detail: "Subtitle choices come directly from the active player server")
                SettingsDivider()
                XSTVSettingsFeature(icon: "clock.arrow.circlepath", title: "Smart Resume", detail: "Saves title, season, episode and exact playback position")
                SettingsDivider()
                XSTVSettingsFeature(icon: "forward.end.fill", title: "Smart Up Next", detail: "Finds the next episode even when you resume directly from Home")
            }
        }
    }

    private var libraryCard: some View {
        SettingsCard(title: "Library", systemImage: "square.stack.fill") {
            VStack(spacing: 0) {
                HStack {
                    Label("Saved Titles", systemImage: "bookmark.fill")
                    Spacer()
                    Text("\(library.favoriteItems.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)

                SettingsDivider()

                HStack {
                    Label("Continue Watching", systemImage: "play.circle.fill")
                    Spacer()
                    Text("\(library.continueWatching.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)

                SettingsDivider()

                Button(role: .destructive) {
                    showClearHistoryConfirmation = true
                } label: {
                    HStack {
                        Label("Clear Watch History", systemImage: "trash")
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private var privacyCard: some View {
        SettingsCard(title: "Privacy", systemImage: "lock.shield.fill") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your My List and viewing progress stay on this device. Catalog credentials remain on the XS TV server and are not embedded in the IPA.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
            .padding(.vertical, 11)
        }
    }

    private var versionFooter: some View {
        VStack(spacing: 5) {
            XSWordmark(compact: true)
                .opacity(0.72)
            Text("Designed for a premium native iOS experience")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.34))
        }
        .padding(.top, 8)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.white.opacity(0.55))
                .textCase(.uppercase)
                .tracking(1.1)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.065)))
        }
    }
}

private struct XSTVSettingsFeature: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.pink)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.065))
            .frame(height: 1)
    }
}
