import SwiftUI

private let xsGlobalSearchAccent = Color(red: 1.0, green: 0.12, blue: 0.38)

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
            Color.black.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    searchHeader

                    if trimmedQuery.isEmpty {
                        discover
                    } else if isSearching && results.isEmpty {
                        loadingState
                    } else if let errorMessage, results.isEmpty {
                        VStack(spacing: 16) {
                            EmptyStateView(
                                title: "Search Failed",
                                message: errorMessage,
                                systemImage: "exclamationmark.magnifyingglass"
                            )
                            Button("Retry Search") { scheduleSearch(query, immediate: true) }
                                .buttonStyle(.borderedProminent)
                                .tint(xsGlobalSearchAccent)
                                .accessibilityHint("Try searching again")
                        }
                        .padding(.top, 24)
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
        .toolbarBackground(Color.black.opacity(0.97), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: MediaItem.self) { item in
            DetailView(item: item)
        }
        .onChange(of: query) { newValue in
            scheduleSearch(newValue)
        }
        .onDisappear {
            searchTask?.cancel()
            isSearching = false
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search XS TV")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                Text("Movies, series and anime in one place")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))

                TextField("Type a title…", text: $query)
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
                            .foregroundStyle(.white.opacity(0.46))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.11)))
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.52))
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack(alignment: .topTrailing) {
                                    RemotePoster(item: item, backdrop: false, cornerRadius: 13)
                                        .frame(width: 126, height: 186)
                                        .clipped()

                                    if item.voteAverage > 0 {
                                        Label(item.ratingText, systemImage: "star.fill")
                                            .font(.system(size: 9, weight: .black, design: .monospaced))
                                            .foregroundStyle(.yellow)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 5))
                                            .padding(7)
                                    }
                                }

                                Text(item.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .frame(width: 126, alignment: .leading)

                                Text("\(item.year) · \(kindText(item.kind))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.48))
                            }
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 18)
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
                        .background(Color.white.opacity(0.038), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 18)
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

        isSearching = true
        errorMessage = nil
        results = []
        searchTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 320_000_000)
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
            guard !Task.isCancelled, text == trimmedQuery else { return }
            results = found
        } catch {
            guard !Task.isCancelled, text == trimmedQuery else { return }
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
