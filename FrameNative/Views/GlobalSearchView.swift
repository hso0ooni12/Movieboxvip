import SwiftUI

private let xsGlobalSearchAccent = XSCinemaStyle.accent

struct XSGlobalSearchView: View {
    @EnvironmentObject private var app: AppState
    @State private var query = ""
    @State private var results: [MediaItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchHasFocus: Bool
    @State private var selectedScope: SearchScope = .all

    private enum SearchScope: String, CaseIterable {
        case all = "All"
        case movies = "Movies"
        case series = "Series"

        var icon: String {
            switch self {
            case .all: return "square.grid.2x2.fill"
            case .movies: return "film"
            case .series: return "play.tv"
            }
        }
    }

    private var scopedResults: [MediaItem] {
        switch selectedScope {
        case .all: return results
        case .movies: return results.filter { $0.kind == .movie }
        case .series: return results.filter { $0.kind == .tv }
        }
    }


    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            XSV3ScreenBackdrop()

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
        // Search owns direct destinations. The parent Home/Catalog stack
        // already registers MediaItem routes; duplicate value resolution
        // could pop back to browsing instead of pushing the chosen detail.
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
                    .focused($searchHasFocus)
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
            if let featured = app.spotlight.first ?? app.popularMovies.first {
                NavigationLink {
                    DetailView(item: featured)
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        RemotePoster(item: featured, backdrop: true, cornerRadius: 23)
                            .frame(height: 235)
                            .clipped()
                        LinearGradient(colors: [.clear, .black.opacity(0.94)],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SPOTLIGHT DISCOVERY")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(2.1)
                                .foregroundStyle(XSV3.amber)
                            Text(featured.title)
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Label("Discover", systemImage: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(20)
                    }
                    .frame(height: 235)
                    .clipShape(RoundedRectangle(cornerRadius: 23))
                    .overlay(RoundedRectangle(cornerRadius: 23).stroke(.white.opacity(0.12)))
                }
                .buttonStyle(XSV3PressStyle())
                .padding(.horizontal, 22)
            }
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
                        NavigationLink {
                            DetailView(item: item)
                        } label: {
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
        VStack(alignment: .leading, spacing: 17) {
            XSV3SectionTitle(
                eyebrow: "YOUR DISCOVERIES",
                title: "Search results",
                count: "\(scopedResults.count) of \(results.count)"
            )

            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        let selected = selectedScope == scope
                        Button {
                            searchHasFocus = false
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedScope = scope
                            }
                        } label: {
                            Label(scope.rawValue, systemImage: scope.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selected ? .black : .white.opacity(0.82))
                                .padding(.horizontal, 14)
                                .frame(height: 40)
                                .background(selected ? Color.white : XSV3.lifted, in: Capsule())
                                .overlay(Capsule().stroke(selected ? Color.clear : .white.opacity(0.1)))
                        }
                        .buttonStyle(XSV3PressStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)

            if scopedResults.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 25))
                        .foregroundStyle(XSV3.amber)
                    Text("No \(selectedScope.rawValue.lowercased()) results")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("Try All or search for another title.")
                        .font(.system(size: 13))
                        .foregroundStyle(XSV3.muted)
                    Button("Show all results") {
                        selectedScope = .all
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .foregroundStyle(.black)
                    .background(.white, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: 14)],
                      alignment: .center, spacing: 23) {
                ForEach(scopedResults) { item in
                    NavigationLink {
                            DetailView(item: item)
                        } label: {
                        XSCinemaPosterTile(item: item)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .buttonStyle(XSV3PressStyle())
                    .accessibilityLabel("Discover \(item.title)")
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            }

            if isSearching {
                HStack(spacing: 8) {
                    ProgressView().tint(XSV3.coral)
                    Text("Finding more…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(XSV3.muted)
                }
                .frame(maxWidth: .infinity)
            }
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
