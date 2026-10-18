import SwiftUI

private let xsAccent = Color(red: 1.0, green: 0.12, blue: 0.38)

struct XSReferenceHomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Binding var showSettings: Bool

    private var featured: MediaItem? {
        app.trendingMovies.first ?? app.spotlight.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if app.isLoading && !app.didLoad {
                PremiumLoadingView(message: "Preparing XS TV…")
            } else if let error = app.errorMessage, !app.didLoad {
                VStack(spacing: 18) {
                    EmptyStateView(title: "Couldn’t Load", message: error, systemImage: "wifi.exclamationmark")
                    Button("Try Again") { Task { await app.loadHome(force: true) } }
                        .buttonStyle(XSReferenceActionButtonStyle(primary: true))
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 30) {
                        if let featured { referenceHero(featured) }
                        continueWatching
                        XSReferenceRail(title: "Trending Now", subtitle: "Top cinema and television streams today", items: Array(app.trendingMovies.prefix(12)))
                        XSReferenceRail(title: "Popular Movies", subtitle: "Global crowd favorites and blockbuster cinema", items: Array(app.popularMovies.prefix(12)))
                        XSReferenceRail(title: "Popular TV Series", subtitle: "Binge-worthy drama, mysteries, and episodic television", items: Array(app.popularTV.prefix(12)))
                        XSReferenceRail(title: "Anime Spotlight", subtitle: "Popular animation and new discoveries", items: Array(app.anime.prefix(12)))
                    }
                    .padding(.bottom, 34)
                }
                .scrollIndicators(.hidden)
                .refreshable { await app.loadHome(force: true) }
            }
        }
        .toolbarBackground(Color.black.opacity(0.96), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { XSWordmark(compact: true) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { MyListView() } label: {
                    Image(systemName: "bookmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    @ViewBuilder
    private func referenceHero(_ item: MediaItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemotePoster(item: item, backdrop: true, cornerRadius: 0)
                .frame(height: 450)
                .clipped()

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.30), .black.opacity(0.96), .black],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    Text("FEATURED FILM")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.12)))

                    if item.voteAverage > 0 {
                        Label(item.ratingText, systemImage: "star.fill")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                    }
                }

                Text(item.title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 8) {
                    Text(item.year)
                    Text("•")
                    Text(item.kind == .tv ? "Series" : "Movie")
                }
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.78))

                if !item.overview.isEmpty {
                    Text(item.overview)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.80))
                        .lineLimit(3)
                        .lineSpacing(3)
                        .frame(maxWidth: 610, alignment: .leading)
                }

                HStack(spacing: 10) {
                    NavigationLink {
                        FrameXTVPlayerScreen(item: item, playback: FrameXTVPlayback(tmdbID: item.tmdbID))
                    } label: {
                        Label("Watch Now", systemImage: "play.fill")
                    }
                    .buttonStyle(XSReferenceActionButtonStyle(primary: true))

                    NavigationLink(value: item) {
                        Label("Details", systemImage: "info.circle")
                    }
                    .buttonStyle(XSReferenceActionButtonStyle(primary: false))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var continueWatching: some View {
        if !library.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "play.circle")
                        .foregroundStyle(xsAccent)
                    Text("Continue Watching")
                        .font(.title3.bold())
                    Spacer()
                    NavigationLink { XSWatchHistoryView() } label: {
                        Text("History →")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.58))
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 20)

                Text("Pick up right where you left off")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 20)
                    .padding(.top, -7)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(library.continueWatching, id: \.item.id) { entry in
                            NavigationLink {
                                FrameXTVPlayerScreen(
                                    item: entry.item,
                                    playback: FrameXTVPlayback(
                                        tmdbID: entry.item.tmdbID,
                                        season: entry.season,
                                        episode: entry.episode,
                                        startAt: entry.currentTime
                                    )
                                )
                            } label: {
                                XSReferenceContinueCard(progress: entry)
                            }
                            .buttonStyle(XSReferenceHitButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct XSReferenceCatalogView: View {
    @EnvironmentObject private var app: AppState
    let kind: MediaKind
    let title: String

    @State private var query = ""
    @State private var viewMode: ViewMode = .grid
    @State private var selectedGenre: Int? = nil
    @State private var selectedYear: String = "All Years"
    @State private var minimumRating: Double = 0
    @State private var sort: SortMode = .defaultOrder

    private enum ViewMode { case grid, list }
    private enum SortMode: String, CaseIterable, Identifiable {
        case defaultOrder = "Default Sort"
        case rating = "Top Rated"
        case newest = "Newest"
        case title = "A–Z"
        var id: String { rawValue }
    }

    private var source: [MediaItem] { app.list(for: kind) }

    private var genreOptions: [(Int, String)] {
        var seen = Set<Int>()
        var values: [(Int, String)] = []
        for item in source {
            for id in item.genreIDs where seen.insert(id).inserted {
                if let name = TMDBGenres.name(for: id) { values.append((id, name)) }
            }
        }
        return values.sorted { $0.1 < $1.1 }
    }

    private var yearOptions: [String] {
        let years = Set(source.map(\.year).filter { $0 != "—" })
        return ["All Years"] + years.sorted(by: >)
    }

    private var filtered: [MediaItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = source.filter { item in
            let matchesQuery = trimmed.isEmpty || item.title.localizedCaseInsensitiveContains(trimmed) || item.subtitle.localizedCaseInsensitiveContains(trimmed)
            let matchesGenre = selectedGenre == nil || item.genreIDs.contains(selectedGenre!)
            let matchesYear = selectedYear == "All Years" || item.year == selectedYear
            let matchesRating = minimumRating == 0 || item.voteAverage >= minimumRating
            return matchesQuery && matchesGenre && matchesYear && matchesRating
        }
        switch sort {
        case .defaultOrder: break
        case .rating: items.sort { $0.voteAverage > $1.voteAverage }
        case .newest: items.sort { $0.year > $1.year }
        case .title: items.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return items
    }

    private var isFiltering: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedGenre != nil || selectedYear != "All Years" || minimumRating > 0 || sort != .defaultOrder
    }

    private var trending: [MediaItem] {
        let ids = Set(filtered.map(\.id))
        let base: [MediaItem]
        switch kind {
        case .movie: base = app.trendingMovies
        case .tv: base = app.trendingTV
        case .anime: base = app.anime
        }
        return base.filter { ids.contains($0.id) }
    }

    private var popular: [MediaItem] {
        let ids = Set(filtered.map(\.id))
        let base: [MediaItem]
        switch kind {
        case .movie: base = app.popularMovies
        case .tv: base = app.popularTV
        case .anime: base = Array(app.anime.dropFirst(min(6, app.anime.count)))
        }
        return base.filter { ids.contains($0.id) }
    }

    var body: some View {
        ZStack {
            XSCinemaStyle.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 27) {
                    if !isFiltering, let spotlight = trending.first ?? popular.first {
                        catalogSpotlight(spotlight)
                    }
                    header
                    searchAndFilters

                    if filtered.isEmpty {
                        EmptyStateView(title: "No Matches", message: "Try different filters or another title.", systemImage: kind.symbol)
                    } else if isFiltering {
                        XSReferenceCatalogSection(title: "Results", subtitle: "\(filtered.count) matching titles", items: filtered, viewModeGrid: viewMode == .grid)
                    } else {
                        XSReferenceCatalogSection(title: trendingTitle, subtitle: trendingSubtitle, items: trending, viewModeGrid: viewMode == .grid)
                        XSReferenceCatalogSection(title: popularTitle, subtitle: popularSubtitle, items: popular, viewModeGrid: viewMode == .grid)
                        XSReferenceCatalogSection(title: thirdTitle, subtitle: thirdSubtitle, items: filtered, viewModeGrid: viewMode == .grid)
                    }
                }
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .refreshable { await app.loadHome(force: true) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.97), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private func catalogSpotlight(_ item: MediaItem) -> some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: item, backdrop: true, cornerRadius: 0)
                    .frame(height: 300)
                    .clipped()
                LinearGradient(
                    colors: [.black.opacity(0.05), XSCinemaStyle.background.opacity(0.38), XSCinemaStyle.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(alignment: .leading, spacing: 10) {
                    Text("NOW SHOWING  /  \(title.uppercased())")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2.5)
                        .foregroundStyle(XSCinemaStyle.warm)
                    Text(item.title)
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Label("Explore title", systemImage: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
            }
            .frame(height: 300)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE COLLECTION")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(2.4)
                        .foregroundStyle(XSCinemaStyle.accent)
                    Text(title)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .tracking(-0.8)
                        .foregroundStyle(.white)
                }
                Spacer()
                HStack(spacing: 0) {
                    modeButton(.grid, image: "square.grid.2x2.fill")
                    modeButton(.list, image: "list.bullet")
                }
                .padding(4)
                .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 13))
                .frame(width: 116)
            }
            Text(descriptionText)
                .font(.system(size: 13))
                .foregroundStyle(XSCinemaStyle.secondary)
                .lineSpacing(3)
        }
        .padding(.horizontal, 22)
    }

    private func modeButton(_ mode: ViewMode, image: String) -> some View {
        Button {
            viewMode = mode
        } label: {
            Image(systemName: image)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(viewMode == mode ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(XSReferenceHitButtonStyle())
    }

    private var searchAndFilters: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.42))
                    TextField("Search \(title.lowercased()) catalog…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10)))


            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Filters & Discovery", systemImage: "slider.horizontal.3")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.88))
                    .symbolRenderingMode(.hierarchical)

                HStack(spacing: 10) {
                    filterMenu(title: selectedGenreName, options: ["All Genres"] + genreOptions.map(\.1)) { value in
                        selectedGenre = genreOptions.first(where: { $0.1 == value })?.0
                    }
                    filterMenu(title: selectedYear, options: yearOptions) { selectedYear = $0 }
                }
                HStack(spacing: 10) {
                    filterMenu(title: ratingTitle, options: ["Any Rating", "6.0+", "7.0+", "8.0+"]) { value in
                        minimumRating = Double(value.replacingOccurrences(of: "+", with: "")) ?? 0
                    }
                    filterMenu(title: sort.rawValue, options: SortMode.allCases.map(\.rawValue)) { value in
                        sort = SortMode(rawValue: value) ?? .defaultOrder
                    }
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.018), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.085)))
        }
        .padding(.horizontal, 20)
    }

    private func filterMenu(title: String, options: [String], select: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { value in
                Button(value) { select(value) }
            }
        } label: {
            HStack {
                Text(title).lineLimit(1)
                Spacer(minLength: 5)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.38))
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08)))
        }
        .buttonStyle(XSReferenceHitButtonStyle())
    }

    private var selectedGenreName: String {
        guard let selectedGenre else { return "All Genres" }
        return genreOptions.first(where: { $0.0 == selectedGenre })?.1 ?? "All Genres"
    }

    private var ratingTitle: String {
        minimumRating == 0 ? "Any Rating" : String(format: "%.1f+", minimumRating)
    }

    private var descriptionText: String {
        switch kind {
        case .movie: return "Browse trending cinema, award-winning blockbusters, and curated genre collections."
        case .tv: return "Discover trending television, binge-worthy series, and curated genre collections."
        case .anime: return "Explore popular anime, new discoveries, and animation favorites in one catalog."
        }
    }

    private var trendingTitle: String { kind == .movie ? "Trending Movies" : (kind == .tv ? "Trending Series" : "Trending Anime") }
    private var trendingSubtitle: String { "Most watched titles across the network today" }
    private var popularTitle: String { kind == .movie ? "Popular Movies" : (kind == .tv ? "Popular Series" : "Popular Anime") }
    private var popularSubtitle: String { "Global crowd favorites and standout titles" }
    private var thirdTitle: String { kind == .movie ? "In Theaters / Now Playing" : (kind == .tv ? "More Series to Explore" : "More Anime to Explore") }
    private var thirdSubtitle: String { kind == .movie ? "Current theatrical releases and recent premieres" : "More titles from the XS TV catalog" }
}

