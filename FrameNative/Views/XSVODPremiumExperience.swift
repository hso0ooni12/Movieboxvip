import SwiftUI

private enum XSVODStyle {
    static let background = Color(red: 0.035, green: 0.041, blue: 0.065)
    static let panel = Color(red: 0.098, green: 0.103, blue: 0.145)
    static let accent = Color(red: 1.0, green: 0.29, blue: 0.39)
    static let secondary = Color.white.opacity(0.62)
}

struct XSVODPlaybackSelection: Identifiable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }
}

struct XSVODHomeView: View {
    @EnvironmentObject private var store: XSVODCatalogStore
    private var featured: XSVODTitle? { store.movies.first ?? store.series.first }

    var body: some View {
        ZStack {
            XSVODStyle.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 29) {
                    if let featured {
                        NavigationLink {
                            XSVODDetailView(item: featured)
                        } label: {
                            featuredHero(featured)
                        }
                        .buttonStyle(.plain)
                    } else {
                        emptyHero
                    }
                    HStack(spacing: 12) {
                        NavigationLink {
                            XSVODBrowseView(kind: .movie)
                        } label: {
                            quickDestination("أفلام", icon: "film.stack.fill",
                                             count: store.movies.count)
                        }
                        NavigationLink {
                            XSVODBrowseView(kind: .series)
                        } label: {
                            quickDestination("مسلسلات", icon: "play.tv.fill",
                                             count: store.series.count)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)

                    if !store.favorites.isEmpty {
                        let saved = (store.movies + store.series)
                            .filter { store.favorites.contains($0.id) }
                        row("قائمتي", tagline: "YOUR WATCHLIST", items: Array(saved.prefix(20)))
                    }
                    row("أفلام جديدة", tagline: "LATEST MOVIES",
                        items: Array(store.movies.prefix(30)))
                    row("مسلسلات عالمية", tagline: "SERIES COLLECTION",
                        items: Array(store.series.prefix(30)))
                    row("الأعلى تقييماً", tagline: "TOP RATED MOVIES",
                        items: Array(store.movies.filter { $0.rating > 0 }
                            .sorted { $0.rating > $1.rating }.prefix(20)))
                    if !store.movieCategories.isEmpty {
                        genreRail
                    }
                    providerStatus
                }
                .padding(.bottom, 65)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .refreshable { await store.load(force: true) }
        }
        .overlay(alignment: .top) { topNavigation }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.load() }
    }

    private var topNavigation: some View {
        HStack {
            XSWordmark(compact: true)
            Spacer()
            NavigationLink {
                XSVODSearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("بحث عن فيلم أو مسلسل")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .background(LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0)],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func featuredHero(_ item: XSVODTitle) -> some View {
        ZStack(alignment: .bottomLeading) {
            XSVODArtwork(item: item, landscape: true)
                .frame(height: 490)
            LinearGradient(colors: [.clear, .black.opacity(0.28), XSVODStyle.background],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Text("FEATURED  /  XS TV")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2.3)
                    .foregroundStyle(XSVODStyle.accent)
                Text(item.title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack {
                    Image(systemName: "play.fill")
                    Text("مشاهدة التفاصيل")
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 18)
                .frame(height: 43)
                .foregroundStyle(.black)
                .background(.white, in: Capsule())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.bottom, 31)
        }
    }

    private var emptyHero: some View {
        VStack(alignment: .leading, spacing: 15) {
            XSBrandMark(size: 96)
            Text("عالم الأفلام والمسلسلات")
                .font(.system(size: 27, weight: .bold))
            Text(store.loading ? "جارٍ جلب مكتبة الأفلام والمسلسلات…"
                  : (store.message ?? "القائمة غير متاحة حالياً"))
                .font(.subheadline)
                .foregroundStyle(XSVODStyle.secondary)
            if store.loading { ProgressView().tint(XSVODStyle.accent) }
            if !store.loading {
                Button("إعادة المحاولة") { Task { await store.load(force: true) } }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 325, alignment: .leading)
        .padding(25)
    }

    private func quickDestination(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(XSVODStyle.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .bold))
                Text("\(count) عنوان").font(.caption2)
                    .foregroundStyle(XSVODStyle.secondary)
            }
            Spacer()
        }
        .padding(14)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .background(XSVODStyle.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ title: String, tagline: String, items: [XSVODTitle]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tagline).font(.system(size: 10, weight: .bold))
                    .tracking(2.4).foregroundStyle(XSVODStyle.accent)
                Text(title).font(.system(size: 24, weight: .bold))
            }
            .padding(.horizontal, 19)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 13) {
                    ForEach(items) { item in
                        NavigationLink {
                            XSVODDetailView(item: item)
                        } label: {
                            XSVODPosterCard(item: item, width: 140)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 19)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var genreRail: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("اكتشف التصنيفات")
                .font(.system(size: 24, weight: .bold))
                .padding(.horizontal, 19)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(store.movieCategories.prefix(20)) { category in
                        NavigationLink {
                            XSVODBrowseView(kind: .movie, initialCategory: category.id)
                        } label: {
                            Text(category.name)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .frame(height: 47)
                                .background(XSVODStyle.panel,
                                            in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 19)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var providerStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("مكتبتك جاهزة", systemImage: "checkmark.shield")
                .font(.subheadline.bold())
            Text("الأفلام والمسلسلات تُجلب من اشتراكك الحالي. تُعرض الترجمات التي يوفرها الفيديو نفسه.")
                .font(.caption)
                .foregroundStyle(XSVODStyle.secondary)
            if let message = store.message {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(XSVODStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 19)
    }
}

struct XSVODBrowseView: View {
    let kind: XSVODKind
    var initialCategory: String = "all"
    @EnvironmentObject private var store: XSVODCatalogStore
    @State private var category = "all"
    @State private var query = ""
    @State private var sortOrder = 0
    @State private var displayLimit = 90

    private var items: [XSVODTitle] {
        let raw = store.byKind(kind)
        let filtered = raw.filter {
            (category == "all" || $0.categoryID == category) &&
            (query.isEmpty || $0.title.localizedStandardContains(query))
        }
        switch sortOrder {
        case 1: return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case 2: return filtered.sorted { $0.rating > $1.rating }
        default: return filtered
        }
    }

    var body: some View {
        ZStack {
            XSVODStyle.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 15) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind == .movie ? "الأفلام" : "المسلسلات")
                                .font(.system(size: 32, weight: .bold))
                            Text("\(items.count) عنوان متاح")
                                .font(.caption)
                                .foregroundStyle(XSVODStyle.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("ترتيب المصدر") { sortOrder = 0 }
                            Button("حسب الاسم") { sortOrder = 1 }
                            Button("حسب التقييم") { sortOrder = 2 }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .padding(12)
                                .background(XSVODStyle.panel, in: Circle())
                        }
                    }
                    .padding(.top, 20)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            categoryButton("الكل", id: "all")
                            ForEach(store.categories(kind)) { cat in
                                categoryButton(cat.name, id: cat.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .padding(.horizontal, -17)
                    if store.loading && items.isEmpty {
                        HStack(spacing: 9) {
                            ProgressView().tint(XSVODStyle.accent)
                            Text("جاري جلب مكتبة المحتوى…")
                        }
                        .font(.caption).foregroundStyle(XSVODStyle.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 21) {
                        ForEach(Array(items.prefix(displayLimit))) { item in
                            NavigationLink {
                                XSVODDetailView(item: item)
                            } label: {
                                XSVODPosterCard(item: item, width: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if displayLimit < items.count {
                        Button("عرض المزيد") { displayLimit += 90 }
                            .frame(maxWidth: .infinity)
                            .frame(height: 47)
                            .buttonStyle(.borderedProminent)
                            .tint(XSVODStyle.accent)
                    }
                    if items.isEmpty && !store.loading {
                        Text(store.message ?? "لا توجد نتائج في هذا القسم.")
                            .foregroundStyle(XSVODStyle.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .padding(.horizontal, 17)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.load(force: true) }
        }
        .searchable(text: $query, prompt: "بحث في \(kind == .movie ? "الأفلام" : "المسلسلات")")
        .navigationTitle(kind == .movie ? "Movies" : "Series")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            category = initialCategory
            Task { await store.load() }
        }
        .onChange(of: category) { _ in displayLimit = 90 }
        .onChange(of: query) { _ in displayLimit = 90 }
    }

    private func categoryButton(_ title: String, id: String) -> some View {
        Button {
            category = id
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .foregroundStyle(category == id ? .black : .white)
                .background(category == id ? .white : XSVODStyle.panel,
                            in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct XSVODSearchView: View {
    @EnvironmentObject private var store: XSVODCatalogStore
    @State private var query = ""
    @State private var filter = 0

    private var results: [XSVODTitle] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let source = filter == 1 ? store.movies : (filter == 2 ? store.series : store.movies + store.series)
        return Array(source.filter { $0.title.localizedStandardContains(query) }.prefix(160))
    }

    var body: some View {
        ZStack {
            XSVODStyle.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("ابحث في مكتبتك")
                        .font(.system(size: 27, weight: .bold))
                    Picker("القسم", selection: $filter) {
                        Text("الكل").tag(0)
                        Text("الأفلام").tag(1)
                        Text("المسلسلات").tag(2)
                    }
                    .pickerStyle(.segmented)
                    Text(query.isEmpty ? "أدخل اسم الفيلم أو المسلسل." : "\(results.count) نتيجة معروضة")
                        .font(.caption).foregroundStyle(XSVODStyle.secondary)
                    ForEach(results) { item in
                        NavigationLink {
                            XSVODDetailView(item: item)
                        } label: {
                            HStack(spacing: 14) {
                                XSVODArtwork(item: item)
                                    .frame(width: 65, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    Text(item.kind == .movie ? "فيلم" : "مسلسل")
                                        .font(.caption).foregroundStyle(XSVODStyle.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(XSVODStyle.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(17)
            }
        }
        .searchable(text: $query, prompt: "اسم فيلم أو مسلسل")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct XSVODDetailView: View {
    let item: XSVODTitle
    @EnvironmentObject private var store: XSVODCatalogStore
    @State private var episodeList: [XSVODEpisode] = []
    @State private var seasons: [Int] = []
    @State private var season = 1
    @State private var loadingEpisodes = false
    @State private var selectedPlayback: XSVODPlaybackSelection?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            XSVODStyle.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottomLeading) {
                        XSVODArtwork(item: item, landscape: true)
                            .frame(height: 370)
                        LinearGradient(colors: [.clear, XSVODStyle.background],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: 370)
                    VStack(alignment: .leading, spacing: 17) {
                        Text(item.title)
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        HStack(spacing: 9) {
                            Label(item.kind == .movie ? "فيلم" : "مسلسل",
                                  systemImage: item.kind == .movie ? "film" : "play.tv")
                            if !item.year.isEmpty { Text(item.year) }
                            if item.rating > 0 {
                                Label(String(format: "%.1f", item.rating), systemImage: "star.fill")
                            }
                        }
                        .font(.caption.bold()).foregroundStyle(XSVODStyle.secondary)
                        HStack(spacing: 11) {
                            if item.kind == .movie {
                                Button {
                                    Task { await startMovie() }
                                } label: {
                                    Label("تشغيل الفيلم", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity, minHeight: 48)
                                }
                                .buttonStyle(.borderedProminent).tint(XSVODStyle.accent)
                            }
                            Button {
                                store.toggle(item)
                            } label: {
                                Label(store.favorite(item) ? "في قائمتي" : "قائمتي",
                                      systemImage: store.favorite(item) ? "checkmark" : "plus")
                                    .frame(minHeight: 48)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                        if !item.plot.isEmpty {
                            Text(item.plot)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.80))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !item.genre.isEmpty {
                            Text(item.genre).font(.caption)
                                .foregroundStyle(XSVODStyle.secondary)
                        }
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        if item.kind == .series {
                            seriesSection
                        }
                        Text("الترجمة من الفيديو نفسه إن كانت متوفرة. يمكن اختيار اللغة من قائمة المشغل.")
                            .font(.caption2).foregroundStyle(XSVODStyle.secondary)
                    }
                    .padding(.horizontal, 19)
                    .padding(.bottom, 45)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            if item.kind == .series { await loadEpisodes() }
        }
        .fullScreenCover(item: $selectedPlayback) { selection in
            XSVODVLCPlayerView(source: selection)
        }
    }

    @ViewBuilder
    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("المواسم والحلقات")
                .font(.title3.bold())
            if loadingEpisodes {
                HStack {
                    ProgressView().tint(XSVODStyle.accent)
                    Text("جارٍ جلب الحلقات…")
                }
                .font(.caption).foregroundStyle(XSVODStyle.secondary)
            }
            if !seasons.isEmpty {
                Picker("الموسم", selection: $season) {
                    ForEach(seasons, id: \.self) { value in
                        Text("Season \(value)").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
                ForEach(episodeList.filter { $0.season == season }) { episode in
                    Button {
                        Task { await startEpisode(episode) }
                    } label: {
                        HStack(spacing: 11) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(XSVODStyle.panel)
                                Image(systemName: "play.fill")
                                    .foregroundStyle(XSVODStyle.accent)
                            }
                            .frame(width: 62, height: 61)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(episode.number). \(episode.name)")
                                    .font(.subheadline.bold()).foregroundStyle(.white)
                                    .lineLimit(2)
                                Text("Episode \(episode.number)")
                                    .font(.caption2).foregroundStyle(XSVODStyle.secondary)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(XSVODStyle.accent)
                        }
                        .padding(8)
                        .background(XSVODStyle.panel.opacity(0.6),
                                    in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            } else if !loadingEpisodes {
                Button("إعادة جلب الحلقات") { Task { await loadEpisodes() } }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func loadEpisodes() async {
        loadingEpisodes = true
        errorMessage = nil
        defer { loadingEpisodes = false }
        do {
            let items = try await XSVODService.shared.episodes(for: item.streamID)
            episodeList = items
            seasons = Array(Set(items.map(\.season))).sorted()
            season = seasons.first ?? 1
            if items.isEmpty { errorMessage = "المسلسل لا يحتوي على حلقات متاحة حالياً." }
        } catch {
            errorMessage = (error as? XSVODFailure)?.localizedDescription ?? "تعذر جلب الحلقات."
        }
    }

    private func startMovie() async {
        guard let url = await XSVODService.shared.moviePlaybackURL(item) else {
            errorMessage = "لا يمكن إنشاء رابط تشغيل للفيلم."
            return
        }
        selectedPlayback = XSVODPlaybackSelection(url: url, title: item.title)
    }

    private func startEpisode(_ episode: XSVODEpisode) async {
        guard let url = await XSVODService.shared.episodePlaybackURL(episode) else {
            errorMessage = "لا يمكن إنشاء رابط تشغيل للحلقة."
            return
        }
        selectedPlayback = XSVODPlaybackSelection(url: url, title: episode.name)
    }
}

private struct XSVODPosterCard: View {
    let item: XSVODTitle
    let width: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            XSVODArtwork(item: item)
                .aspectRatio(0.7, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            HStack {
                Text(item.year.isEmpty ? (item.kind == .movie ? "Movie" : "Series") : item.year)
                Spacer()
                if item.rating > 0 { Image(systemName: "star.fill") }
            }
            .font(.caption2).foregroundStyle(XSVODStyle.secondary)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct XSVODArtwork: View {
    let item: XSVODTitle
    var landscape = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [XSVODStyle.panel, Color.purple.opacity(0.20),
                                        XSVODStyle.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = landscape ? item.backdropURL : item.imageURL {
                    AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else { placeholder }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
    private var placeholder: some View {
        Image(systemName: item.kind == .movie ? "film.stack" : "play.tv")
            .font(.system(size: landscape ? 62 : 40, weight: .thin))
            .foregroundStyle(.white.opacity(0.24))
    }
}
