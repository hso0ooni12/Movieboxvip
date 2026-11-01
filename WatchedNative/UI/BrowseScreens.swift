import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedProvider: ProviderOption?
    @State private var providerItems: [MediaTitle] = []
    @State private var providerError: String?
    @State private var providerLoading = false
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                if !store.home.featured.isEmpty { HeroCarousel(items: Array(store.home.featured.prefix(6))) }
                if let message = store.connectionMessage { StatusPill(text: message).padding(.horizontal, 20) }
                if !store.progress.isEmpty { continueWatching }
                ForEach(store.home.rails) { rail in
                    if rail.title.hasPrefix("On ") { providerRail(rail) }
                    else { TitleRail(rail: rail) }
                }
                HStack(spacing: 6) {
                    Circle().fill(WatchedTheme.accent).frame(width: 4, height: 4)
                    Text("WATCHED").font(.system(size: 10, weight: .semibold)).tracking(3)
                }.foregroundStyle(.white.opacity(0.25)).frame(maxWidth: .infinity).padding(.vertical, 20)
            }.padding(.bottom, 16)
        }
        .background(WatchedTheme.background)
        .scrollIndicators(.hidden)
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
    }
    private var continueWatching: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.t("كمل مشاهدتك", "Continue Watching")).font(.system(size: 20, weight: .bold)).padding(.horizontal, 20)
            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.progress) { progress in
                        NavigationLink(value: progress.title) {
                            VStack(alignment: .leading, spacing: 8) {
                                RemoteImage(url: progress.title.backdropURL).frame(width: 250, height: 140).clipShape(RoundedRectangle(cornerRadius: 13))
                                    .overlay(alignment: .bottom) { ProgressView(value: progress.fraction).tint(WatchedTheme.accent).padding(9) }
                                Text(progress.title.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            }.frame(width: 250, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
        }
    }
    private func providerRail(_ initial: MediaRail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(store.home.providers) { option in
                        Button { chooseProvider(option) } label: {
                            Text(option.label).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                                .foregroundStyle(selectedProvider?.id == option.id ? Color.black : Color.white.opacity(0.7))
                                .background(selectedProvider?.id == option.id ? Color.white : Color.white.opacity(0.06), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
            if providerLoading { ProgressView().frame(maxWidth: .infinity).frame(height: 190) }
            else if let providerError { StatusPill(text: providerError).padding(.horizontal, 20) }
            else { TitleRail(rail: selectedProvider == nil ? initial : MediaRail(id: "provider", title: selectedProvider?.label ?? "", items: providerItems)) }
        }
    }
    private func chooseProvider(_ option: ProviderOption) {
        selectedProvider = option; providerLoading = true; providerError = nil
        Task {
            do {
                let items = try await WatchedClient.shared.provider(option, kind: .tv)
                guard selectedProvider?.id == option.id else { return }
                providerItems = items; providerLoading = false
            } catch {
                guard selectedProvider?.id == option.id else { return }
                providerError = store.t("تعذّر تحميل هذه المنصة حالياً", "Couldn’t load this platform right now"); providerLoading = false
            }
        }
    }
}

struct HeroCarousel: View {
    let items: [MediaTitle]
    @EnvironmentObject private var store: AppStore
    @State private var selection = 0
    var body: some View {
        VStack(spacing: 15) {
            TabView(selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .bottomLeading) {
                        RemoteImage(url: item.backdropURL).frame(height: 425)
                        LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: .black.opacity(0.55), location: 0.5), .init(color: WatchedTheme.background, location: 1)], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 6) {
                                Capsule().fill(WatchedTheme.accent).frame(width: 19, height: 3)
                                Text(store.t("اختيار يستاهل", "IN THE SPOTLIGHT")).font(.system(size: 10, weight: .bold)).tracking(1.5)
                            }.foregroundStyle(.white.opacity(0.7))
                            Text(item.name).font(.system(size: 34, weight: .black, design: .rounded)).lineLimit(2).minimumScaleFactor(0.75)
                                .environment(\.layoutDirection, .leftToRight)
                            HStack(spacing: 10) {
                                if !item.year.isEmpty { Text(item.year) }
                                if item.rating > 0 { Label(String(format: "%.1f", item.rating), systemImage: "star.fill").foregroundStyle(.yellow) }
                                Text(store.t(item.kind == .movie ? "فيلم" : "مسلسل", item.kind == .movie ? "Movie" : "Series"))
                            }.font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                            Text(item.overview).font(.system(size: 12)).lineSpacing(3).lineLimit(2).foregroundStyle(.white.opacity(0.6))
                                .environment(\.layoutDirection, .leftToRight)
                            HStack(spacing: 10) {
                                NavigationLink(value: item) {
                                    Label(store.t("شاهد التفاصيل", "Explore title"), systemImage: "play.fill")
                                }.buttonStyle(PrimaryAction()).accessibilityIdentifier("hero-details-\(index)")
                                Button { store.toggleSaved(item) } label: {
                                    Image(systemName: store.isSaved(item) ? "checkmark" : "plus").font(.system(size: 19, weight: .medium)).frame(width: 48, height: 48)
                                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(.white)
                                }.accessibilityLabel(store.t("قائمتي", "My List"))
                            }.padding(.top, 5)
                        }.padding(.horizontal, 23).padding(.bottom, 5)
                    }.tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 425)
            HStack(spacing: 5) {
                ForEach(items.indices, id: \.self) { index in
                    Capsule().fill(selection == index ? WatchedTheme.accent : .white.opacity(0.18)).frame(width: selection == index ? 24 : 5, height: 4)
                }
            }.animation(.easeOut(duration: 0.2), value: selection)
        }
    }
}

