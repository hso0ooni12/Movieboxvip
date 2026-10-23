import SwiftUI

// XS TV V27: complete cinematic presentation layer, independently testable
// from the content provider and player. Former V24/25 layouts are excluded
// from the device build. Only real catalog items are presented.
struct XSVODPlaybackSelection: Identifiable {
    let url: URL
    let title: String
    let fallbackURL: URL?
    var id: String { url.absoluteString }
}

private enum XSPalette {
    static let canvas = Color(red: 0.024, green: 0.026, blue: 0.044)
    static let card = Color(red: 0.088, green: 0.083, blue: 0.127)
    static let accent = Color(red: 0.99, green: 0.30, blue: 0.44)
    static let blue = Color(red: 0.44, green: 0.70, blue: 0.98)
    static let gold = Color(red: 1.0, green: 0.78, blue: 0.49)
    static let second = Color.white.opacity(0.66)
    static let stroke = Color.white.opacity(0.12)
}

struct XSPremiumCinemaBackdrop: View {
    var body: some View {
        ZStack {
            XSPalette.canvas
            RadialGradient(colors: [XSPalette.accent.opacity(0.17), .clear],
                           center: .topTrailing, startRadius: 10, endRadius: 370)
            RadialGradient(colors: [.indigo.opacity(0.12), .clear],
                           center: .bottomLeading, startRadius: 10, endRadius: 430)
        }
        .ignoresSafeArea()
    }
}

private struct XSPremiumGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(XSPalette.stroke, lineWidth: 1))
    }
}

private struct XSPremiumPoster: View {
    let movie: XSCinemaMedia
    var width: CGFloat = 142
    var large: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                XSPremiumImage(url: movie.imageURL, symbol: movie.kind == .movie ? "film.fill" : "play.tv.fill")
                    .aspectRatio(0.70, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: large ? 20 : 15, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: large ? 20 : 15)
                        .stroke(XSPalette.stroke, lineWidth: 1))
                if movie.rating > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(XSPalette.gold)
                        Text(String(format: "%.1f", movie.rating))
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.77), in: Capsule())
                    .padding(8)
                }
            }
            Text(movie.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                Text(movie.kind == .movie ? "MOVIE" : "SERIES")
                if !movie.year.isEmpty {
                    Text("·")
                    Text(movie.year.prefix(4))
                }
            }
            .font(.system(size: 10, weight: .medium))
            .tracking(0.8)
            .foregroundStyle(XSPalette.second)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct XSPremiumImage: View {
    let url: URL?
    let symbol: String
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red:0.14, green:0.10, blue:0.20),
                                        XSPalette.canvas],
                               startPoint:.topLeading,endPoint:.bottomTrailing)
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.24))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .transition(.opacity)
                        default:
                            Image(systemName: symbol)
                                .font(.system(size: 34, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 34, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

private struct XSPremiumSectionTitle: View {
    let eyebrow: String
    let title: String
    var count: Int? = nil
    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(2.4)
                    .foregroundStyle(XSPalette.accent)
                Text(title)
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
            }
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(XSPalette.second)
            }
        }
        .padding(.horizontal, 20)
    }
}

struct XSPremiumCinemaHome: View {
    @EnvironmentObject private var library: XSCinemaNativeStore
    @State private var featuredIndex = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var feature: [XSCinemaMedia] {
        Array((library.movies + library.series.prefix(2)).prefix(5))
    }
    private var selected: XSCinemaMedia? {
        guard !feature.isEmpty else { return nil }
        return feature[min(featuredIndex, feature.count - 1)]
    }
    private var saved: [XSCinemaMedia] {
        (library.movies + library.series + library.freeMovies).filter { library.favorites.contains($0.id) }
    }

