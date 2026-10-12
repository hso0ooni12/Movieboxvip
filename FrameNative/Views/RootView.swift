import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @State private var showSettings = false

    var body: some View {
        Group {
            if app.isConfigured {
                mainTabs
            } else {
                SetupView()
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .task {
            if app.isConfigured { await app.loadHome() }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack { HomeView(showSettings: $showSettings) }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { CatalogView(kind: .movie, title: "Movies") }
                .tabItem { Label("Movies", systemImage: "film.stack.fill") }

            NavigationStack { CatalogView(kind: .tv, title: "TV") }
                .tabItem { Label("TV", systemImage: "tv.fill") }

            NavigationStack { CatalogView(kind: .anime, title: "Anime") }
                .tabItem { Label("Anime", systemImage: "sparkles.tv.fill") }

            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
        }
        .tint(.cyan)
    }
}

struct SetupView: View {
    @EnvironmentObject private var app: AppState
    @State private var token = ""
    @State private var validating = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Spacer(minLength: 52)
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.white)
                            Text("fX")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                        }
                        .frame(width: 58, height: 58)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Frame Native")
                                .font(.system(size: 30, weight: .black, design: .rounded))
                            Text("Native catalog • FrameXTV player")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("One-time catalog setup")
                            .font(.title2.bold())
                        Text("Paste your TMDB Read Access Token. It is stored only on this iPhone and is used for movie/TV metadata, posters, seasons and search. Playback uses the FrameXTV embed you provided.")
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TMDB Read Access Token")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        SecureField("eyJhbGciOiJIUzI1NiJ9…", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if validating { ProgressView().tint(.black) }
                            Text(validating ? "Checking…" : "Continue")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                    .disabled(validating || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("No certificate or Apple secret is needed inside GitHub.", systemImage: "checkmark.shield")
                        Label("The token can be changed later from Settings.", systemImage: "gearshape")
                        Label("No direct stream URLs are extracted by the app.", systemImage: "lock.shield")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        }
    }

    @MainActor
    private func save() async {
        validating = true
        error = nil
        do {
            try await app.validateToken(token)
            app.saveToken(token)
            await app.loadHome(force: true)
        } catch {
            self.error = error.localizedDescription
        }
        validating = false
    }
}

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var validating = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Catalog") {
                SecureField("TMDB Read Access Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("Metadata language", selection: $app.language) {
                    Text("English").tag("en-US")
                    Text("العربية").tag("ar-SA")
                }

                Button(validating ? "Checking…" : "Validate & Save") {
                    Task { await save() }
                }
                .disabled(validating || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let error { Text(error).foregroundStyle(.orange).font(.footnote) }
            }

            Section("Playback") {
                LabeledContent("Engine", value: "FrameXTV Embed")
                LabeledContent("Player UI", value: "Native + WebKit bridge")
                LabeledContent("Continue Watching", value: "On-device")
            }

            Section("Privacy") {
                Text("Your TMDB token, favorites and watch progress are stored locally on this device using iOS app storage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { token = app.token }
    }

    @MainActor
    private func save() async {
        validating = true
        error = nil
        do {
            try await app.validateToken(token)
            app.saveToken(token)
            await app.loadHome(force: true)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        validating = false
    }
}