struct CatalogView: View {
    let kind: MediaKind
    @EnvironmentObject private var store: AppStore
    @StateObject private var catalog = CatalogStore()
    @State private var filters = CatalogFilters()
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.t(kind == .movie ? "سينما على ذوقك" : "حلقة ورا حلقة", kind == .movie ? "Find your next film" : "One more episode"))
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45))
                        Text(store.t(kind.title, kind == .movie ? "Movies" : "Shows")).font(.system(size: 30, weight: .bold))
                    }
                    Spacer()
                    Menu {
                        Button(store.t("الأكثر رواجاً", "Popular")) { filters.sort = "popularity.desc" }
                        Button(store.t("الأعلى تقييماً", "Top rated")) { filters.sort = "vote_average.desc" }
                        Button(store.t("الأحدث", "Newest")) { filters.sort = kind == .movie ? "primary_release_date.desc" : "first_air_date.desc" }
                    } label: { Image(systemName: "arrow.up.arrow.down").font(.system(size: 15)).frame(width: 38, height: 38).background(.white.opacity(0.06), in: Circle()) }
                }.padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        genreChip(nil, store.t("الكل", "All"))
                        ForEach(kind == .movie ? GenreOption.all : GenreOption.shows) { genre in
                            genreChip(genre.id, store.t(genre.arabic, genre.english))
                        }
                    }.padding(.horizontal, 20)
                }.scrollIndicators(.hidden)
                if catalog.usingSavedCopy {
                    StatusPill(text: store.t("نسخة محفوظة · النتائج المتاحة محدودة", "Saved copy · Limited results available")).padding(.horizontal, 20)
                }
                if catalog.items.isEmpty && catalog.isLoading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 100) }
                else if catalog.items.isEmpty {
                    EmptyMessage(symbol: "film.stack", title: store.t("ما حصلنا نتائج", "No titles found"), message: catalog.error ?? store.t("جرّب تصنيفاً آخر", "Try a different filter"))
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(catalog.items) { item in
                            GeometryReader { proxy in
                                NavigationLink(value: item) { PosterCard(item: item, width: proxy.size.width) }.buttonStyle(.plain)
                            }.aspectRatio(0.55, contentMode: .fit)
                                .onAppear { if item.id == catalog.items.suffix(4).first?.id { Task { await catalog.more(kind: kind, filters: filters) } } }
                        }
                    }.padding(.horizontal, 20)
                    if catalog.isLoading { ProgressView().frame(maxWidth: .infinity).padding() }
                    if let error = catalog.error, !catalog.usingSavedCopy {
                        VStack(spacing: 12) {
                            Text(error).font(.caption).foregroundStyle(.secondary)
                            Button(store.t("إعادة المحاولة", "Try again")) { Task { await catalog.more(kind: kind, filters: filters) } }
                        }.frame(maxWidth: .infinity).padding()
                    }
                }
            }.padding(.top, 24).padding(.bottom, 32)
        }
        .background(WatchedTheme.background)
        .scrollIndicators(.hidden)
        .task(id: filters) { await catalog.load(kind: kind, filters: filters, fallback: store.home.allTitles, preview: store.isPreview) }
        .refreshable { await catalog.load(kind: kind, filters: filters, fallback: store.home.allTitles, preview: store.isPreview) }
    }
    private func genreChip(_ id: Int?, _ title: String) -> some View {
        Button { filters.genreID = id } label: {
            Text(title).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 15).padding(.vertical, 10)
                .foregroundStyle(filters.genreID == id ? .black : .white.opacity(0.65))
                .background(filters.genreID == id ? .white : .white.opacity(0.06), in: Capsule())
        }.buttonStyle(.plain)
    }
}

