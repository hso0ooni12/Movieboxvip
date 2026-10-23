import SwiftUI

// XS TV 27 — native, cinematic, minimal navigation.
// Source metadata never implies a title has a licensed direct stream.
// Sports lives separately in the protected IPTV tab.
private enum XSPalette27 {
    static let canvas = Color(red: 0.027, green: 0.030, blue: 0.047)
    static let raised = Color(red: 0.074, green: 0.079, blue: 0.105)
    static let subtle = Color.white.opacity(0.58)
    static let accent = Color(red: 0.93, green: 0.28, blue: 0.44)
    static let secondary = Color(red: 0.57, green: 0.35, blue: 0.91)
    static let stroke = Color.white.opacity(0.105)
}

private struct XSPremiumButton27: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.89 : 1.0)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.15),
                       value: configuration.isPressed)
    }
}

private struct XSThumbnail27: View {
    let media: XSCinemaMedia
    var wide = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [XSPalette27.raised,
                                        Color(red: 0.15, green: 0.11, blue: 0.21),
                                        XSPalette27.canvas],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = wide ? media.backdropURL : media.imageURL {
                    AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Image(systemName: media.kind == .movie ? "film" : "play.tv")
                                .font(.system(size: 34, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.38))
                        default:
                            Image(systemName: "sparkles.tv")
                                .font(.system(size: 28, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.18))
                        }
                    }
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.32))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }
}

private struct XSPoster27: View {
    let media: XSCinemaMedia
    let width: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            XSThumbnail27(media: media)
                .aspectRatio(0.694, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if media.rating > 0 {
                        Label(String(format: "%.1f", media.rating), systemImage: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .background(.black.opacity(0.76), in: Capsule())
                            .padding(7)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(XSPalette27.stroke))
            Text(media.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(.white.opacity(0.94))
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 5) {
                Text(media.year.isEmpty ? media.kind.label : media.year)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if media.isPlayable {
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(XSPalette27.accent)
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(XSPalette27.subtle)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct XSSectionHeader27: View {
    let eyebrow: String
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(XSPalette27.accent)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}

struct XSHomeV27: View {
    @EnvironmentObject private var store: XSCinemaNativeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var spotlight: XSCinemaMedia? {
        store.movies.first(where: { $0.backdropURL != nil }) ?? store.movies.first
    }

    var body: some View {
        ZStack {
            XSPalette27.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 27) {
                    masthead
                    if let spotlight {
                        NavigationLink { XSDetailV27(media: spotlight) } label: {
                            spotlightCard(spotlight)
                        }
                        .buttonStyle(XSPremiumButton27())
                    }
                    HStack(spacing: 11) {
                        NavigationLink { XSBrowseV27(kind: .movie) } label: {
                            categoryTile("الأفلام", subtitle: "Movies",
                                         icon: "film.stack.fill",
                                         tint: XSPalette27.accent)
                        }
                        NavigationLink { XSBrowseV27(kind: .series) } label: {
                            categoryTile("المسلسلات", subtitle: "Series",
                                         icon: "play.tv.fill",
                                         tint: XSPalette27.secondary)
                        }
                    }
                    .padding(.horizontal, 18)
                    .buttonStyle(XSPremiumButton27())
                    rail(title: "مختارات السينما", eyebrow: "CURATED FOR YOU",
                         items: store.movies)
                    rail(title: "مسلسلات تستحق المتابعة", eyebrow: "BINGE-WORTHY",
                         items: store.series)
                    if !store.freeMovies.isEmpty {
                        rail(title: "مشاهدة مجانية مرخّصة", eyebrow: "FREE TO WATCH",
                             items: store.freeMovies)
                    }
                    let saved = (store.movies + store.series + store.freeMovies)
                        .filter { store.favorites.contains($0.id) }
                    if !saved.isEmpty {
                        rail(title: "قائمتي", eyebrow: "YOUR WATCHLIST", items: saved)
                    }
                    footer
                }
                .padding(.bottom, 45)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.boot() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.boot() }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) {
                appeared = true
            }
        }
    }

    private var masthead: some View {
        HStack(spacing: 12) {
            XSBrandMark(size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("XS TV")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(0.3)
                Text("YOUR CINEMA")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(2.9)
                    .foregroundStyle(XSPalette27.subtle)
            }
            Spacer()
            NavigationLink { XSSearchV27() } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 45, height: 45)
                    .background(.white.opacity(0.065), in: Circle())
                    .overlay(Circle().stroke(XSPalette27.stroke))
            }
            .accessibilityLabel("البحث في الأفلام والمسلسلات")
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 19)
        .padding(.top, 13)
    }

