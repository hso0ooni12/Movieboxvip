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
                .scaleEffect(showSplash ? 1.015 : 1)

            if showSplash {
                FrameXSplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
                    .zIndex(10)
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
                .preferredColorScheme(.dark)
        }
        .task { await app.loadHome() }
        .task {
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack { HomeView(showSettings: $showSettings) }
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { CatalogView(kind: .movie, title: "Movies") }
                .tabItem { Label("Movies", systemImage: "film.fill") }
            NavigationStack { CatalogView(kind: .tv, title: "Series") }
                .tabItem { Label("Series", systemImage: "play.tv.fill") }
            NavigationStack { CatalogView(kind: .anime, title: "Anime") }
                .tabItem { Label("Anime", systemImage: "sparkles") }
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .tint(.cyan)
        .toolbarBackground(Color.black.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct FrameXSplashView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [.cyan.opacity(0.13), .clear, .clear],
                center: .center,
                startRadius: 15,
                endRadius: 260
            )
            .ignoresSafeArea()
            .scaleEffect(animate ? 1.12 : 0.9)
            .opacity(animate ? 1 : 0.55)

            VStack(spacing: 20) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.white)
                        .frame(width: 96, height: 96)
                        .shadow(color: .cyan.opacity(0.28), radius: 28)

                    Text("fX")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                }
                .scaleEffect(animate ? 1 : 0.86)

                VStack(spacing: 5) {
                    Text("frameX")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-1)
                    Text("WATCH · DISCOVER · ENJOY")
                        .font(.caption2.bold())
                        .tracking(3.2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .opacity(animate ? 1 : 0)
                .offset(y: animate ? 0 : 8)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.78)) { animate = true }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage = "en-US"
    @State private var showClearHistoryConfirmation = false

    @AppStorage("FrameNative.preferredProvider") private var preferredProvider = "auto"
    @AppStorage("FrameNative.preferredSpeed") private var preferredSpeed = 1.0
    @AppStorage("FrameNative.preferredSubtitleLanguage") private var preferredSubtitleLanguage = "auto"
    @AppStorage("FrameNative.autoNextEpisode") private var autoNextEpisode = true

    private let languages: [(String, String)] = [
        ("English", "en-US"), ("العربية", "ar-SA"), ("Français", "fr-FR"),
        ("Español", "es-ES"), ("Deutsch", "de-DE"), ("Italiano", "it-IT"),
        ("Português", "pt-BR"), ("Türkçe", "tr-TR"), ("हिन्दी", "hi-IN"),
        ("日本語", "ja-JP"), ("한국어", "ko-KR")
    ]

    private let subtitleLanguages: [(String, String)] = [
        ("Automatic", "auto"), ("Off", "off"), ("العربية · Arabic", "ar"),
        ("English", "en"), ("Español", "es"), ("Français", "fr"),
        ("Deutsch", "de"), ("Italiano", "it"), ("Português", "pt"),
        ("Türkçe", "tr"), ("日本語", "ja"), ("한국어", "ko"),
        ("中文", "zh"), ("Русский", "ru"), ("हिन्दी", "hi")
    ]

    private let providers = ["auto", "barbarian", "archer", "goblin"]
    private let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white)
                            Text("fX").font(.system(size: 20, weight: .black, design: .rounded)).foregroundStyle(.black)
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("frameX").font(.title3.weight(.bold))
                            Text("Premium native entertainment for iPhone & iPad")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }

                Section("Language & Catalog") {
                    Picker("Metadata language", selection: $selectedLanguage) {
                        ForEach(languages, id: \.1) { language in Text(language.0).tag(language.1) }
                    }
                    LabeledContent("Catalog", value: "TMDB")
                    LabeledContent("Playback", value: "FrameXTV")
                }

                Section("Playback Defaults") {
                    Picker("Default server", selection: $preferredProvider) {
                        ForEach(providers, id: \.self) { provider in
                            Text(provider == "auto" ? "Automatic" : provider.capitalized).tag(provider)
                        }
                    }

                    Picker("Playback speed", selection: $preferredSpeed) {
                        ForEach(speeds, id: \.self) { speed in
                            Text(speed == 1 ? "1× Normal" : String(format: "%g×", speed)).tag(speed)
                        }
                    }

                    Picker("Preferred subtitles", selection: $preferredSubtitleLanguage) {
                        ForEach(subtitleLanguages, id: \.1) { language in Text(language.0).tag(language.1) }
                    }

                    Toggle("Play next episode automatically", isOn: $autoNextEpisode)
                }

                Section("Player Features") {
                    Label("Only real subtitle language names are shown", systemImage: "captions.bubble.fill")
                    Label("FrameXTV native controls stay enabled", systemImage: "slider.horizontal.3")
                    Label("Auto Next for series", systemImage: "forward.end.fill")
                    Label("Landscape-optimized controls", systemImage: "rectangle.landscape")
                    Label("Quality & audio menus appear when detected", systemImage: "waveform")
                    Label("Skip Intro appears only when intro timing is exposed", systemImage: "forward.end.alt.fill")
                }

                Section("Library") {
                    LabeledContent("Saved titles", value: "\(library.favoriteItems.count)")
                    LabeledContent("Continue Watching", value: "\(library.continueWatching.count)")
                    Button(role: .destructive) { showClearHistoryConfirmation = true } label: {
                        Label("Clear watch history", systemImage: "trash")
                    }
                }

                Section("Privacy") {
                    Text("Favorites and watch progress stay on this device. TMDB credentials stay on the server and are not embedded in the IPA.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.fontWeight(.semibold) } }
        .onAppear { selectedLanguage = app.language }
        .onChange(of: selectedLanguage) { newValue in
            guard newValue != app.language else { return }
            app.language = newValue
            Task { await app.loadHome(force: true) }
        }
        .confirmationDialog("Clear Continue Watching history?", isPresented: $showClearHistoryConfirmation, titleVisibility: .visible) {
            Button("Clear History", role: .destructive) { library.clearWatchHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
