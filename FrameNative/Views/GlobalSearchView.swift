import SwiftUI

private let xsGlobalSearchAccent = XSCinemaStyle.accent

struct XSGlobalSearchView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            XSCinemaStyle.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    searchHeader

                    if trimmedQuery.isEmpty {
                        discover
                    } else if isSearching && results.isEmpty {
                        loadingState
                    } else if let errorMessage, results.isEmpty {
                        EmptyStateView(
                            title: "Search Failed",
                            message: errorMessage,
                            systemImage: "exclamationmark.magnifyingglass"
                        )
                        .padding(.top, 50)
                    } else if results.isEmpty {
                        EmptyStateView(
                            title: "No Results",
                            message: "Try another title, spelling, or language.",
                            systemImage: "magnifyingglass"
                        )
                        .padding(.top, 50)
                    } else {
                        resultsSection
                    }
                }
                .padding(.bottom, 42)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(XSCinemaStyle.background.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: MediaItem.self) { item in
            DetailView(item: item)
        }
        .onChange(of: query) { newValue in
            scheduleSearch(newValue)
        }
        .onDisappear {
            searchTask?.cancel()
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("THE DISCOVERY ROOM")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(XSCinemaStyle.accent)
            Text("What moves you?")
                .font(.system(size: 35, weight: .black, design: .rounded))
                .tracking(-1.0)
                .foregroundStyle(.white)
            Text("Movies and series in one place")
                .font(.system(size: 14))
                .foregroundStyle(XSCinemaStyle.secondary)

            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                TextField("Search a title, story or genre…", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { scheduleSearch(query, immediate: true) }
                if !query.isEmpty {
                    Button {
                        query = ""
                        results = []
                        errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 36, height: 36)
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.13)))
            .padding(.top, 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 19)
    }

    private var discover: some View {
        VStack(alignment: .leading, spacing: 24) {
            searchRail(
                title: "Trending Now",
                subtitle: "Popular picks to start exploring",
                items: Array(app.spotlight.prefix(10))
            )
            searchRail(
                title: "Popular Movies",
                subtitle: "Big-screen favorites",
                items: Array(app.popularMovies.prefix(10))
            )
            searchRail(
                title: "Popular Series",
                subtitle: "Binge-worthy television",
                items: Array(app.popularTV.prefix(10))
            )
        }
    }

    private func searchRail(title: String, subtitle: String, items: [MediaItem]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            XSCinemaHeadline(eyebrow: subtitle.uppercased(), title: title)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 13) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            XSCinemaPosterTile(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 5)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Results")
                        .font(.title3.bold())
                    Text("\(results.count) matches for “\(trimmedQuery)”")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.52))
                }
                Spacer()
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .tint(xsGlobalSearchAccent)
                }
            }
            .padding(.horizontal, 18)

            LazyVStack(spacing: 10) {
                ForEach(results) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 14) {
                            RemotePoster(item: item, backdrop: false, cornerRadius: 11)
                                .frame(width: 78, height: 114)
                                .clipped()

                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 8) {
                                    Text(item.title)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Spacer(minLength: 4)
                                }

                                HStack(spacing: 7) {
                                    Text(item.year)
                                    Text("•")
                                    Text(kindText(item.kind))
                                    if item.voteAverage > 0 {
                                        Text("•")
                                        Label(item.ratingText, systemImage: "star.fill")
                                            .foregroundStyle(.yellow.opacity(0.92))
                                    }
                                }
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.56))

                                if !item.overview.isEmpty {
                                    Text(item.overview)
                                        .font(.caption)
                                        .foregroundStyle(.white.opacity(0.62))
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                }

                                Label("Open Details", systemImage: "chevron.right")
                                    .font(.caption2.bold())
                                    .foregroundStyle(xsGlobalSearchAccent)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 22)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 13) {
            ProgressView()
                .controlSize(.large)
                .tint(xsGlobalSearchAccent)
            Text("Searching XS TV…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private func scheduleSearch(_ text: String, immediate: Bool = false) {
        searchTask?.cancel()
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            results = []
            errorMessage = nil
            isSearching = false
            return
        }

        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 220_000_000)
            }
            guard !Task.isCancelled else { return }
            await performSearch(cleaned)
        }
    }

    @MainActor
    private func performSearch(_ text: String) async {
        isSearching = true
        errorMessage = nil
        do {
            let found = try await app.search(text)
            guard !Task.isCancelled else { return }
            results = found
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    private func kindText(_ kind: MediaKind) -> String {
        switch kind {
        case .movie: return "Movie"
        case .tv: return "Series"
        case .anime: return "Anime"
        }
    }
}
