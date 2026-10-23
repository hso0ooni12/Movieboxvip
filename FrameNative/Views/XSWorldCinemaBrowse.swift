import SwiftUI
import AVKit

struct XSWorldBrowse: View {
    let kind: XSCinemaMediaKind
    @EnvironmentObject private var cinema: XSCinemaNativeStore
    @State private var query = ""
    @State private var remoteItems: [XSCinemaMedia] = []
    @State private var selectedFilter = 0
    @State private var orderByRating = false
    @State private var pendingSearch: Task<Void, Never>?

    private var items: [XSCinemaMedia] {
        let original = kind == .movie && selectedFilter == 1
            ? cinema.freeMovies : cinema.list(kind)
        guard query.count > 1 else {
            return orderByRating ? original.sorted { $0.rating > $1.rating } : original
        }
        var seen = Set<String>()
        return (original.filter { $0.title.localizedStandardContains(query) } + remoteItems)
            .filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        ZStack {
            XSWorldBackDrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 23) {
                    browseHeader
                    featuredBanner
                    filterBar
                    posterGrid
                    if items.isEmpty && !cinema.loading {
                        Text(cinema.error ?? "No titles found")
                            .font(.subheadline)
                            .foregroundStyle(XSCinemaStyle.secondary)
                            .frame(maxWidth: .infinity, minHeight: 170)
                    }
                    if query.isEmpty && selectedFilter == 0 && !items.isEmpty {
                        moreButton
                    }
                }
                .padding(.horizontal, 19)
                .padding(.bottom, 54)
            }
            .scrollIndicators(.hidden)
            .refreshable { await cinema.refresh() }
        }
        .navigationTitle(kind == .movie ? "Movies" : "Series")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search movies and series")
        .onChange(of: query) { next in
            pendingSearch?.cancel()
            remoteItems = []
            guard next.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else { return }
            pendingSearch = Task {
                try? await Task.sleep(nanoseconds: 320_000_000)
                guard !Task.isCancelled else { return }
                if let incoming = try? await XSCinemaCatalogAPI.shared.search(next, kind: kind),
                   !Task.isCancelled {
                    remoteItems = incoming
                }
            }
        }
        .task { await cinema.boot() }
    }

    private var browseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind == .movie ? "THE MOVIE LIBRARY" : "DISCOVER SERIES")
                .font(.system(size: 10, weight: .black))
                .tracking(2.5)
                .foregroundStyle(XSCinemaStyle.accent)
            Text(kind == .movie ? "Movies" : "Series")
                .font(.system(size: 37, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Discover stories worth watching")
                .font(.subheadline)
                .foregroundStyle(XSCinemaStyle.secondary)
        }
        .padding(.top, 14)
    }

    @ViewBuilder
    private var featuredBanner: some View {
        if let cover = items.first {
            NavigationLink {
                XSWorldDetail(item: cover)
            } label: {
                ZStack(alignment: .bottomLeading) {
                    XSWorldPhoto(item: cover, backdrop: true)
                        .frame(height: 210)
                    LinearGradient(colors: [.clear, .black.opacity(0.88)],
                                   startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FEATURED COLLECTION")
                            .font(.system(size: 10, weight: .black))
                            .tracking(2.0)
                            .foregroundStyle(XSCinemaStyle.gold)
                        Text(cover.title)
                            .font(.title2.bold())
                            .lineLimit(2)
                        Label("View details", systemImage: "arrow.up.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.10)))
            }
            .buttonStyle(XSWorldTapStyle())
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            if kind == .movie {
                filterChip("All", selection: 0)
                filterChip("Free to watch", selection: 1)
            } else {
                Text("\(items.count) titles")
                    .font(.subheadline.bold())
                    .foregroundStyle(XSCinemaStyle.secondary)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { orderByRating.toggle() }
            } label: {
                Label(orderByRating ? "Top rated" : "Popular",
                      systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(.white.opacity(0.095), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var posterGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 13),
            GridItem(.flexible(), spacing: 13)
        ], spacing: 22) {
            ForEach(items) { item in
                NavigationLink {
                    XSWorldDetail(item: item)
                } label: {
                    XSWorldBrowseCard(item: item)
                }
                .buttonStyle(XSWorldTapStyle())
            }
        }
    }

    private var moreButton: some View {
        Button {
            Task { await cinema.more(kind) }
        } label: {
            HStack(spacing: 10) {
                if cinema.loadingMore.contains(kind) {
                    ProgressView().tint(.white)
                }
                Text("Load more")
            }
            .font(.subheadline.bold())
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(.white)
            .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(XSWorldTapStyle())
    }

    private func filterChip(_ title: String, selection: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.22)) { selectedFilter = selection }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 15)
                .frame(height: 36)
                .background(selectedFilter == selection
                            ? XSCinemaStyle.accent.opacity(0.91)
                            : .white.opacity(0.11), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct XSWorldBrowseCard: View {
    let item: XSCinemaMedia
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    XSWorldPhoto(item: item)
                    LinearGradient(colors: [.clear, .black.opacity(0.78)],
                                   startPoint: .center, endPoint: .bottom)
                    HStack(spacing: 6) {
                        if item.rating > 0 {
                            Image(systemName: "star.fill")
                                .foregroundStyle(XSCinemaStyle.gold)
                            Text(String(format: "%.1f", item.rating))
                        }
                        Spacer()
                        if item.isPlayable {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.white)
                        }
                    }
                    .font(.system(size: 11, weight: .bold))
                    .padding(11)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 17))
            }
            .aspectRatio(0.70, contentMode: .fit)
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(item.year.isEmpty ? item.kind.label : item.year)
                .font(.caption2)
                .foregroundStyle(XSCinemaStyle.secondary)
                .lineLimit(1)
        }
    }
}

