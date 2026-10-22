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

struct XSCinemaNativeHomeView: View {
    @EnvironmentObject private var store: XSCinemaNativeStore
    private var featured: XSCinemaMedia? { store.movies.first ?? store.freeMovies.first }

    var body: some View {
        ZStack {
            XSNativeCinemaColors.background.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment:.leading,spacing:24) {
                    if let featured {
                        NavigationLink {
                            XSCinemaNativeDetailView(media: featured)
                        } label: { featuredArtwork(featured) }
                            .buttonStyle(.plain)
                    } else {
                        headerPlaceholder
                    }

                    HStack(spacing:13) {
                        NavigationLink { XSCinemaNativeBrowseView(kind:.movie) }
                            label: { navCard("الأفلام","film.stack.fill",count:store.movies.count) }
                        NavigationLink { XSCinemaNativeBrowseView(kind:.series) }
                            label: { navCard("المسلسلات","play.tv.fill",count:store.series.count) }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal,18)

                    posterRail("أفلام عالمية","POPULAR MOVIES",items:store.movies)
                    posterRail("مسلسلات عالمية","TOP SERIES",items:store.series)
                    if !store.freeMovies.isEmpty {
                        posterRail("متاحة للمشاهدة مجاناً","OPEN LICENSE STREAMS",items:store.freeMovies)
                    }
                    if !store.favorites.isEmpty {
                        posterRail("قائمتي","WATCHLIST",
                            items:(store.movies + store.series + store.freeMovies)
                                .filter { store.favorites.contains($0.id) })
                    }
                    VStack(alignment:.leading,spacing:7) {
                        Text("مكتبة مستقلة عن IPTV")
                            .font(.subheadline.bold())
                        Text("هذي واجهة نيتيف لفهرس الأفلام والمسلسلات. الأعمال اللي لها حقوق تشغيل متاحة فقط يظهر لها زر مشاهدة. مصدر ETWatch ما زال يحتاج واجهة رسمية لربط مكتبته ومشغله.")
                            .font(.caption)
                            .foregroundStyle(XSNativeCinemaColors.muted)
                    }
                    .padding(17)
                    .frame(maxWidth:.infinity,alignment:.leading)
                    .background(XSNativeCinemaColors.tile,
                                in:RoundedRectangle(cornerRadius:15))
                    .padding(.horizontal,18)
                }
                .padding(.bottom,45)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.boot() }
        }
        .overlay(alignment:.topTrailing) {
            NavigationLink { XSCinemaNativeSearchView() } label: {
                Image(systemName:"magnifyingglass")
                    .font(.system(size:18,weight:.semibold))
                    .foregroundStyle(.white)
                    .frame(width:47,height:47)
                    .background(.black.opacity(0.65),in:Circle())
            }
            .padding(19)
        }
        .toolbar(.hidden,for:.navigationBar)
        .task { await store.boot() }
    }

    private func featuredArtwork(_ item:XSCinemaMedia)->some View {
        ZStack(alignment:.bottomLeading) {
            XSCinemaNativeArtwork(media:item,landscape:true)
                .frame(height:465)
            LinearGradient(colors:[.clear,.black.opacity(0.38),
                                   XSNativeCinemaColors.background],
                           startPoint:.top,endPoint:.bottom)
            VStack(alignment:.leading,spacing:11) {
                Text("XS TV   ·   FEATURED")
                    .font(.caption2.bold())
                    .tracking(2.8)
                    .foregroundStyle(XSNativeCinemaColors.accent)
                Text(item.title)
                    .font(.system(size:31,weight:.black,design:.rounded))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                HStack(spacing:10) {
                    Image(systemName:item.isPlayable ? "play.fill":"info.circle.fill")
                    Text(item.isPlayable ? "شاهد الآن" : "التفاصيل")
                }
                .font(.subheadline.bold())
                .frame(width:148,height:43)
                .foregroundStyle(.black)
                .background(.white,in:Capsule())
            }
            .padding(.horizontal,22)
            .padding(.bottom,24)
        }
    }

    private var headerPlaceholder:some View {
        VStack(alignment:.leading,spacing:13) {
            XSBrandMark(size:95)
            Text("السينما بين يديك")
                .font(.largeTitle.bold())
            if store.loading {
                ProgressView("نجلب أحدث الأفلام والمسلسلات")
                    .tint(XSNativeCinemaColors.accent)
            } else {
                Text(store.error ?? "مكتبة المحتوى غير متوفرة الآن.")
                    .foregroundStyle(XSNativeCinemaColors.muted)
            }
        }
        .frame(maxWidth:.infinity,minHeight:320,alignment:.bottomLeading)
        .padding(22)
    }

    private func navCard(_ title:String,_ symbol:String,count:Int)->some View {
        HStack(spacing:12) {
            Image(systemName:symbol).font(.system(size:21))
                .foregroundStyle(XSNativeCinemaColors.accent)
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.subheadline.bold())
                Text("\(count) عنوان").font(.caption2)
                    .foregroundStyle(XSNativeCinemaColors.muted)
            }
            Spacer(minLength:0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(XSNativeCinemaColors.tile,
                    in:RoundedRectangle(cornerRadius:15))
    }

    @ViewBuilder
    private func posterRail(_ title:String,_ eyebrow:String,items:[XSCinemaMedia])->some View {
        if !items.isEmpty {
            VStack(alignment:.leading,spacing:12) {
                VStack(alignment:.leading,spacing:5) {
                    Text(eyebrow)
                        .font(.system(size:10,weight:.bold))
                        .tracking(2.3)
                        .foregroundStyle(XSNativeCinemaColors.accent)
                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal,19)
                ScrollView(.horizontal) {
                    LazyHStack(spacing:12) {
                        ForEach(Array(items.prefix(30))) { item in
                            NavigationLink { XSCinemaNativeDetailView(media:item) }
                            label: { XSCinemaNativePoster(media:item,width:145) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal,19)
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
        var ids=Set(local.map(\.id))
        return Array((local+remoteMovies+remoteSeries)
            .filter { ids.insert($0.id).inserted == false ? local.contains($0) : true }
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
                        Label("هذا العنوان موجود في الفهرس فقط. ما توفر له رابط تشغيل مصرح به، ولا بنعرض زر تشغيل وهمي.",
                              systemImage:"info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.95))
                    } else {
                        Text("تشغيل مباشر من مصدر مفتوح الترخيص. اختيار الترجمة يعتمد على المسارات التي يوفرها الملف.")
                            .font(.caption)
                            .foregroundStyle(XSNativeCinemaColors.muted)
                    }
                    if item.kind == .series {
                        VStack(alignment:.leading,spacing:13) {
                            Text("المواسم والحلقات").font(.title3.bold())
                            if !seasons.isEmpty {
                                Picker("الموسم",selection:$selectedSeason) {
                                    ForEach(seasons,id:\.self) {
                                        Text("الموسم \($0)").tag($0)
                                    }
                                }
                                .pickerStyle(.menu)
                                ForEach(item.episodes.filter{$0.season==selectedSeason}) { ep in
                                    HStack(spacing:12) {
                                        Image(systemName:"play.rectangle")
                                            .frame(width:53,height:51)
                                            .background(XSNativeCinemaColors.tile,
                                                        in:RoundedRectangle(cornerRadius:11))
                                        VStack(alignment:.leading,spacing:4) {
                                            Text("\(ep.number). \(ep.title)")
                                                .font(.subheadline.bold())
                                            Text("Episode \(ep.number)")
                                                .font(.caption2)
                                                .foregroundStyle(XSNativeCinemaColors.muted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical,4)
                                }
                                Text("بيانات الحلقات متوفرة للفهرسة، وليس لدينا روابط مرخصة لتشغيلها.")
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
                        Link("معلومات المصدر ورخصته",destination:url)
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