private struct XSReferenceCatalogSection: View {
    let title: String
    let subtitle: String
    let items: [MediaItem]
    let viewModeGrid: Bool

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                    Text("\(items.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.60))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.04), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.08)))
                    Spacer()
                }
                .padding(.horizontal, 20)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 20)
                    .padding(.top, -8)

                if viewModeGrid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110, maximum: 190), spacing: 12)], spacing: 22) {
                        ForEach(Array(items.prefix(18))) { item in
                            XSReferencePosterCard(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(items.prefix(30))) { item in
                            XSReferenceListCard(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }
}

private struct XSReferenceRail: View {
    let title: String
    let subtitle: String
    let items: [MediaItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                    Text("\(items.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.58))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.04), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.08)))
                    Spacer()
                    Text("View all")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.horizontal, 20)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.52))
                    .padding(.horizontal, 20)
                    .padding(.top, -6)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(items) { item in
                            XSReferencePosterCard(item: item)
                                .frame(width: 126)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct XSReferencePosterCard: View {
    @EnvironmentObject private var library: LibraryStore
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                NavigationLink(value: item) {
                    ZStack(alignment: .bottomLeading) {
                        RemotePoster(item: item, cornerRadius: 16)
                            .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        LinearGradient(colors: [.clear, .black.opacity(0.60)], startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        if item.voteAverage > 0 {
                            Label(item.ratingText, systemImage: "star.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(XSCinemaStyle.warm)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(.black.opacity(0.76), in: Capsule())
                                .padding(9)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.13)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(XSReferenceHitButtonStyle())

                Button { library.toggleFavorite(item) } label: {
                    Image(systemName: library.isFavorite(item) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(library.isFavorite(item) ? XSCinemaStyle.warm : .white)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.70), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.15)))
                }
                .buttonStyle(XSReferenceHitButtonStyle())
                .padding(7)
                .accessibilityLabel(library.isFavorite(item) ? "Remove from My List" : "Add to My List")
            }

            Text(item.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(item.year)  ·  \(item.kind == .tv ? "Series" : "Film")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(XSCinemaStyle.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

private struct XSReferenceListCard: View {
    @EnvironmentObject private var library: LibraryStore
    let item: MediaItem

    var body: some View {
        HStack(spacing: 13) {
            NavigationLink(value: item) {
                RemotePoster(item: item, cornerRadius: 9)
                    .frame(width: 68, height: 102)
                    .contentShape(Rectangle())
            }
            .buttonStyle(XSReferenceHitButtonStyle())

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title).font(.headline).lineLimit(2)
                Text("\(item.year) • \(item.kind == .tv ? "Series" : "Film")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.caption2).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
                }
            }
            Spacer()
            Button { library.toggleFavorite(item) } label: {
                Image(systemName: library.isFavorite(item) ? "bookmark.fill" : "bookmark")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(XSReferenceHitButtonStyle())
        }
        .padding(10)
        .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.07)))
    }
}

private struct XSReferenceContinueCard: View {
    let progress: WatchProgress

    private var remaining: String {
        guard progress.duration > 0 else { return "Resume" }
        let minutes = max(0, Int((progress.duration - progress.currentTime) / 60))
        return minutes > 0 ? "\(minutes) min left" : "Almost finished"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                RemotePoster(item: progress.item, backdrop: true, cornerRadius: 11)
                    .frame(width: 190, height: 108)
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.18))
                            Rectangle().fill(xsAccent).frame(width: proxy.size.width * progress.fraction)
                        }
                        .frame(height: 4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 11))
                HStack {
                    if let label = progress.episodeLabel {
                        Text(label.replacingOccurrences(of: " ", with: "  ·  "))
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(.black.opacity(0.72), in: Capsule())
                    }
                    Spacer()
                }
                .padding(8)
            }
            Text(progress.item.title).font(.subheadline.bold()).lineLimit(1)
            HStack(spacing: 7) {
                if let label = progress.episodeLabel { Text(label.replacingOccurrences(of: " ", with: "  ·  ")) }
                Text(remaining)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.52))
        }
        .frame(width: 190, alignment: .leading)
    }
}

private struct XSWatchHistoryView: View {
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(library.continueWatching, id: \.item.id) { entry in
                        NavigationLink {
                            FrameXTVPlayerScreen(
                                item: entry.item,
                                playback: FrameXTVPlayback(tmdbID: entry.item.tmdbID, season: entry.season, episode: entry.episode, startAt: entry.currentTime)
                            )
                        } label: {
                            HStack(spacing: 12) {
                                RemotePoster(item: entry.item, backdrop: true, cornerRadius: 10)
                                    .frame(width: 120, height: 68)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.item.title).font(.headline).lineLimit(1)
                                    Text(entry.episodeLabel ?? "Resume").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.fill")
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(XSReferenceHitButtonStyle())
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("History")
    }
}

private struct XSReferenceHitButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(6)
            .contentShape(Rectangle())
            .padding(-6)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct XSReferenceActionButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(primary ? Color.white : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(primary ? Color.clear : Color.white.opacity(0.13)))
            .foregroundStyle(primary ? Color.black : Color.white)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