struct XSWorldSearch: View {
    @EnvironmentObject private var cinema: XSCinemaNativeStore
    @State private var query = ""
    @State private var remoteMovies: [XSCinemaMedia] = []
    @State private var remoteSeries: [XSCinemaMedia] = []
    @State private var lookupTask: Task<Void, Never>?

    private var results: [XSCinemaMedia] {
        guard !query.isEmpty else { return [] }
        let cached = cinema.movies + cinema.series + cinema.freeMovies
        var seen = Set<String>()
        return Array((cached.filter { $0.title.localizedStandardContains(query) }
                      + remoteMovies + remoteSeries)
            .filter { seen.insert($0.id).inserted }
            .prefix(120))
    }

    var body: some View {
        ZStack {
            XSWorldBackDrop()
            ScrollView {
                LazyVStack(spacing: 11) {
                    if query.count < 2 {
                        VStack(spacing: 13) {
                            Image(systemName: "sparkle.magnifyingglass")
                                .font(.system(size: 39))
                                .foregroundStyle(XSCinemaStyle.lavender)
                            Text("Every story starts somewhere")
                                .font(.title3.bold())
                            Text("اكتب اسم الفيلم أو المسلسل للبحث")
                                .font(.caption)
                                .foregroundStyle(XSCinemaStyle.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 270)
                    }
                    ForEach(results) { item in
                        NavigationLink {
                            XSWorldDetail(item: item)
                        } label: {
                            HStack(spacing: 14) {
                                XSWorldPhoto(item: item)
                                    .frame(width: 72, height: 102)
                                    .clipShape(RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.title)
                                        .font(.subheadline.bold())
                                        .lineLimit(2)
                                    Text(item.kind.label + "  ·  " + item.year)
                                        .font(.caption)
                                        .foregroundStyle(XSCinemaStyle.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(XSCinemaStyle.accent)
                            }
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(XSCinemaStyle.surface.opacity(0.70),
                                        in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(XSWorldTapStyle())
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Movie or series")
        .onChange(of: query) { next in
            lookupTask?.cancel()
            remoteMovies = []
            remoteSeries = []
            guard next.count >= 2 else { return }
            lookupTask = Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                async let movieTask = XSCinemaCatalogAPI.shared.search(next, kind: .movie)
                async let seriesTask = XSCinemaCatalogAPI.shared.search(next, kind: .series)
                if let m = try? await movieTask, !Task.isCancelled { remoteMovies = m }
                if let s = try? await seriesTask, !Task.isCancelled { remoteSeries = s }
            }
        }
    }
}

struct XSWorldWatchlist: View {
    @EnvironmentObject private var cinema: XSCinemaNativeStore
    private var favorites: [XSCinemaMedia] {
        (cinema.movies + cinema.series + cinema.freeMovies)
            .filter { cinema.favorites.contains($0.id) }
    }

    var body: some View {
        ZStack {
            XSWorldBackDrop()
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 13),
                                    GridItem(.flexible(), spacing: 13)], spacing: 23) {
                    ForEach(favorites) { item in
                        NavigationLink { XSWorldDetail(item: item) } label: {
                            XSWorldBrowseCard(item: item)
                        }
                        .buttonStyle(XSWorldTapStyle())
                    }
                }
                .padding(18)
            }
            if favorites.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 45, weight: .ultraLight))
                        .foregroundStyle(XSCinemaStyle.accent)
                    Text("Your watchlist is empty").font(.title3.bold())
                    Text("اضغط إضافة لقائمتي داخل تفاصيل العمل")
                        .font(.caption)
                        .foregroundStyle(XSCinemaStyle.secondary)
                }
            }
        }
        .navigationTitle("My List")
    }
}

struct XSWorldDetail: View {
    let item: XSCinemaMedia
    @EnvironmentObject private var cinema: XSCinemaNativeStore
    @State private var detail: XSCinemaMedia?
    @State private var season = 1
    @State private var selectedEpisode: XSCinemaEpisode?
    @State private var showSite = false
    @State private var showOpen = false

    private var media: XSCinemaMedia { detail ?? item }
    private var seasons: [Int] { Array(Set(media.episodes.map(\.season))).sorted() }
    private var siteURL: URL? {
        guard let link = media.sourceURL, let url = URL(string: link),
              url.scheme == "https",
              url.host == "etwatch.net" || url.host == "www.etwatch.net" else { return nil }
        return url
    }