    private func spotlightCard(_ media: XSCinemaMedia) -> some View {
        ZStack(alignment: .bottomLeading) {
            XSThumbnail27(media: media, wide: true)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.28), location: 0.35),
                .init(color: XSPalette27.canvas.opacity(0.97), location: 0.83),
                .init(color: XSPalette27.canvas, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    Circle().fill(XSPalette27.accent).frame(width: 6, height: 6)
                    Text("XS ORIGINAL SELECTION")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2)
                }
                .foregroundStyle(.white.opacity(0.89))
                Text(media.title)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    if media.rating > 0 {
                        Label(String(format: "%.1f", media.rating),
                              systemImage: "star.fill")
                            .foregroundStyle(.yellow)
                    }
                    Text(media.year)
                    Text(media.kind.label)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.81))
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("استكشف العمل")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 22)
                .frame(height: 45)
                .background(.white, in: Capsule())
            }
            .padding(23)
            .padding(.bottom, 15)
            .foregroundStyle(.white)
        }
        .frame(height: 435)
        .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21).stroke(XSPalette27.stroke))
        .padding(.horizontal, 13)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 9)
    }

    private func categoryTile(_ title: String, subtitle: String,
                              icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 35)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(subtitle).font(.caption2)
                    .foregroundStyle(XSPalette27.subtle)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XSPalette27.raised, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(XSPalette27.stroke))
    }

    @ViewBuilder
    private func rail(title: String, eyebrow: String, items: [XSCinemaMedia]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                XSSectionHeader27(eyebrow: eyebrow, title: title)
                    .padding(.horizontal, 19)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 13) {
                        ForEach(Array(items.prefix(28))) { item in
                            NavigationLink { XSDetailV27(media: item) } label: {
                                XSPoster27(media: item, width: 141)
                            }
                            .buttonStyle(XSPremiumButton27())
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles.tv")
                .foregroundStyle(XSPalette27.accent)
            Text("كتالوج الأفلام والمسلسلات مستقل عن قنوات الرياضة")
                .font(.caption)
                .foregroundStyle(XSPalette27.subtle)
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 12)
    }
}

struct XSBrowseV27: View {
    let kind: XSCinemaMediaKind
    @EnvironmentObject private var store: XSCinemaNativeStore
    @State private var term = ""
    @State private var results: [XSCinemaMedia] = []
    @State private var onlySaved = false
    @State private var freeOnly = false
    @State private var sortByRating = false
    @State private var searchTask: Task<Void, Never>?

    private var displayed: [XSCinemaMedia] {
        let pool = freeOnly && kind == .movie ? store.freeMovies : store.list(kind)
        let local = term.isEmpty ? pool : pool.filter {
            $0.title.localizedStandardContains(term)
        }
        var ids = Set(local.map(\.id))
        let combined = local + (term.count > 1 ? results.filter {
            ids.insert($0.id).inserted
        } : [])
        let filtered = onlySaved ? combined.filter { store.favorites.contains($0.id) } : combined
        return sortByRating ? filtered.sorted { $0.rating > $1.rating } : filtered
    }

    var body: some View {
        ZStack {
            XSPalette27.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    XSSectionHeader27(
                        eyebrow: kind == .movie ? "DISCOVER FILMS" : "DISCOVER SERIES",
                        title: kind == .movie ? "الأفلام" : "المسلسلات"
                    )
                    .padding(.top, 16)
                    .overlay(alignment: .bottomTrailing) {
                        Text("\(displayed.count) عنوان")
                            .font(.caption2)
                            .foregroundStyle(XSPalette27.subtle)
                    }

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            capsule("الكل", active: !onlySaved && !freeOnly && !sortByRating) {
                                onlySaved = false; freeOnly = false; sortByRating = false
                            }
                            capsule("الأعلى تقييماً", active: sortByRating) {
                                sortByRating.toggle()
                            }
                            capsule("قائمتي", active: onlySaved) {
                                onlySaved.toggle()
                            }
                            if kind == .movie {
                                capsule("مجانية مرخصة", active: freeOnly) {
                                    freeOnly.toggle()
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 13),
                        GridItem(.flexible(), spacing: 13)
                    ], alignment: .center, spacing: 21) {
                        ForEach(displayed) { item in
                            NavigationLink { XSDetailV27(media: item) } label: {
                                XSPoster27(media: item, width: nil)
                            }
                            .buttonStyle(XSPremiumButton27())
                        }
                    }
                    if displayed.isEmpty && !store.loading {
                        VStack(spacing: 9) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 27))
                            Text("ما لقينا نتائج بهالفلتر")
                                .font(.subheadline.bold())
                        }
                        .foregroundStyle(XSPalette27.subtle)
                        .frame(maxWidth: .infinity, minHeight: 170)
                    }
                    if term.isEmpty && !freeOnly && !onlySaved {
                        Button {
                            Task { await store.more(kind) }
                        } label: {
                            HStack(spacing: 9) {
                                if store.loadingMore.contains(kind) {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.down.circle")
                                }
                                Text("اكتشف المزيد")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(XSPalette27.raised,
                                        in: RoundedRectangle(cornerRadius: 13))
                        }
                        .buttonStyle(XSPremiumButton27())
                    }
                }
                .padding(.horizontal, 17)
                .padding(.bottom, 42)
            }
            .scrollIndicators(.hidden)
        }
        .searchable(text: $term, prompt: "ابحث في \(kind == .movie ? "الأفلام" : "المسلسلات")")
        .navigationTitle(kind == .movie ? "Movies" : "Series")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.boot() }
        .onChange(of: term) { value in
            searchTask?.cancel()
            results = []
            guard value.count >= 2 else { return }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 370_000_000)
                guard !Task.isCancelled else { return }
                if let found = try? await XSCinemaCatalogAPI.shared.search(value, kind: kind),
                   !Task.isCancelled {
                    results = found
                }
            }
        }
    }

    private func capsule(_ title: String, active: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: active ? .bold : .medium))
                .foregroundStyle(active ? Color.white : XSPalette27.subtle)
                .padding(.horizontal, 14)
                .frame(height: 35)
                .background(active ? XSPalette27.accent : XSPalette27.raised,
                            in: Capsule())
                .overlay(Capsule().stroke(XSPalette27.stroke))
        }
        .buttonStyle(XSPremiumButton27())
    }
}

