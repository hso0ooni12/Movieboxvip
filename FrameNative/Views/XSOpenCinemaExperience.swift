import SwiftUI

private enum XSOpenCinemaStyle {
    static let base = Color(red: 0.035, green: 0.041, blue: 0.065)
    static let surface = Color(red: 0.09, green: 0.11, blue: 0.15)
    static let pink = Color(red: 1, green: 0.29, blue: 0.39)
}

struct XSOpenCinemaHomeView: View {
    @EnvironmentObject private var source: XSOpenCinemaStore

    var body: some View {
        ZStack {
            XSOpenCinemaStyle.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 11) {
                        XSWordmark()
                        Text("FREE & OPEN CINEMA")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(2.5)
                            .foregroundStyle(XSOpenCinemaStyle.pink)
                        Text("شاهد أعمالاً مرخّصة للمشاركة مجاناً")
                            .font(.system(size: 23, weight: .bold))
                        Text("بعيداً عن اشتراك IPTV ومواقع البث غير الموثوقة.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.60))
                    }
                    .frame(maxWidth: .infinity, minHeight: 230, alignment: .bottomLeading)
                    .padding(20)

                    HStack(spacing: 12) {
                        NavigationLink { XSOpenCinemaBrowseView(shelf: .movies) } label: {
                            quickButton("الأفلام", icon: "film.stack.fill", count: source.movies.count)
                        }
                        NavigationLink { XSOpenCinemaBrowseView(shelf: .series) } label: {
                            quickButton("المسلسلات", icon: "play.tv.fill", count: source.series.count)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)

                    rail("الأفلام المجانية", list: source.movies)
                    rail("الأعمال المتسلسلة", list: source.series)
                    let favoriteItems = (source.movies + source.series).filter {
                        source.favorites.contains($0.id)
                    }
                    if !favoriteItems.isEmpty { rail("قائمتي", list: favoriteItems) }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("حول المكتبة").font(.headline)
                        Text("الأعمال مأخوذة من Internet Archive مع فلترة تراخيص المشاع الإبداعي التي تسمح بإعادة الاستخدام. إنها ليست مكتبة أحدث أفلام هوليوود، والترجمة العربية ليست متوفرة بكل فيلم.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.67))
                        if source.loading.contains(.movies) || source.loading.contains(.series) {
                            ProgressView().tint(XSOpenCinemaStyle.pink)
                        }
                    }
                    .padding(17)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(XSOpenCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 15))
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                async let a: Void = source.refresh(.movies)
                async let b: Void = source.refresh(.series)
                _ = await (a, b)
            }
        }
        .overlay(alignment: .topTrailing) {
            NavigationLink {
                XSOpenCinemaSearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(16)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await source.start() }
    }

