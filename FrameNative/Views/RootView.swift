import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @State private var showSettings = false

    var body: some View {
        mainTabs
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
                    .preferredColorScheme(.dark)
            }
            .task { await app.loadHome() }
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

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage = "en-US"
    @State private var showClearHistoryConfirmation = false

    @AppStorage("FrameNative.preferredProvider") private var preferredProvider = "auto"
    @AppStorage("FrameNative.preferredSpeed") private var preferredSpeed = 1.0

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

    private let providers = ["auto", "barbarian", "archer", "goblin"]
    private let speeds: [Double] = [0.5, 1, 1.25, 1.5, 2]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white)
                            Text("fX")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 50, height: 50)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("frameX")
                                .font(.title3.weight(.bold))
                            Text("Premium native entertainment for iPhone & iPad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 5)
                }

                Section("Language & Catalog") {
                    Picker("Metadata language", selection: $selectedLanguage) {
                        ForEach(languages, id: \.1) { language in
                            Text(language.0).tag(language.1)
                        }
                    }

                    LabeledContent("Catalog", value: "TMDB")
                    LabeledContent("Playback", value: "FrameXTV")
                }

                Section("Playback Defaults") {
                    Picker("Default server", selection: $preferredProvider) {
                        ForEach(providers, id: \.self) { provider in
                            Text(provider == "auto" ? "Automatic" : provider.capitalized)
                                .tag(provider)
                        }
                    }

                    Picker("Playback speed", selection: $preferredSpeed) {
                        ForEach(speeds, id: \.self) { speed in
                            Text(speed == 1 ? "1× Normal" : String(format: "%g×", speed))
                                .tag(speed)
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "captions.bubble.fill")
                            .foregroundStyle(.cyan)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Subtitles")
                                .font(.body.weight(.semibold))
                            Text("The player now has a permanent Subtitles button that opens FrameXTV’s exact language menu when available, plus a direct track fallback.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Player Features") {
                    Label("Exact subtitle menu + direct track fallback", systemImage: "captions.bubble.fill")
                    Label("Server switching and playback speed", systemImage: "server.rack")
                    Label("Resume playback automatically", systemImage: "clock.arrow.circlepath")
                    Label("Native quick seek controls", systemImage: "goforward.10")
                }

                Section("Library") {
                    LabeledContent("Saved titles", value: "\(library.favoriteItems.count)")
                    LabeledContent("Continue Watching", value: "\(library.continueWatching.count)")

                    Button(role: .destructive) {
                        showClearHistoryConfirmation = true
                    } label: {
                        Label("Clear watch history", systemImage: "trash")
                    }
                }

                Section("Privacy") {
                    Text("Favorites and watch progress stay on this device. TMDB credentials stay on the server and are not embedded in the IPA.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear { selectedLanguage = app.language }
        .onChange(of: selectedLanguage) { newValue in
            guard newValue != app.language else { return }
            app.language = newValue
            Task { await app.loadHome(force: true) }
        }
        .confirmationDialog(
            "Clear Continue Watching history?",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { library.clearWatchHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
