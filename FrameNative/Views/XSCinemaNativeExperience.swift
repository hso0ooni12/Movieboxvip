import SwiftUI

// Source-neutral media selection consumed by the original-style VLC player.
// V24 contains no ETWatch full-page browser and no Xtream VOD linkage.
struct XSVODPlaybackSelection: Identifiable {
    let url: URL
    let title: String
    let fallbackURL: URL?
    var id: String { url.absoluteString }
}

private enum XSNativeCinemaColors {
    static let background = Color(red:0.031,green:0.038,blue:0.060)
    static let tile = Color(red:0.088,green:0.104,blue:0.145)
    static let accent = Color(red:0.50,green:0.77,blue:0.67)
    static let muted = Color.white.opacity(0.64)
}

// Editorial, native-first home: restrained typography, one hero and
// compact poster carousels. No nested browser nav or marketing text cards.
struct XSCinemaNativeHomeView: View {
    @EnvironmentObject private var store: XSCinemaNativeStore
    @State private var revealed = false
    @State private var resumeSelection: XSCinemaWatchRecord?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var featured: XSCinemaMedia? { store.movies.first(where: { $0.backdrop != nil }) ?? store.movies.first }

    var body: some View {
        ZStack {
            XSAtmosphericCinemaBackdropV27()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    topBar
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                    if let featured {
                        featuredHero(featured)
                            .padding(.horizontal, 15)
                            .opacity(revealed ? 1 : 0)
                            .offset(y: revealed ? 0 : 15)
                    } else {
                        headerPlaceholder
                    }

                    continueWatching
                    if store.shelves.isEmpty {
                        posterRail("أفلام تستحق المشاهدة", items: store.movies)
                        posterRail("مسلسلات مختارة", items: store.series)
                    }
                    XSEditorialCollectionsV27()
                    if !store.favorites.isEmpty {
                        posterRail("قائمتي", items: (store.movies + store.series + store.freeMovies)
                            .filter { store.favorites.contains($0.id) })
                    }
                    if !store.freeMovies.isEmpty {
                        posterRail("مشاهدة مجانية", items: store.freeMovies)
                    }
                }
                .padding(.bottom, 35)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.boot(force: true) }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.boot() }
        .onAppear {
            withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.42)) { revealed = true }
        }
            .fullScreenCover(item: $resumeSelection) { record in
                if let url = record.watchURL {
                    XSETWatchNativeDetailPlayer(url: url, title: record.title,
                        season: record.season, episode: record.episode,
                        resumePosition: record.position,
                        onProgress: { time, duration in
                            store.saveProgress(record.media, season: record.season, episode: record.episode,
                                               position: time, duration: duration)
                        })
                }
            }
    }

    @ViewBuilder
    private var continueWatching: some View {
        if !store.recents.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("أكمل المشاهدة").font(.title3.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.recents) { record in
                            Button { resumeSelection = record } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    XSCinemaNativeArtwork(media: record.media, landscape: true)
                                        .frame(width: 240, height: 134)
                                        .overlay {
                                            Image(systemName: "play.circle.fill").font(.system(size: 34))
                                                .foregroundStyle(.white).shadow(radius: 10)
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 13))
                                    ProgressView(value: record.progress).tint(XSNativeCinemaColors.accent)
                                    Text(record.title).font(.caption.bold()).lineLimit(1).foregroundStyle(.white)
                                }
                                .frame(width: 240)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }

        }
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            XSBrandMark(size: 35)
            VStack(alignment: .leading, spacing: 2) {
                Text("XS TV")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .tracking(-0.7)
                    .foregroundStyle(.white)
                Text("CINEMA")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(3.3)
                    .foregroundStyle(XSNativeCinemaColors.muted)
            }
            Spacer()
            NavigationLink {
                XSCinemaNativeSearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.075), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
            }
            .accessibilityLabel("البحث في السينما")
        }
    }

    private func featuredHero(_ item: XSCinemaMedia) -> some View {
        NavigationLink {
            XSCinemaNativeDetailView(media: item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                XSCinemaNativeArtwork(media: item, landscape: true)
                    .frame(height: 382)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.10), location: 0.0),
                    .init(color: .clear, location: 0.34),
                    .init(color: .black.opacity(0.64), location: 0.66),
                    .init(color: .black.opacity(0.96), location: 1.0)
                ], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 12) {
                    Text("FEATURED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.9)
                        .foregroundStyle(.white.opacity(0.78))
                    Text(item.title)
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.white)
                    HStack(spacing: 11) {
                        if !item.year.isEmpty {
                            Text(item.year).lineLimit(1)
                        }
                        if item.rating > 0 {
                            Label(String(format: "%.1f", item.rating), systemImage: "star.fill")
                        }
                        Text(item.kind.label)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("استكشف")
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.black)
                    .frame(width: 132, height: 43)
                    .background(.white, in: Capsule())
                    .padding(.top, 3)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 23)
            }
            .frame(height: 382)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
    }

    private var headerPlaceholder: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("عالم من الحكايات")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            if store.loading {
                ProgressView().tint(XSNativeCinemaColors.accent)
            } else {
                Text(store.error ?? "ما قدرنا نحمّل الأفلام حالياً")
                    .font(.subheadline)
                    .foregroundStyle(XSNativeCinemaColors.muted)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .bottomLeading)
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private func posterRail(_ title: String, items: [XSCinemaMedia]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 21)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(items.prefix(24))) { item in
                            NavigationLink {
                                XSCinemaNativeDetailView(media: item)
                            } label: {
                                XSCinemaNativePoster(media: item, width: 143)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct XSCinemaNativeBrowseView: View {
    let kind:XSCinemaMediaKind
    @EnvironmentObject private var store:XSCinemaNativeStore
    @State private var query=""
    @State private var remote:[XSCinemaMedia]=[]
    @State private var filter=0
    @State private var searchTask:Task<Void,Never>?

    private var items:[XSCinemaMedia] {
        var original = store.list(kind)
        if kind == .movie && filter == 1 { original = store.freeMovies }
        if query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return original }
        let local = original.filter { $0.title.localizedStandardContains(query) }
        var seen = Set(local.map(\.id))
        return local + remote.filter { seen.insert($0.id).inserted }
    }

    var body:some View {
        ZStack {
            XSNativeCinemaColors.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment:.leading,spacing:16) {
                    VStack(alignment:.leading,spacing:5) {
                        Text(kind == .movie ? "الأفلام" : "المسلسلات")
                            .font(.system(size:30,weight:.bold))
                        Text("\(items.count) عنوان")
                            .font(.caption)
                            .foregroundStyle(XSNativeCinemaColors.muted)
                    }
                    .foregroundStyle(.white)
                    .padding(.top,13)
                    if kind == .movie {
                        Picker("الفئة",selection:$filter) {
                            Text("الكل").tag(0)
                            Text("متاح مجاناً").tag(1)
                        }
                        .pickerStyle(.segmented)
                    }
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:132),spacing:12)],
                              spacing:21) {
                        ForEach(items) { item in
                            NavigationLink { XSCinemaNativeDetailView(media:item) }
                            label: { XSCinemaNativePoster(media:item,width:nil) }
                                .buttonStyle(.plain)
                        }
                    }
                    if !items.isEmpty && query.isEmpty && filter == 0 && store.hasMore(kind) {
                        if store.moreErrors.contains(kind) {
                            Button("إعادة تحميل المزيد") { Task { await store.more(kind) } }
                                .frame(maxWidth: .infinity, minHeight: 44)
                        } else {
                            ProgressView().tint(XSNativeCinemaColors.accent)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .task(id: "\(items.count):\(store.paginationRevision)") { await store.more(kind) }
                        }
                    }
                    if items.isEmpty && !store.loading {
                        Text(store.error ?? "ما فيه نتائج")
                            .font(.subheadline)
                            .foregroundStyle(XSNativeCinemaColors.muted)
                            .frame(maxWidth:.infinity,minHeight:180)
                    }
                }
                .padding(.horizontal,17)
                .padding(.bottom,34)
            }
            .scrollIndicators(.hidden)
        }
        .searchable(text:$query,prompt:"ابحث عن اسم الفيلم أو المسلسل")
        .navigationTitle(kind == .movie ? "Movies" : "Series")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.boot() }
        .onDisappear { searchTask?.cancel() }
        .onChange(of:query) { value in
            remote = []
            searchTask?.cancel()
            guard value.count >= 2 else { remote=[];return }
            searchTask=Task {
                try? await Task.sleep(nanoseconds:420_000_000)
                guard !Task.isCancelled else { return }
                if let results=try? await XSCinemaCatalogAPI.shared.search(value,kind:kind),
                   !Task.isCancelled { remote=results }
            }
        }
    }
}

