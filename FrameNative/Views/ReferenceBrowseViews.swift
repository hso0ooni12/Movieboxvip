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

// V8: The catalog opens directly with posters and real discovery sections.
// No large duplicate hero, no fixed 18/30-poster limit, no local-only genres.
struct XSReferenceCatalogView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: MediaKind
    let title: String

    @State private var selectedCollection: XSCatalogCollection
    @State private var loaded: [MediaItem] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var requestGeneration = UUID()
    @State private var query = ""
    @State private var queryTask: Task<Void, Never>?
    @State private var listMode = false
    @State private var sortMode: SortMode = .suggested

    private struct CachedCollection {
        let items: [MediaItem]
        let nextPage: Int
        let hasMore: Bool
    }
    @State private var collectionCache: [String: CachedCollection] = [:]
    @State private var cacheOrder: [String] = []

    private var currentCacheKey: String {
        "\(kind.rawValue):\(selectedCollection.id)"
    }

    private enum SortMode: String, CaseIterable, Identifiable {
        case suggested = "مقترحة"
        case rating = "الأعلى تقييماً"
        case newest = "الأحدث"
        case alphabetic = "أبجدي"
        var id: String { rawValue }
    }

    init(kind: MediaKind, title: String) {
        self.kind = kind
        self.title = title
        _selectedCollection = State(initialValue: XSCatalogCollection.all(for: kind)[0])
    }

    private var collections: [XSCatalogCollection] {
        XSCatalogCollection.all(for: kind)
    }

    private var visibleItems: [MediaItem] {
        var output = loaded
        switch sortMode {
        case .suggested: break
        case .rating: output.sort { $0.voteAverage > $1.voteAverage }
        case .newest: output.sort { $0.year > $1.year }
        case .alphabetic:
            output.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return output
    }

    var body: some View {
        ZStack {
            XSV3ScreenBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    pageHeading
                    collectionNavigation
                    searchAndSort
                    resultsHeading

                    if loaded.isEmpty && isLoading {
                        posterSkeleton
                    } else if loaded.isEmpty && loadError != nil {
                        loadingFailure
                    } else if loaded.isEmpty {
                        EmptyStateView(
                            title: "ما فيه نتائج",
                            message: "جرّب قسم آخر أو غيّر البحث.",
                            systemImage: "film"
                        )
                        .padding(.horizontal, 22)
                    } else {
                        posterCollection
                    }

                    if hasMore && loadError == nil && !loaded.isEmpty {
                        HStack(spacing: 11) {
                            ProgressView().tint(XSV3.coral)
                            Text("تحميل المزيد من \(kind == .movie ? "الأفلام" : "المسلسلات")…")
                                .font(.system(size: 12))
                                .foregroundStyle(XSV3.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .task(id: "\(selectedCollection.id)-\(loaded.count)-\(query)") {
                            await loadNextPage()
                        }
                    } else if loadError != nil && !loaded.isEmpty {
                        Button("إعادة محاولة تحميل المزيد") {
                            loadError = nil
                            Task { await loadNextPage() }
                        }
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 22)
                        .frame(height: 46)
                        .foregroundStyle(.white)
                        .background(XSV3.lifted, in: Capsule())
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 10)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .refreshable { await reload(force: true) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(XSV3.ink.opacity(0.97), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
        .task(id: "\(kind.rawValue)-\(selectedCollection.id)") {
            await reload()
        }
        .onChange(of: query) { _ in
            queryTask?.cancel()
            queryTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
        .onDisappear {
            queryTask?.cancel()
            requestGeneration = UUID()
        }
    }

    private var pageHeading: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .movie ? "THE MOVIE COLLECTION" : "YOUR SERIES UNIVERSE")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2.1)
                    .foregroundStyle(XSV3.coral)
                Text(kind == .movie ? "الأفلام" : "المسلسلات")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                    listMode.toggle()
                }
            } label: {
                Image(systemName: listMode ? "square.grid.2x2.fill" : "list.bullet")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(XSV3.lifted,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listMode ? "عرض البوسترات" : "عرض كقائمة")
        }
        .padding(.horizontal, 22)
    }

    private var collectionNavigation: some View {
        VStack(alignment: .leading, spacing: 12) {
            chipRail(title: "تصفّح", items: Array(collections.prefix(5)))
            chipRail(title: "المنصات", items: collections.filter(\.isProvider))
            chipRail(title: "التصنيفات", items: collections.filter {
                if case .genre = $0.category { return true }
                return false
            })
            if selectedCollection.isProvider {
                Text("هذه تصنيفات بحسب بيانات منصات العرض في TMDB (منطقة الولايات المتحدة)، وليست تأكيداً لتوفر التشغيل.")
                    .font(.system(size: 10))
                    .foregroundStyle(XSV3.muted)
                    .padding(.horizontal, 22)
            }
        }
    }

    private func chipRail(title: String, items: [XSCatalogCollection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .padding(.horizontal, 22)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(items) { section in
                        let selected = selectedCollection.id == section.id
                        Button {
                            guard selectedCollection.id != section.id else { return }
                            queryTask?.cancel()
                            query = ""
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                                selectedCollection = section
                            }
                        } label: {
                            Label(section.title, systemImage: section.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(selected ? .black : .white.opacity(0.87))
                                .padding(.horizontal, 14)
                                .frame(height: 43)
                                .background(selected ? Color.white : XSV3.lifted, in: Capsule())
                                .overlay(Capsule().stroke(selected ? .clear : .white.opacity(0.09)))
                        }
                        .buttonStyle(XSV3PressStyle())
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var searchAndSort: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(XSV3.muted)
                TextField(kind == .movie ? "ابحث عن فيلم..." : "ابحث عن مسلسل...", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .foregroundStyle(.white)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(XSV3.muted)
                            .frame(width: 39, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("مسح البحث")
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 52)
            .background(XSV3.lifted, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10)))

            Menu {
                ForEach(SortMode.allCases) { option in
                    Button {
                        sortMode = option
                    } label: {
                        Label(option.rawValue, systemImage: option == sortMode ? "checkmark" : "arrow.up.arrow.down")
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(XSV3.lifted,
                                in: RoundedRectangle(cornerRadius: 15))
            }
            .accessibilityLabel("ترتيب النتائج")
        }
        .padding(.horizontal, 22)
        .padding(.top, 1)
    }

    private var resultsHeading: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text("NOW BROWSING")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.0)
                    .foregroundStyle(XSV3.amber)
                Text(query.isEmpty ? selectedCollection.title : "نتائج البحث")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Text("\(loaded.count) \(kind == .movie ? "فيلم" : "مسلسل")")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(XSV3.muted)
        }
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private var posterCollection: some View {
        if listMode {
            LazyVStack(spacing: 12) {
                ForEach(visibleItems) { item in
                    XSReferenceListCard(item: item)
                }
            }
            .padding(.horizontal, 22)
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112, maximum: 185), spacing: 12)],
                spacing: 19
            ) {
                ForEach(visibleItems) { item in
                    XSReferencePosterCard(item: item)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    private var posterSkeleton: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112, maximum: 185), spacing: 12)],
            spacing: 19
        ) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(XSV3.lifted)
                    .aspectRatio(0.65, contentMode: .fit)
                    .overlay {
                        ProgressView().tint(.white.opacity(0.25))
                    }
            }
        }
        .padding(.horizontal, 22)
        .accessibilityLabel("جارٍ تحميل المحتوى")
    }

    private var loadingFailure: some View {
        VStack(spacing: 13) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(XSV3.amber)
            Text(loadError ?? "تعذّر تحميل القائمة")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.74))
                .multilineTextAlignment(.center)
            Button("إعادة المحاولة") { Task { await reload() } }
                .font(.system(size: 14, weight: .semibold))
                .frame(height: 46)
                .padding(.horizontal, 23)
                .foregroundStyle(.black)
                .background(.white, in: Capsule())
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .padding(.vertical, 45)
    }

    @MainActor
    private func reload(force: Bool = false) async {
        let generation = UUID()
        requestGeneration = generation
        isLoading = false
        loadError = nil
        if !force, query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let cached = collectionCache[currentCacheKey] {
            loaded = cached.items
            nextPage = cached.nextPage
            hasMore = cached.hasMore
            return
        }
        loaded = []
        nextPage = 1
        hasMore = true
        await loadNextPage(generation: generation)
    }

    @MainActor
    private func loadNextPage(generation expected: UUID? = nil) async {
        guard hasMore, !isLoading, loadError == nil else { return }
        let generation = expected ?? requestGeneration
        let categoryID = selectedCollection.id
        let selected = selectedCollection
        let searchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let page = nextPage
        isLoading = true

        do {
            let response: XSCatalogPage
            if !searchText.isEmpty {
                let source = try await app.client.search(searchText, page: page)
                let matches = source.filter { kind == .movie ? $0.kind == .movie : $0.kind != .movie }
                response = XSCatalogPage(items: matches, hasMore: !source.isEmpty && page < 50)
            } else {
                response = try await app.client.discoverCollection(
                    kind: kind, collection: selected, page: page
                )
            }
            guard requestGeneration == generation,
                  categoryID == selectedCollection.id,
                  query.trimmingCharacters(in: .whitespacesAndNewlines) == searchText else { return }

            var known = Set(loaded.map(\.id))
            loaded += response.items.filter { known.insert($0.id).inserted }
            nextPage += 1
            hasMore = response.hasMore
            loadError = nil
            if searchText.isEmpty {
                let key = currentCacheKey
                collectionCache[key] = CachedCollection(items: loaded, nextPage: nextPage, hasMore: hasMore)
                cacheOrder.removeAll { $0 == key }
                cacheOrder.append(key)
                while cacheOrder.count > 8 {
                    let oldest = cacheOrder.removeFirst()
                    collectionCache[oldest] = nil
                }
            }
        } catch {
            guard requestGeneration == generation else { return }
            loadError = error.localizedDescription
        }

        if requestGeneration == generation { isLoading = false }
    }
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
                        ForEach(items) { item in
                            XSReferencePosterCard(item: item)
                        }
                    }
                    .padding(.horizontal, 20)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(items) { item in
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
                .buttonStyle(XSV3PressStyle())

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
                .font(.system(size: 13, weight: .bold, design: .rounded))
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