    private func quickButton(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(XSOpenCinemaStyle.pink)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text("\(count) عمل").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(15)
        .background(XSOpenCinemaStyle.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func rail(_ title: String, list: [XSOpenTitle]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.title2.bold()).padding(.horizontal, 18)
            if list.isEmpty {
                HStack(spacing: 9) {
                    ProgressView().tint(XSOpenCinemaStyle.pink)
                    Text("بانتظار محتوى المصدر…")
                        .foregroundStyle(.secondary).font(.caption)
                }
                .padding(.horizontal, 18)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 13) {
                        ForEach(list.prefix(22)) { item in
                            NavigationLink {
                                XSOpenCinemaDetailView(item: item)
                            } label: {
                                XSOpenCinemaPoster(item: item, width: 150)
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

struct XSOpenCinemaBrowseView: View {
    let shelf: XSOpenShelf
    @EnvironmentObject private var source: XSOpenCinemaStore
    @State private var query = ""

    private var titles: [XSOpenTitle] {
        let raw = source.items(shelf)
        guard !query.isEmpty else { return raw }
        return raw.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        ZStack {
            XSOpenCinemaStyle.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shelf.title).font(.system(size: 29, weight: .bold))
                            Text("\(titles.count) عنوان من أعمال مفتوحة الترخيص")
                                .font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Button {
                            Task { await source.refresh(shelf) }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding(.top, 12)
                    if source.loading.contains(shelf) {
                        ProgressView("جارٍ البحث عن أعمال قابلة للتشغيل…")
                            .font(.caption)
                            .tint(XSOpenCinemaStyle.pink)
                    }
                    if let message = source.messages[shelf] {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                    if titles.isEmpty && !source.loading.contains(shelf) {
                        Text("ما فيه أعمال قابلة للتشغيل بهذا القسم حالياً.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)],
                              spacing: 19) {
                        ForEach(titles) { item in
                            NavigationLink {
                                XSOpenCinemaDetailView(item: item)
                            } label: {
                                XSOpenCinemaPoster(item: item, width: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .refreshable { await source.refresh(shelf) }
        }
        .searchable(text: $query, prompt: "اسم الفيلم")
        .navigationTitle(shelf.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await source.start() }
    }
}

struct XSOpenCinemaSearchView: View {
    @EnvironmentObject private var source: XSOpenCinemaStore
    @State private var query = ""
    var body: some View {
        ZStack {
            XSOpenCinemaStyle.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(source.search(query)) { item in
                        NavigationLink {
                            XSOpenCinemaDetailView(item: item)
                        } label: {
                            HStack {
                                XSOpenCinemaArtwork(item: item)
                                    .frame(width: 73, height: 78)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.white)
                                    Text(item.shelf.title).font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.forward")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(15)
            }
        }
        .searchable(text: $query, prompt: "البحث في الأفلام المرخّصة")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct XSOpenCinemaDetailView: View {
    let item: XSOpenTitle
    @EnvironmentObject private var source: XSOpenCinemaStore
    @State private var selectedPlayback: XSVODPlaybackSelection?
    var body: some View {
        ZStack {
            XSOpenCinemaStyle.base.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    XSOpenCinemaArtwork(item: item)
                        .frame(height: 290)
                        .clipShape(RoundedRectangle(cornerRadius: 17))
                    Text(item.name)
                        .font(.system(size: 25, weight: .bold))
                    HStack(spacing: 10) {
                        Button {
                            guard let url = item.playableURL else { return }
                            selectedPlayback = XSVODPlaybackSelection(
                                url: url, title: item.name, fallbackURL: nil)
                        } label: {
                            Label("تشغيل الفيلم", systemImage: "play.fill")
                                .frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(XSOpenCinemaStyle.pink)
                        Button {
                            source.toggle(item)
                        } label: {
                            Image(systemName: source.isFavorite(item) ? "checkmark" : "plus")
                                .frame(width: 48, height: 46)
                        }
                        .buttonStyle(.bordered)
                    }
                    if !item.details.isEmpty {
                        Text(item.details).font(.subheadline)
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    if item.hasArabicSubtitleFile {
                        Label("يوجد ملف ترجمة عربية في المصدر؛ قد يلزم توافقه مع نسخة الفيديو.",
                              systemImage: "captions.bubble")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Label("لم يُتحقق من وجود ترجمة عربية لهذه النسخة.",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("رخصة الاستخدام")
                        .font(.subheadline.bold())
                    if let license = URL(string: item.licenseURL) {
                        Link(item.licenseURL, destination: license)
                            .font(.caption)
                            .lineLimit(2)
                    }
                    if let url = item.sourceURL {
                        Link("عرض صفحة المصدر وحقوقه في Internet Archive", destination: url)
                            .font(.caption)
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedPlayback) { selected in
            // V21 VLC UI deliberately preserves the original XS TV controls
            // (10-sec skip, scrub bar, Arabic track, audio and speed panels).
            XSVODVLCPlayerView(source: selected)
        }
    }
}

private struct XSOpenCinemaPoster: View {
    let item: XSOpenTitle
    let width: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            XSOpenCinemaArtwork(item: item)
                .aspectRatio(0.70, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 13))
            Text(item.name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text("Open License")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct XSOpenCinemaArtwork: View {
    let item: XSOpenTitle
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [XSOpenCinemaStyle.surface, .purple.opacity(0.18),
                                        XSOpenCinemaStyle.base],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let image = item.thumbnail {
                    AsyncImage(url: image) { result in
                        if case .success(let visual) = result {
                            visual.resizable().scaledToFill()
                        } else {
                            Image(systemName: "film.stack")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                } else {
                    Image(systemName: "film.stack")
                        .font(.system(size: 38))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}