    var body: some View {
        ZStack {
            XSPremiumCinemaBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let item = selected {
                        hero(item)
                    } else {
                        heroPlaceholder
                    }
                    if feature.count > 1 { featurePicker.padding(.top, 7) }
                    destinations.padding(.top, 29)
                    if !saved.isEmpty { rail("YOUR COLLECTION", "قائمتي", items: saved, width: 132).padding(.top, 31) }
                    if !library.movies.isEmpty {
                        rankedRail.padding(.top, 32)
                    }
                    rail("HANDPICKED FOR TONIGHT", "أفلام تستحق المشاهدة", items: library.movies, width: 147)
                        .padding(.top, 34)
                    rail("YOUR NEXT OBSESSION", "مسلسلات عالمية", items: library.series, width: 147)
                        .padding(.top, 34)
                    if !library.freeMovies.isEmpty {
                        rail("OPEN-LICENSE STREAMS", "متاح مجاناً الآن", items: library.freeMovies, width: 136)
                            .padding(.top, 34)
                    }
                    footer.padding(.top, 40)
                }
                .padding(.bottom, 66)
                .opacity(appeared ? 1 : 0.02)
                .offset(y: appeared ? 0 : (reduceMotion ? 0 : 14))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.50), value: appeared)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .refreshable { await library.boot() }
        }
        .overlay(alignment: .top) { header }
        .toolbar(.hidden, for: .navigationBar)
        .task { await library.boot() }
        .onAppear { appeared = true }
    }

    private var header: some View {
        HStack(spacing: 13) {
            XSWordmark(compact: true)
            Spacer()
            NavigationLink {
                XSPremiumSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 41, height: 43)
            }
            NavigationLink {
                XSPremiumWatchlist()
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 41, height: 43)
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 10)
        .background {
            LinearGradient(colors: [XSPalette.canvas.opacity(0.97),
                                    XSPalette.canvas.opacity(0.12)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        }
    }

    private func hero(_ item: XSCinemaMedia) -> some View {
        ZStack(alignment: .bottomLeading) {
            XSPremiumImage(url: item.backdropURL, symbol: "play.rectangle.fill")
                .frame(height: 555)
                .id(item.id)
                .transition(.opacity)
            LinearGradient(stops: [
                .init(color: .black.opacity(0.40), location: 0),
                .init(color: .clear, location: 0.25),
                .init(color: XSPalette.canvas.opacity(0.35), location: 0.52),
                .init(color: XSPalette.canvas.opacity(0.94), location: 0.87),
                .init(color: XSPalette.canvas, location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Circle().fill(XSPalette.accent).frame(width: 7, height: 7)
                    Text("XS PREMIERE").tracking(2.2)
                    Spacer()
                    Text(String(format: "%02d / %02d", featuredIndex+1, feature.count))
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.90))
                Spacer(minLength: 10)
                Text("THE SPOTLIGHT")
                    .font(.system(size: 10, weight: .black))
                    .tracking(2.6)
                    .foregroundStyle(XSPalette.gold)
                Text(item.title)
                    .font(.system(size: 37, weight: .black, design: .rounded))
                    .tracking(-1.2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.white)
                    .padding(.top, 9)
                HStack(spacing: 10) {
                    if !item.year.isEmpty { Text(item.year.prefix(4)) }
                    Text(item.kind == .movie ? "FILM" : "SERIES")
                    if item.rating > 0 {
                        Image(systemName: "star.fill").foregroundStyle(XSPalette.gold)
                        Text(String(format:"%.1f", item.rating))
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.top, 11)
                if !item.summary.isEmpty {
                    Text(item.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                        .lineSpacing(3)
                        .padding(.top, 12)
                }
                HStack(spacing: 11) {
                    NavigationLink {
                        XSPremiumCinemaDetail(media: item)
                    } label: {
                        Label("استكشف العمل", systemImage:"play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.black)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    }
                    NavigationLink {
                        XSPremiumBrowse(kind: item.kind)
                    } label: {
                        Label("تصفح", systemImage:"square.grid.2x2")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 15))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(XSPalette.stroke))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
            }
            .padding(.horizontal, 22)
            .padding(.top, 120)
            .padding(.bottom, 26)
        }
        .frame(height: 555)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 60).onEnded { gesture in
            guard feature.count > 1, abs(gesture.translation.width) > 65 else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                featuredIndex = (featuredIndex + feature.count + (gesture.translation.width < 0 ? 1 : -1)) % feature.count
            }
        })
    }

    private var heroPlaceholder: some View {
        ZStack {
            XSPremiumCinemaBackdrop()
            VStack(spacing: 15) {
                XSBrandMark(size: 90)
                Text("THE CINEMA STARTS HERE")
                    .font(.system(size: 13, weight: .bold)).tracking(1.3)
                ProgressView().tint(XSPalette.accent)
                Text("نجهّز مكتبة الأفلام والمسلسلات")
                    .font(.footnote).foregroundStyle(XSPalette.second)
            }
        }
        .frame(height: 430)
    }

    private var featurePicker: some View {
        HStack(spacing: 9) {
            ForEach(feature.indices, id:\.self) { index in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { featuredIndex = index }
                } label: {
                    XSPremiumImage(url: feature[index].imageURL, symbol:"film")
                        .frame(maxWidth: .infinity)
                        .frame(height: 73)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(index == featuredIndex ? XSPalette.accent : XSPalette.stroke,
                                    lineWidth: index == featuredIndex ? 2.5 : 1))
                        .opacity(index == featuredIndex ? 1 : 0.62)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: 12) {
            XSPremiumSectionTitle(eyebrow:"EXPLORE XS TV", title:"وين تبي تروح؟")
            HStack(spacing: 11) {
                NavigationLink {
                    XSPremiumBrowse(kind: .movie)
                } label: { destinationCard("Movies", "THE BIG SCREEN", "film.stack", XSPalette.gold) }
                NavigationLink {
                    XSPremiumBrowse(kind: .series)
                } label: { destinationCard("Series", "ONE MORE EPISODE", "play.tv", XSPalette.blue) }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
    }

    private func destinationCard(_ text: String, _ eyebrow: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Image(systemName: symbol)
                .font(.system(size: 29, weight: .ultraLight))
                .foregroundStyle(tint)
                .frame(height: 38)
            Spacer(minLength: 0)
            Text(eyebrow)
                .font(.system(size: 8, weight: .black))
                .tracking(1.2)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 23, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            HStack {
                Text("Discover")
                    .font(.caption2.bold())
                Spacer()
                Image(systemName:"arrow.up.right")
            }
            .foregroundStyle(XSPalette.second)
        }
        .padding(18)
        .frame(maxWidth:.infinity)
        .frame(height:190)
        .background(LinearGradient(colors: [XSPalette.card, tint.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius:20))
        .overlay(RoundedRectangle(cornerRadius:20).stroke(tint.opacity(0.17)))
    }

    private var rankedRail: some View {
        VStack(alignment: .leading, spacing: 12) {
            XSPremiumSectionTitle(eyebrow:"MOST DISCOVERED",title:"الأكثر رواجاً")
            ScrollView(.horizontal) {
                LazyHStack(alignment:.bottom,spacing:16) {
                    ForEach(Array(library.movies.prefix(10).enumerated()), id:\.element.id) { idx, movie in
                        NavigationLink {
                            XSPremiumCinemaDetail(media: movie)
                        } label: {
                            ZStack(alignment:.bottomLeading) {
                                Text("\(idx+1)")
                                    .font(.system(size: 105, weight: .black, design: .rounded))
                                    .foregroundStyle(XSPalette.gold.opacity(0.70))
                                    .offset(x:-5,y:13)
                                XSPremiumPoster(movie:movie,width:128)
                                    .padding(.leading,36)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal,20)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func rail(_ eyebrow:String,_ title:String,items:[XSCinemaMedia],width:CGFloat) -> some View {
        if !items.isEmpty {
            VStack(alignment:.leading,spacing:13) {
                XSPremiumSectionTitle(eyebrow:eyebrow,title:title,count:items.count)
                ScrollView(.horizontal) {
                    LazyHStack(spacing:14) {
                        ForEach(Array(items.prefix(30))) { item in
                            NavigationLink {
                                XSPremiumCinemaDetail(media:item)
                            } label: {
                                XSPremiumPoster(movie:item,width:width)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal,20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var footer: some View {
        HStack(spacing:10) {
            Image(systemName:"sparkles.tv")
                .foregroundStyle(XSPalette.gold)
            Text("CINEMA · SERIES · LIVE SPORTS")
                .font(.system(size:10,weight:.bold))
                .tracking(1.9)
                .foregroundStyle(XSPalette.second)
        }
        .frame(maxWidth:.infinity)
        .padding(.bottom,24)
    }
}

struct XSPremiumBrowse: View {
    let kind: XSCinemaMediaKind
    @EnvironmentObject private var library: XSCinemaNativeStore
    @State private var text = ""
    @State private var remote: [XSCinemaMedia] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var freeOnly = false

    private var items:[XSCinemaMedia] {
        let base = freeOnly && kind == .movie ? library.freeMovies : library.list(kind)
        if text.isEmpty { return base }
        let local = base.filter { $0.title.localizedStandardContains(text) }
        var ids = Set<String>()
        return (local + remote).filter { ids.insert($0.id).inserted }
    }

    var body: some View {
        ZStack {
            XSPremiumCinemaBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(kind == .movie ? "CINEMA COLLECTION" : "STORIES & SEASONS")
                            .font(.system(size:10,weight:.black))
                            .tracking(2.8)
                            .foregroundStyle(XSPalette.accent)
                        Text(kind == .movie ? "الأفلام" : "المسلسلات")
                            .font(.system(size:37,weight:.black,design:.rounded))
                        Text("اكتشف، احفظ في قائمتك، وتابع تفاصيل الأعمال")
                            .font(.footnote).foregroundStyle(XSPalette.second)
                    }
                    .padding(.top,22)
                    if kind == .movie {
                        HStack(spacing:10) {
                            filterChip("الكل",active:!freeOnly) { freeOnly=false }
                            filterChip("متاح مجاناً",active:freeOnly) { freeOnly=true }
                        }
                    }
                    HStack {
                        Text("EXPLORE").tracking(2).foregroundStyle(XSPalette.accent)
                        Spacer()
                        Text("\(items.count) TITLES").foregroundStyle(XSPalette.second)
                    }
                    .font(.system(size:10,weight:.bold))
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:130),spacing:13)],
                              spacing:22) {
                        ForEach(items) { item in
                            NavigationLink {
                                XSPremiumCinemaDetail(media:item)
                            } label: { XSPremiumPoster(movie:item,width:145) }
                            .buttonStyle(.plain)
                        }
                    }
                    if !items.isEmpty && text.isEmpty && !freeOnly {
                        Button {
                            Task { await library.more(kind) }
                        } label: {
                            HStack(spacing:10) {
                                if library.loadingMore.contains(kind) { ProgressView().tint(.white) }
                                Text("اكتشف المزيد")
                            }
                            .font(.subheadline.bold())
                            .frame(maxWidth:.infinity,minHeight:49)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(XSPalette.accent)
                        .disabled(library.loadingMore.contains(kind))
                    }
                    if items.isEmpty {
                        ContentUnavailableViewPlaceholder(text: text, sourceError: library.error)
                    }
                }
                .padding(.horizontal,18)
                .padding(.bottom,48)
            }
            .scrollIndicators(.hidden)
        }
        .searchable(text:$text,prompt:"ابحث عن فيلم أو مسلسل")
        .navigationTitle(kind == .movie ? "Movies" : "Series")
        .navigationBarTitleDisplayMode(.inline)
        .task { await library.boot() }
        .onChange(of:text) { keyword in
            searchTask?.cancel()
            remote=[]
            guard keyword.count >= 2 else { return }
            searchTask = Task {
                try? await Task.sleep(nanoseconds:420_000_000)
                guard !Task.isCancelled else { return }
                if let list = try? await XSCinemaCatalogAPI.shared.search(keyword, kind: kind),
                   !Task.isCancelled { remote=list }
            }
        }
    }

    private func filterChip(_ title:String,active:Bool,action:@escaping ()->Void)->some View {
        Button(action:action) {
            Text(title)
                .font(.system(size:12,weight:.bold))
                .foregroundStyle(active ? .white : XSPalette.second)
                .padding(.horizontal,16)
                .frame(height:38)
                .background(active ? XSPalette.accent.opacity(0.77) : XSPalette.card,
                            in: Capsule())
                .overlay(Capsule().stroke(active ? XSPalette.accent : XSPalette.stroke))
        }
        .buttonStyle(.plain)
    }
}

private struct ContentUnavailableViewPlaceholder: View {
    let text:String
    let sourceError:String?
    var body:some View {
        VStack(spacing:12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size:34,weight:.light))
            Text(text.isEmpty ? "ما فيه عناوين في هذا القسم حالياً" : "ما لقينا نتائج مطابقة")
                .font(.subheadline.bold())
            if let sourceError {
                Text(sourceError).font(.caption).foregroundStyle(XSPalette.second)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth:.infinity,minHeight:200)
    }
}

struct XSPremiumSearch: View {
    @EnvironmentObject private var library:XSCinemaNativeStore
    @State private var text=""
    @State private var remoteMovies:[XSCinemaMedia]=[]
    @State private var remoteShows:[XSCinemaMedia]=[]
    @State private var searchTask:Task<Void,Never>?

    private var items:[XSCinemaMedia] {
        guard text.count >= 1 else { return [] }
        let local=(library.movies+library.series+library.freeMovies)
            .filter { $0.title.localizedStandardContains(text) }
        var ids=Set<String>()
        return Array((local+remoteMovies+remoteShows)
            .filter { ids.insert($0.id).inserted }.prefix(80))
    }

    var body:some View {
        ZStack {
            XSPremiumCinemaBackdrop()
            ScrollView {
                LazyVStack(alignment:.leading,spacing:16) {
                    XSPremiumSectionTitle(eyebrow:"DISCOVER",title:"البحث")
                    ForEach(items) { item in
                        NavigationLink {
                            XSPremiumCinemaDetail(media:item)
                        } label: {
                            HStack(spacing:13) {
                                XSPremiumImage(url:item.imageURL,symbol:"film")
                                    .frame(width:71,height:94)
                                    .clipShape(RoundedRectangle(cornerRadius:11))
                                VStack(alignment:.leading,spacing:7) {
                                    Text(item.title)
                                        .font(.subheadline.bold())
                                    Text(item.kind == .movie ? "MOVIE" : "SERIES")
                                        .font(.caption2)
                                        .tracking(1.2)
                                        .foregroundStyle(XSPalette.second)
                                }
                                Spacer()
                                Image(systemName:"chevron.right")
                                    .foregroundStyle(XSPalette.second)
                            }
                            .foregroundStyle(.white)
                            .padding(8)
                            .modifier(XSPremiumGlass())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal,17)
                    }
                }
                .padding(.top,19)
                .padding(.bottom,40)
            }
        }
        .searchable(text:$text,prompt:"بحث عالمي عن الأفلام والمسلسلات")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of:text) { keyword in
            searchTask?.cancel()
            remoteMovies=[];remoteShows=[]
            guard keyword.count>=2 else{return}
            searchTask=Task {
                try? await Task.sleep(nanoseconds:430_000_000)
                guard !Task.isCancelled else{return}
                async let movies=XSCinemaCatalogAPI.shared.search(keyword,kind:.movie)
                async let shows=XSCinemaCatalogAPI.shared.search(keyword,kind:.series)
                if let values=try? await movies,!Task.isCancelled{remoteMovies=values}
                if let values=try? await shows,!Task.isCancelled{remoteShows=values}
            }
        }
    }
}

struct XSPremiumWatchlist: View {
    @EnvironmentObject private var library:XSCinemaNativeStore
    private var items:[XSCinemaMedia] {
        (library.movies+library.series+library.freeMovies).filter { library.favorites.contains($0.id) }
    }
    var body:some View {
        ZStack {
            XSPremiumCinemaBackdrop()
            ScrollView {
                LazyVStack(alignment:.leading,spacing:19) {
                    XSPremiumSectionTitle(eyebrow:"YOUR COLLECTION",title:"قائمتي",count:items.count)
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:130),spacing:14)]) {
                        ForEach(items) { item in
                            NavigationLink {
                                XSPremiumCinemaDetail(media:item)
                            } label: { XSPremiumPoster(movie:item,width:144) }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal,17)
                    if items.isEmpty {
                        Text("احفظ أفلامك ومسلسلاتك من صفحة التفاصيل، وبتظهر لك هنا.")
                            .font(.subheadline)
                            .foregroundStyle(XSPalette.second)
                            .padding(25)
                    }
                }
                .padding(.top,25)
            }
        }
        .navigationTitle("Watchlist")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct XSPremiumCinemaDetail:View {
    let media:XSCinemaMedia
    @EnvironmentObject private var library:XSCinemaNativeStore
    @State private var detailed:XSCinemaMedia?
    @State private var showSite=false
    @State private var siteEpisode:XSCinemaEpisode?
    @State private var direct:XSVODPlaybackSelection?
    @State private var season=1
    private var item:XSCinemaMedia { detailed ?? media }
    private var seasons:[Int] { Array(Set(item.episodes.map(\.season))).sorted() }
    private var siteLink:URL? {
        guard let raw=item.sourceURL,let url=URL(string:raw),
              ["etwatch.net","www.etwatch.net"].contains(url.host ?? "") else { return nil }
        return url
    }

    var body:some View {
        ZStack {
            XSPremiumCinemaBackdrop()
            ScrollView {
                VStack(alignment:.leading,spacing:0) {
                    ZStack(alignment:.bottomLeading) {
                        XSPremiumImage(url:item.backdropURL,symbol:"film.stack")
                            .frame(height:400)
                        LinearGradient(colors:[.clear,XSPalette.canvas.opacity(0.45),XSPalette.canvas],
                                       startPoint:.top,endPoint:.bottom)
                        VStack(alignment:.leading,spacing:11) {
                            Text(item.kind == .movie ? "FEATURE FILM" : "ORIGINAL SERIES")
                                .font(.system(size:10,weight:.black))
                                .tracking(2.6)
                                .foregroundStyle(XSPalette.gold)
                            Text(item.title)
                                .font(.system(size:34,weight:.black,design:.rounded))
                                .lineLimit(3)
                            HStack(spacing:10) {
                                if !item.year.isEmpty { Text(item.year.prefix(4)) }
                                Text(item.kind == .movie ? "MOVIE" : "SERIES")
                                if item.rating > 0 {
                                    Image(systemName:"star.fill").foregroundStyle(XSPalette.gold)
                                    Text(String(format:"%.1f",item.rating))
                                }
                            }
                            .font(.caption.bold())
                            .foregroundStyle(XSPalette.second)
                        }
                        .padding(19)
                    }
                    .frame(height:400)

                    VStack(alignment:.leading,spacing:22) {
                        HStack(spacing:12) {
                            if item.isPlayable,let url=item.streamURL {
                                Button {
                                    direct=XSVODPlaybackSelection(url:url,title:item.title,fallbackURL:nil)
                                } label: { primaryButton("تشغيل الفيلم") }
                            } else if siteLink != nil {
                                Button {
                                    siteEpisode=nil
                                    showSite=true
                                } label: { primaryButton("فتح المشغل") }
                            }
                            Button { library.toggle(item) } label: {
                                Image(systemName:library.favorite(item) ? "checkmark" : "plus")
                                    .font(.title3.bold())
                                    .frame(width:54,height:51)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            .background(XSPalette.card,in:RoundedRectangle(cornerRadius:14))
                        }
                        .buttonStyle(.plain)

                        if !item.summary.isEmpty {
                            VStack(alignment:.leading,spacing:9) {
                                sectionTitle("القصة")
                                Text(item.summary)
                                    .font(.system(size:14))
                                    .lineSpacing(5)
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }
                        if item.kind == .series {
                            seriesContents
                        }
                        HStack(alignment:.top,spacing:10) {
                            Image(systemName:"info.circle")
                                .foregroundStyle(XSPalette.gold)
                            Text(item.isPlayable
                                  ? "هذا الفيلم له رابط مباشر من مصدر مفتوح الترخيص. الترجمة تعتمد على ملفات الفيديو المتاحة."
                                  : "تشغيل ETWatch يعتمد على المشغل وسيرفرات الموقع، وقد يتعذر تشغيل بعض الأعمال أو ترجماتها داخل التطبيق.")
                                .font(.caption)
                                .foregroundStyle(XSPalette.second)
                                .fixedSize(horizontal:false,vertical:true)
                        }
                        .padding(14)
                        .background(XSPalette.card,in:RoundedRectangle(cornerRadius:14))
                        if let url=siteLink {
                            Link("عرض صفحة المصدر الأصلية",destination:url)
                                .font(.caption)
                                .foregroundStyle(XSPalette.second)
                        }
                    }
                    .padding(.horizontal,19)
                    .padding(.bottom,60)
                }
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges:.top)
        }
        .toolbar(.hidden,for:.tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .task(id:media.id) {
            if media.kind == .series {
                detailed=await XSCinemaCatalogAPI.shared.detail(media)
                season=seasons.first ?? 1
            }
        }
        .fullScreenCover(isPresented:$showSite) {
            if let url=siteLink {
                XSETWatchNativeDetailPlayer(
                    url:url,title:siteEpisode.map{"\(item.title) · S\($0.season) E\($0.number)"} ?? item.title,
                    season:siteEpisode?.season,episode:siteEpisode?.number)
            }
        }
        .fullScreenCover(item:$direct) { media in
            XSVODVLCPlayerView(source:media)
        }
    }

    private func primaryButton(_ name:String)->some View {
        Label(name,systemImage:"play.fill")
            .font(.system(size:15,weight:.bold))
            .foregroundStyle(.black)
            .frame(maxWidth:.infinity,minHeight:51)
            .background(.white,in:RoundedRectangle(cornerRadius:14))
    }

    private func sectionTitle(_ name:String)->some View {
        Text(name)
            .font(.system(size:23,weight:.bold,design:.rounded))
            .foregroundStyle(.white)
    }

    private var seriesContents:some View {
        VStack(alignment:.leading,spacing:15) {
            sectionTitle("المواسم والحلقات")
            if seasons.isEmpty {
                Text("لم تتوفر بيانات الحلقات من الفهرس.")
                    .foregroundStyle(XSPalette.second)
            } else {
                Picker("الموسم",selection:$season) {
                    ForEach(seasons,id:\.self){ n in
                        Text("الموسم \(n)").tag(n)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)

                ForEach(item.episodes.filter{$0.season==season}) { ep in
                    Button {
                        siteEpisode=ep
                        showSite=true
                    } label: {
                        HStack(spacing:13) {
                            Image(systemName:"play.rectangle.fill")
                                .font(.system(size:25))
                                .foregroundStyle(XSPalette.accent)
                                .frame(width:57,height:54)
                                .background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:10))
                            VStack(alignment:.leading,spacing:5) {
                                Text(ep.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(2)
                                Text("S\(ep.season) · E\(ep.number)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(XSPalette.second)
                            }
                            Spacer()
                            Image(systemName:"play.fill")
                                .foregroundStyle(XSPalette.second)
                        }
                        .foregroundStyle(.white)
                        .padding(10)
                        .modifier(XSPremiumGlass())
                    }
                    .disabled(siteLink==nil)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