struct XSSearchV27: View {
    @EnvironmentObject private var store: XSCinemaNativeStore
    @State private var query = ""
    @State private var remoteMovies: [XSCinemaMedia] = []
    @State private var remoteSeries: [XSCinemaMedia] = []
    @State private var searchTask: Task<Void, Never>?

    private var matches: [XSCinemaMedia] {
        guard !query.isEmpty else { return [] }
        let base = (store.movies + store.series + store.freeMovies)
            .filter { $0.title.localizedStandardContains(query) }
        var found = Set<String>()
        return Array((base + remoteMovies + remoteSeries)
            .filter { found.insert($0.id).inserted }.prefix(100))
    }

    var body: some View {
        ZStack {
            XSPalette27.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 7) {
                    if query.isEmpty {
                        XSSectionHeader27(eyebrow: "DISCOVER", title: "وش ودك تشاهد؟")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(matches) { item in
                        NavigationLink { XSDetailV27(media: item) } label: {
                            HStack(spacing: 12) {
                                XSThumbnail27(media: item)
                                    .frame(width: 68, height: 89)
                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title)
                                        .font(.subheadline.bold())
                                        .lineLimit(2)
                                    Text(item.kind.label + "  ·  " + item.year)
                                        .font(.caption2)
                                        .foregroundStyle(XSPalette27.subtle)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward")
                                    .font(.caption.bold())
                                    .foregroundStyle(XSPalette27.subtle)
                            }
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(XSPalette27.raised,
                                        in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(XSPremiumButton27())
                    }
                }
                .padding(16)
            }
        }
        .searchable(text: $query, prompt: "فيلم، مسلسل أو اسم ممثل")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: query) { value in
            searchTask?.cancel()
            remoteMovies = []; remoteSeries = []
            guard value.count > 1 else { return }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 390_000_000)
                guard !Task.isCancelled else { return }
                async let movies = XSCinemaCatalogAPI.shared.search(value, kind: .movie)
                async let series = XSCinemaCatalogAPI.shared.search(value, kind: .series)
                if let m = try? await movies, !Task.isCancelled { remoteMovies = m }
                if let s = try? await series, !Task.isCancelled { remoteSeries = s }
            }
        }
    }
}

private struct XSWebsitePlayback27: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let season: Int?
    let episode: Int?
}

struct XSDetailV27: View {
    let media: XSCinemaMedia
    @EnvironmentObject private var store: XSCinemaNativeStore
    @State private var detail: XSCinemaMedia?
    @State private var season = 1
    @State private var websitePlayer: XSWebsitePlayback27?
    @State private var openMedia: XSVODPlaybackSelection?