struct XSCinemaNativeSearchView:View {
    @EnvironmentObject private var store:XSCinemaNativeStore
    @State private var search=""
    @State private var remoteMovies:[XSCinemaMedia]=[]
    @State private var remoteSeries:[XSCinemaMedia]=[]
    @State private var task:Task<Void,Never>?

    private var results:[XSCinemaMedia] {
        guard !search.isEmpty else { return [] }
        let originals=store.movies+store.series+store.freeMovies
        let local=originals.filter { $0.title.localizedStandardContains(search) }
        var ids = Set<String>()
        return Array((local + remoteMovies + remoteSeries)
            .filter { ids.insert($0.id).inserted }
            .prefix(120))
    }

    var body:some View {
        ZStack {
            XSNativeCinemaColors.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment:.leading,spacing:11) {
                    Text("ابحث عن فيلم أو مسلسل")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .padding(.bottom,9)
                    ForEach(results) { item in
                        NavigationLink { XSCinemaNativeDetailView(media:item) } label: {
                            HStack(spacing:13) {
                                XSCinemaNativeArtwork(media:item,landscape:false)
                                    .frame(width:68,height:91)
                                    .clipShape(RoundedRectangle(cornerRadius:10))
                                VStack(alignment:.leading,spacing:6) {
                                    Text(item.title).font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    Text(item.kind.label).font(.caption)
                                        .foregroundStyle(XSNativeCinemaColors.muted)
                                }
                                Spacer()
                                Image(systemName:"chevron.forward")
                                    .foregroundStyle(XSNativeCinemaColors.muted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(17)
            }
        }
        .searchable(text:$search,prompt:"بحث عالمي بالأفلام والمسلسلات")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel() }
        .onChange(of:search) { value in
            task?.cancel()
            remoteMovies=[];remoteSeries=[]
            guard value.count>=2 else{return}
            task=Task {
                try? await Task.sleep(nanoseconds:430_000_000)
                guard !Task.isCancelled else{return}
                async let m=XSCinemaCatalogAPI.shared.search(value,kind:.movie)
                async let s=XSCinemaCatalogAPI.shared.search(value,kind:.series)
                if let movies=try? await m,!Task.isCancelled{remoteMovies=movies}
                if let series=try? await s,!Task.isCancelled{remoteSeries=series}
            }
        }
    }
}

struct XSCinemaNativeDetailView: View {
    let media: XSCinemaMedia
    @EnvironmentObject private var store: XSCinemaNativeStore
    @State private var details: XSCinemaMedia?
    @State private var selection: XSVODPlaybackSelection?
    @State private var watch: XSCinemaWatchRecord?
    @State private var selectedSeason = 1
    @State private var loadingDetails = true
    @State private var expandedSummary = false

    private var item: XSCinemaMedia { details ?? media }
    private var seasons: [Int] { Array(Set(item.episodes.map(\.season))).sorted() }
    private var episodes: [XSCinemaEpisode] {
        item.episodes.filter { $0.season == selectedSeason }.sorted { $0.number < $1.number }
    }
    private var canWatch: Bool {
        guard let raw = item.sourceURL, let url = URL(string: raw) else { return false }
        return XSETWatchRoutes.watchURL(source: url, isSeries: item.kind == .series) != nil
    }
    private func start(_ episode: XSCinemaEpisode? = nil) {
        let season = item.kind == .series ? (episode?.season ?? selectedSeason) : nil
        let number = item.kind == .series ? (episode?.number ?? episodes.first?.number ?? 1) : nil
        watch = XSCinemaWatchRecord(media: item, season: season, episode: number,
                                   position: store.resume(item, season: season, episode: number),
                                   duration: 0, updated: Date())
    }

    var body: some View {
        ZStack {
            XSAtmosphericCinemaBackdropV27()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ZStack(alignment: .bottomLeading) {
                        XSCinemaNativeArtwork(media: item, landscape: true).frame(height: 350)
                        LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(item.kind.label.uppercased())
                                .font(.caption2.bold()).tracking(2).foregroundStyle(XSNativeCinemaColors.accent)
                            Text(item.title).font(.system(size: 30, weight: .bold, design: .rounded))
                                .foregroundStyle(.white).lineLimit(3)
                        }
                        .padding(21)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    HStack(spacing: 14) {
                        if !item.year.isEmpty { Text(item.year) }
                        if item.rating > 0 {
                            Label(String(format: "%.1f", item.rating), systemImage: "star.fill")
                        }
                        if !seasons.isEmpty { Text("\(seasons.count) مواسم") }
                    }
                    .font(.caption.bold()).foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 12) {
                        if let url = item.streamURL, item.isPlayable {
                            Button {
                                selection = XSVODPlaybackSelection(url: url, title: item.title, fallbackURL: nil)
                            } label: { playLabel }
                            .buttonStyle(.borderedProminent).tint(XSNativeCinemaColors.accent)
                        } else if canWatch {
                            Button { start() } label: { playLabel }
                                .buttonStyle(.borderedProminent).tint(XSNativeCinemaColors.accent)
                        } else if loadingDetails {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 48)
                        } else {
                            Text("المشاهدة غير متاحة لهذا العنوان حالياً")
                                .font(.caption).foregroundStyle(.white.opacity(0.65))
                        }
                        Button { store.toggle(item) } label: {
                            Image(systemName: store.favorite(item) ? "checkmark" : "plus")
                                .font(.system(size: 20, weight: .medium)).frame(width: 35, height: 36)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(store.favorite(item) ? "إزالة من قائمتي" : "أضف إلى قائمتي")
                    }
                    if !item.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.summary).font(.subheadline).lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.76)).lineLimit(expandedSummary ? nil : 4)
                            Button(expandedSummary ? "عرض أقل" : "قراءة المزيد") { expandedSummary.toggle() }
                                .font(.caption.bold()).tint(XSNativeCinemaColors.accent)
                        }
                    }
                    if item.kind == .series {
                        VStack(alignment: .leading, spacing: 14) {
                            if !seasons.isEmpty {
                                XSSeasonStripV27(seasons: seasons, selected: $selectedSeason)
                                ForEach(episodes) { episode in
                                    Button { start(episode) } label: { XSEpisodePosterRowV27(episode: episode) }
                                        .buttonStyle(.plain).disabled(!canWatch)
                                }
                            } else if loadingDetails {
                                ProgressView("تحميل الحلقات…").tint(XSNativeCinemaColors.accent)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                            } else {
                                Text("تعذر تحميل الحلقات حالياً").font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }
                }
                .padding(.horizontal, 17).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
        .task(id: media.id) {
            loadingDetails = true
            let refreshed = await XSCinemaCatalogAPI.shared.detail(media)
            guard !Task.isCancelled else { return }
            details = refreshed
            selectedSeason = seasons.first ?? 1
            loadingDetails = false
        }
        .fullScreenCover(item: $selection) { chosen in XSVODVLCPlayerView(source: chosen) }
        .fullScreenCover(item: $watch) { chosen in
            if let url = chosen.watchURL {
                XSETWatchNativeDetailPlayer(url: url, title: chosen.title,
                    season: chosen.season, episode: chosen.episode, resumePosition: chosen.position,
                    onProgress: { time, duration in
                        store.saveProgress(chosen.media, season: chosen.season, episode: chosen.episode,
                                           position: time, duration: duration)
                    })
            }
        }
    }
    private var playLabel: some View {
        Label("شاهد الآن", systemImage: "play.fill")
            .font(.subheadline.bold()).foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 42)
    }
}