    var body: some View {
        ZStack {
            XSWorldBackDrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(alignment: .leading, spacing: 17) {
                        Text(media.title)
                            .font(.system(size: 29, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        HStack(spacing: 12) {
                            Text(media.kind == .movie ? "MOVIE" : "SERIES")
                            Text(media.year)
                            if media.rating > 0 {
                                Label(String(format: "%.1f", media.rating),
                                      systemImage: "star.fill")
                                    .foregroundStyle(XSCinemaStyle.gold)
                            }
                        }
                        .font(.caption.bold())
                        .foregroundStyle(XSCinemaStyle.secondary)
                        actionBar
                        if !media.summary.isEmpty {
                            Text(media.summary)
                                .font(.subheadline)
                                .lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        if media.kind == .series { episodes }
                        sourceNotice
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 50)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(media.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            if item.kind == .series {
                detail = await XSCinemaCatalogAPI.shared.detail(item)
                season = seasons.first ?? 1
            }
        }
        .fullScreenCover(isPresented: $showSite) {
            if let siteURL {
                XSWorldSitePlayer(url: siteURL,
                                  title: selectedEpisode.map {
                                    "\(media.title) • S\($0.season) E\($0.number)"
                                  } ?? media.title,
                                  episode: selectedEpisode?.number,
                                  season: selectedEpisode?.season)
            }
        }
        .fullScreenCover(isPresented: $showOpen) {
            if let stream = media.streamURL {
                XSWorldOpenVideo(url: stream, title: media.title)
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottom) {
            XSWorldPhoto(item: media, backdrop: true)
                .frame(height: 345)
            LinearGradient(colors: [.clear,
                                    XSCinemaStyle.background.opacity(0.60),
                                    XSCinemaStyle.background],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(height: 345)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if media.isPlayable {
                Button {
                    showOpen = true
                } label: {
                    Label("Watch now", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(XSCinemaStyle.accent,
                                    in: RoundedRectangle(cornerRadius: 14))
                }
            } else if siteURL != nil {
                Button {
                    selectedEpisode = nil
                    showSite = true
                } label: {
                    Label(media.kind == .series ? "Open series player" : "Watch on ETWatch",
                          systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(.white)
                        .background(XSCinemaStyle.accent,
                                    in: RoundedRectangle(cornerRadius: 14))
                }
            }
            Button {
                cinema.toggle(media)
            } label: {
                Image(systemName: cinema.favorite(media) ? "checkmark" : "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 51, height: 50)
                    .background(.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("إضافة لقائمتي")
        }
        .buttonStyle(XSWorldTapStyle())
    }

    @ViewBuilder
    private var episodes: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Episodes")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                if !seasons.isEmpty {
                    Picker("Season", selection: $season) {
                        ForEach(seasons, id: \.self) { number in
                            Text("Season \(number)").tag(number)
                        }
                    }
                    .tint(.white)
                }
            }
            .foregroundStyle(.white)
            if seasons.isEmpty {
                Text("Season and episode metadata is unavailable.")
                    .foregroundStyle(XSCinemaStyle.secondary)
            } else {
                ForEach(media.episodes.filter { $0.season == season }) { ep in
                    Button {
                        selectedEpisode = ep
                        if siteURL != nil { showSite = true }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(XSCinemaStyle.surface)
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 29))
                                    .foregroundStyle(XSCinemaStyle.accent)
                            }
                            .frame(width: 85, height: 67)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(ep.title)
                                    .font(.subheadline.bold())
                                    .lineLimit(2)
                                Text("S\(ep.season) E\(ep.number)")
                                    .font(.caption)
                                    .foregroundStyle(XSCinemaStyle.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(XSCinemaStyle.secondary)
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                    }
                    .disabled(siteURL == nil)
                    .buttonStyle(XSWorldTapStyle())
                }
            }
        }
        .padding(.top, 13)
    }

    private var sourceNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Playback information", systemImage: "info.circle")
                .font(.caption.bold())
                .foregroundStyle(XSCinemaStyle.gold)
            Text(media.isPlayable
                 ? "هذا فيديو من مصدر مفتوح الترخيص، وقد تختلف خيارات الصوت والترجمة."
                 : siteURL != nil
                   ? "مشغل ETWatch خارجي. قد يتطلب اختيار الجودة أو الترجمة من الموقع، وتوفر التشغيل غير مضمون."
                   : "هذا العمل متوفر في الفهرس فقط، ولم يتم العثور على مصدر مشاهدة.")
                .font(.caption)
                .lineSpacing(4)
                .foregroundStyle(XSCinemaStyle.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(XSCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct XSWorldOpenVideo: View {
    let url: URL
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let player {
                XSWorldAVController(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .foregroundStyle(.white)
                    .background(.black.opacity(0.66), in: Circle())
            }
            .padding(18)
        }
        .onAppear {
            let p = AVPlayer(url: url)
            player = p
            p.play()
        }
        .onDisappear { player?.pause(); player = nil }
    }
}

private struct XSWorldAVController: UIViewControllerRepresentable {
    let player: AVPlayer
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.showsPlaybackControls = true
        return controller
    }
    func updateUIViewController(_ viewController: AVPlayerViewController, context: Context) {
        viewController.player = player
    }
}
