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
        .toolbarBackground(Color.black.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}

private struct XSTVSplashView: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.purple.opacity(0.24),
                    Color.pink.opacity(0.13),
                    Color.orange.opacity(0.05),
                    .clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 330
            )
            .ignoresSafeArea()
            .scaleEffect(animate ? 1.12 : 0.88)
            .opacity(animate ? 1 : 0.45)

            VStack(spacing: 22) {
                Image("XSStoreLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 42, style: .continuous))
                    .shadow(color: .purple.opacity(0.35), radius: 32)
                    .scaleEffect(animate ? 1 : 0.82)
                    .opacity(animate ? 1 : 0)

                VStack(spacing: 5) {
                    Text("XS TV")
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .tracking(-1)

                    Text("ENTERTAINMENT · REIMAGINED")
                        .font(.caption2.bold())
                        .tracking(2.6)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .opacity(animate ? 1 : 0)
                .offset(y: animate ? 0 : 10)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.78, dampingFraction: 0.82)) {
                animate = true
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
            Color.black.ignoresSafeArea()

            Form {
                Section {
                    HStack(spacing: 14) {
                        Image("XSStoreLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("XS TV")
                                .font(.title3.weight(.bold))
                            Text("Premium entertainment for iPhone & iPad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
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

                Section("Playback") {
                    Toggle("Play next episode automatically", isOn: $autoNextEpisode)

                    Label("All available servers stay inside the player", systemImage: "server.rack")
                    Label("Subtitle languages use the player’s real list", systemImage: "captions.bubble.fill")
                    Label("Quality and audio stay synced with each server", systemImage: "waveform")
                    Label("Resume saves season, episode and exact position", systemImage: "clock.arrow.circlepath")
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

                Section("XS TV") {
                    Text("Designed around the XS Store identity. Favorites and watch progress stay on this device; catalog credentials remain on the server.")
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
}
