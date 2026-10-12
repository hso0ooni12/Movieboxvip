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
        .tint(.white)
        .toolbarBackground(Color.black.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLanguage = "en-US"
    @State private var showClearHistoryConfirmation = false

    private let languages: [(String, String)] = [
        ("English", "en-US"),
        ("العربية", "ar-SA"),
        ("Français", "fr-FR"),
        ("Español", "es-ES"),
        ("Deutsch", "de-DE"),
        ("Italiano", "it-IT"),
        ("Türkçe", "tr-TR"),
        ("日本語", "ja-JP"),
        ("한국어", "ko-KR")
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(.white)
                            Text("fX")
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 48, height: 48)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("frameX")
                                .font(.headline.weight(.bold))
                            Text("Native iOS entertainment experience")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Experience") {
                    Picker("Metadata language", selection: $selectedLanguage) {
                        ForEach(languages, id: \.1) { language in
                            Text(language.0).tag(language.1)
                        }
                    }

                    LabeledContent("Catalog", value: "TMDB")
                    LabeledContent("Playback", value: "FrameXTV")
                    LabeledContent("Player", value: "Native + Embed SDK")
                }

                Section("Playback") {
                    Label("Subtitle selector is available inside the player", systemImage: "captions.bubble.fill")
                    Label("Multiple playback providers supported", systemImage: "server.rack")
                    Label("Continue Watching saves automatically", systemImage: "clock.arrow.circlepath")
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
                    Text("Your favorites and watch progress stay on this device. TMDB credentials are stored on the server, not inside the IPA.")
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
