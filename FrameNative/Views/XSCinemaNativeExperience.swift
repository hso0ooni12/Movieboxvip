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
    static let accent = Color(red:0.99,green:0.27,blue:0.36)
    static let muted = Color.white.opacity(0.64)
}

// Editorial, native-first home: restrained typography, one hero and
// compact poster carousels. No nested browser nav or marketing text cards.
struct XSCinemaNativeHomeView: View {
    @EnvironmentObject private var store: XSCinemaNativeStore
    @State private var revealed = false
    private var featured: XSCinemaMedia? { store.movies.first ?? store.freeMovies.first }

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

                    posterRail("أفلام تستحق المشاهدة", items: store.movies)
                    posterRail("مسلسلات مختارة", items: store.series)
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
            .refreshable { await store.boot() }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await store.boot() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.42)) { revealed = true }
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
                    if !items.isEmpty && query.isEmpty && filter == 0 {
                        Button {
                            Task { await store.more(kind) }
                        } label: {
                            HStack(spacing:10) {
                                if store.loadingMore.contains(kind) {
                                    ProgressView().tint(.white)
                                }
                                Text("عرض المزيد")
                            }
                            .frame(maxWidth:.infinity,minHeight:47)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(XSNativeCinemaColors.accent)
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
        .onChange(of:query) { value in
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

struct XSCinemaNativeDetailView:View {
    let media:XSCinemaMedia
    @EnvironmentObject private var store:XSCinemaNativeStore
    @State private var details:XSCinemaMedia?
    @State private var selection:XSVODPlaybackSelection?
    @State private var selectedSeason=1
    @State private var showWebsitePlayer=false
    @State private var selectedWebsiteEpisode: XSCinemaEpisode?

    private var item:XSCinemaMedia { details ?? media }
    private var seasons:[Int] { Array(Set(item.episodes.map(\.season))).sorted() }

    var body:some View {
        ZStack {
            XSNativeCinemaColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment:.leading,spacing:17) {
                    XSCinemaNativeArtwork(media:item,landscape:true)
                        .frame(height:330)
                        .clipShape(RoundedRectangle(cornerRadius:16))
                    Text(item.title)
                        .font(.system(size:28,weight:.bold))
                        .foregroundStyle(.white)
                    HStack(spacing:14) {
                        Text(item.kind.label)
                        if !item.year.isEmpty { Text(item.year) }
                        if item.rating>0 {
                            Label(String(format:"%.1f",item.rating),systemImage:"star.fill")
                        }
                    }
                    .font(.caption.bold())
                    .foregroundStyle(XSNativeCinemaColors.muted)
                    HStack(spacing:12) {
                        if let url=item.streamURL, item.isPlayable {
                            Button {
                                selection=XSVODPlaybackSelection(url:url,title:item.title,fallbackURL:nil)
                            } label: {
                                Label("شاهد الآن",systemImage:"play.fill")
                                    .frame(maxWidth:.infinity,minHeight:45)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(XSNativeCinemaColors.accent)
                        }
                        if let source=item.sourceURL, let url=URL(string:source),
                           url.host=="www.etwatch.net" || url.host=="etwatch.net",
                           !item.isPlayable {
                            Button {
                                selectedWebsiteEpisode = nil
                                showWebsitePlayer=true
                            } label: {
                                Label(item.kind == .movie ? "مشاهدة على ETWatch" : "فتح مشغل المسلسل",
                                      systemImage:"play.fill")
                                    .frame(maxWidth:.infinity,minHeight:45)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(XSNativeCinemaColors.accent)
                        }
                        Button {
                            store.toggle(item)
                        } label: {
                            Label(store.favorite(item) ? "في قائمتي":"قائمتي",
                                  systemImage:store.favorite(item) ? "checkmark":"plus")
                                .frame(minHeight:45)
                        }
                        .buttonStyle(.bordered)
                    }
                    if !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.79))
                    }
                    if !item.isPlayable {
                        Label(item.sourceURL != nil
                              ? "ينفتح مشغل الموقع الأصلي بشكل منفصل. توفر الفيديو والترجمة يعتمد على السيرفر، وبيظهر تنبيه إذا علّق التشغيل."
                              : "هذا العنوان موجود في الفهرس، لكن ما عندنا له رابط مشاهدة مؤكد.",
                              systemImage:"info.circle")
                            .font(.caption)
                            .foregroundStyle(XSNativeCinemaColors.muted)
                    } else {
                        Text("تشغيل مباشر من مصدر مفتوح الترخيص. اختيار الترجمة يعتمد على المسارات التي يوفرها الملف.")
                            .font(.caption)
                            .foregroundStyle(XSNativeCinemaColors.muted)
                    }
                    if item.kind == .series {
                        VStack(alignment:.leading,spacing:13) {
                            Text("المواسم والحلقات").font(.title3.bold())
                            if !seasons.isEmpty {
                                XSSeasonStripV27(seasons: seasons, selected: $selectedSeason)
                                ForEach(item.episodes.filter{$0.season==selectedSeason}) { ep in
                                    Button {
                                        selectedWebsiteEpisode = ep
                                        showWebsitePlayer = true
                                    } label: {
                                        XSEpisodePosterRowV27(episode: ep)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Text("الضغط على الحلقة يحاول فتحها مباشرة من قائمة الموقع. إذا تغيّر الموقع قد تحتاج اختيارها من مشغله.")
                                    .font(.caption2)
                                    .foregroundStyle(XSNativeCinemaColors.muted)
                            } else {
                                Text("ما توفرت بيانات الحلقات لهذا العمل.")
                                    .foregroundStyle(XSNativeCinemaColors.muted)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.top,10)
                    }
                    if let source=item.sourceURL, let url=URL(string:source) {
                        Link(item.isPlayable ? "معلومات المصدر ورخصته" : "صفحة المشاهدة الأصلية",destination:url)
                            .font(.footnote)
                    }
                }
                .padding(.horizontal,17)
                .padding(.bottom,45)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id:media.id) {
            if media.kind == .series {
                details=await XSCinemaCatalogAPI.shared.detail(media)
                selectedSeason=seasons.first ?? 1
            }
        }
        .fullScreenCover(item:$selection) { chosen in
            XSVODVLCPlayerView(source:chosen)
        }
        .fullScreenCover(isPresented:$showWebsitePlayer) {
            if let source=item.sourceURL, let url=URL(string:source) {
                XSETWatchNativeDetailPlayer(
                    url: url,
                    title: selectedWebsiteEpisode.map { "\(item.title)  S\($0.season) E\($0.number)" } ?? item.title,
                    season: selectedWebsiteEpisode?.season,
                    episode: selectedWebsiteEpisode?.number)
            }
        }
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
                    AsyncImage(url:url,transaction:Transaction(animation:nil)) { phase in
                        if case .success(let image)=phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName:media.kind == .movie ? "film.stack":"play.tv")
                                .font(.system(size:36,weight:.thin))
                                .foregroundStyle(.white.opacity(0.24))
                        }
                    }
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