private struct XSCinemaNativePoster:View {
    let media:XSCinemaMedia
    let width:CGFloat?
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            XSCinemaNativeArtwork(media:media,landscape:false)
                .aspectRatio(0.69,contentMode:.fit)
                .clipShape(RoundedRectangle(cornerRadius:14))
            Text(media.title)
                .font(.system(size:12,weight:.semibold))
                .lineLimit(2)
                .foregroundStyle(.white)
            HStack(spacing:5) {
                if media.isPlayable {
                    Image(systemName:"play.circle.fill")
                    Text("متاح")
                } else {
                    Text(media.kind.label)
                }
                Spacer(minLength:0)
                if media.rating>0 {
                    Image(systemName:"star.fill")
                    Text(String(format:"%.1f",media.rating))
                }
            }
            .font(.caption2)
            .foregroundStyle(XSNativeCinemaColors.muted)
        }
        .frame(width:width,alignment:.leading)
    }
}

private struct XSCinemaNativeArtwork:View {
    let media:XSCinemaMedia
    let landscape:Bool
    var body:some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors:[XSNativeCinemaColors.tile,.purple.opacity(0.22),
                                       XSNativeCinemaColors.background],
                               startPoint:.topLeading,endPoint:.bottomTrailing)
                if let url=landscape ? media.backdropURL : media.imageURL {
                    XSCinemaImage(url: url, maxDimension: landscape ? 1200 : 500)
                } else {
                    Image(systemName:media.kind == .movie ? "film.stack":"play.tv")
                        .font(.system(size:40,weight:.thin))
                        .foregroundStyle(.white.opacity(0.24))
                }
            }
            .frame(width:geo.size.width,height:geo.size.height)
            .clipped()
        }
    }
}