    private var item: XSCinemaMedia { detail ?? media }
    private var seasons: [Int] { Array(Set(item.episodes.map(\.season))).sorted() }
    private var websiteURL: URL? {
        guard let source = item.sourceURL, let url = URL(string: source),
              url.host == "www.etwatch.net" || url.host == "etwatch.net"
        else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            XSPalette27.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    hero
                    VStack(alignment: .leading, spacing: 17) {
                        Text(item.title)
                            .font(.system(size: 29, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        HStack(spacing: 13) {
                            if item.rating > 0 {
                                Label(String(format: "%.1f", item.rating),
                                      systemImage: "star.fill")
                                    .foregroundStyle(.yellow)
                            }
                            Text(item.year)
                            Text(item.kind.label)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(XSPalette27.subtle)
                        HStack(spacing: 10) {
                            if let link = item.streamURL, item.isPlayable {
                                Button {
                                    openMedia = XSVODPlaybackSelection(
                                        url: link, title: item.title, fallbackURL: nil)
                                } label: { primaryAction("تشغيل", symbol: "play.fill") }
                                    .buttonStyle(XSPremiumButton27())
                            } else if let link = websiteURL {
                                Button {
                                    websitePlayer = XSWebsitePlayback27(
                                        url: link, title: item.title,
                                        season: nil, episode: nil)
                                } label: { primaryAction("تشغيل", symbol: "play.fill") }
                                    .buttonStyle(XSPremiumButton27())
                            }
                            Button { store.toggle(item) } label: {
                                Image(systemName: store.favorite(item) ? "checkmark" : "plus")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 52, height: 49)
                                    .background(XSPalette27.raised,
                                                in: RoundedRectangle(cornerRadius: 13))
                            }
                            .buttonStyle(XSPremiumButton27())
                        }
                        if !item.summary.isEmpty {
                            Text(item.summary)
                                .font(.system(size: 14))
                                .lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        if !item.isPlayable && websiteURL != nil {
                            Label("المشاهدة تتم عبر مشغل المصدر؛ الترجمة والجودة تتبع السيرفر المتاح.",
                                  systemImage: "info.circle")
                                .font(.caption2)
                                .foregroundStyle(XSPalette27.subtle)
                        }
                        if item.kind == .series { episodes }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 42)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: media.id) {
            if media.kind == .series {
                detail = await XSCinemaCatalogAPI.shared.detail(media)
                season = seasons.first ?? 1
            }
        }
        .fullScreenCover(item: $websitePlayer) { selected in
            XSETWatchNativeDetailPlayer(url: selected.url, title: selected.title,
                                          season: selected.season,
                                          episode: selected.episode)
        }
        .fullScreenCover(item: $openMedia) { selected in
            XSVODVLCPlayerView(source: selected)
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            XSThumbnail27(media: item, wide: true)
            LinearGradient(colors: [.clear, XSPalette27.canvas],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(height: 310)
        .clipped()
    }

    private func primaryAction(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 49)
            .background(LinearGradient(
                colors: [XSPalette27.accent, XSPalette27.secondary],
                startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 13))
    }

    private var episodes: some View {
        VStack(alignment: .leading, spacing: 12) {
            XSSectionHeader27(eyebrow: "EPISODES", title: "الحلقات والمواسم")
            if !seasons.isEmpty {
                Menu {
                    ForEach(seasons, id: \.self) { value in
                        Button("الموسم \(value)") { season = value }
                    }
                } label: {
                    Label("الموسم \(season)", systemImage: "chevron.down")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 40)
                        .background(XSPalette27.raised, in: Capsule())
                }
                ForEach(item.episodes.filter { $0.season == season }) { ep in
                    Button {
                        if let websiteURL {
                            websitePlayer = XSWebsitePlayback27(
                                url: websiteURL, title: "\(item.title) · S\(ep.season) E\(ep.number)",
                                season: ep.season, episode: ep.number)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if let image = ep.thumbnail.flatMap(URL.init(string:)) {
                                AsyncImage(url: image) { phase in
                                    if case .success(let picture) = phase {
                                        picture.resizable().scaledToFill()
                                    } else {
                                        Image(systemName: "play.rectangle.fill")
                                    }
                                }
                                .frame(width: 100, height: 66)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            } else {
                                Image(systemName: "play.rectangle.fill")
                                    .frame(width: 100, height: 66)
                                    .background(XSPalette27.raised,
                                                in: RoundedRectangle(cornerRadius: 10))
                            }
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(ep.number) · \(ep.title)")
                                    .font(.subheadline.bold())
                                    .lineLimit(2)
                                Text("S\(ep.season) · E\(ep.number)")
                                    .font(.caption2)
                                    .foregroundStyle(XSPalette27.subtle)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(XSPalette27.accent)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(XSPalette27.raised,
                                    in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(XSPremiumButton27())
                }
                Text("فتح الحلقة يعتمد على توفر رابطها داخل موقع المشاهدة.")
                    .font(.caption2)
                    .foregroundStyle(XSPalette27.subtle)
            } else {
                Text("ما توفرت تفاصيل الحلقات حالياً.")
                    .font(.caption)
                    .foregroundStyle(XSPalette27.subtle)
            }
        }
        .padding(.top, 6)
    }
}