struct SearchScreen: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var movies = CatalogStore()
    @StateObject private var shows = CatalogStore()
    @State private var query = ""
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        ScrollView {
            if trimmedQuery.count < 2 {
                VStack(alignment: .leading, spacing: 22) {
                    Text(store.t("وش ودك تشوف؟", "What’s on your mind?")).font(.system(size: 29, weight: .bold)).padding(.horizontal, 20)
                    Text(store.t("ابحث عن فيلم أو مسلسل", "Search for a movie or show")).font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 20)
                    if let rail = store.home.rails.first { TitleRail(rail: rail) }
                }.padding(.top, 25)
            } else {
                VStack(alignment: .leading, spacing: 25) {
                    if movies.isLoading || shows.isLoading { ProgressView().frame(maxWidth: .infinity) }
                    if movies.usingSavedCopy || shows.usingSavedCopy {
                        StatusPill(text: store.t("البحث في النسخة المحفوظة فقط", "Searching the saved copy only")).padding(.horizontal, 20)
                    }
                    if !movies.items.isEmpty { TitleRail(rail: .init(id: "movies", title: store.t("الأفلام", "Movies"), items: movies.items)) }
                    if !shows.items.isEmpty { TitleRail(rail: .init(id: "shows", title: store.t("المسلسلات", "Shows"), items: shows.items)) }
                    if !movies.isLoading && !shows.isLoading && movies.items.isEmpty && shows.items.isEmpty {
                        EmptyMessage(symbol: "magnifyingglass", title: store.t("ما حصلنا نتائج", "No results"), message: store.t("جرّب اسم ثاني أو غيّر طريقة الكتابة", "Try another name or spelling"))
                    }
                }.padding(.vertical, 28)
            }
        }
        .background(WatchedTheme.background)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: store.t("فيلم، مسلسل…", "Movies, shows…"))
        .task(id: trimmedQuery) {
            guard trimmedQuery.count >= 2 else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            let filters = CatalogFilters(query: trimmedQuery)
            async let m: () = movies.load(kind: .movie, filters: filters, fallback: store.home.allTitles, preview: store.isPreview)
            async let s: () = shows.load(kind: .tv, filters: filters, fallback: store.home.allTitles, preview: store.isPreview)
            _ = await (m, s)
        }
    }
}

struct SavedScreen: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(store.t("قائمتي", "My List")).font(.system(size: 30, weight: .bold)).padding(.horizontal, 20)
                if store.saved.isEmpty {
                    EmptyMessage(symbol: "bookmark", title: store.t("اختياراتك تنتظرك هنا", "Make room for your favorites"), message: store.t("اضغط + عند أي عنوان لإضافته إلى قائمتك", "Tap + on any title to save it for later"))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 20) {
                        ForEach(store.saved) { item in
                            GeometryReader { proxy in NavigationLink(value: item) { PosterCard(item: item, width: proxy.size.width) }.buttonStyle(.plain) }
                                .aspectRatio(0.55, contentMode: .fit)
                        }
                    }.padding(.horizontal, 20)
                }
            }.padding(.top, 24)
        }.background(WatchedTheme.background)
    }
}
