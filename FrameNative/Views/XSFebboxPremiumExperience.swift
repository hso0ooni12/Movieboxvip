import SwiftUI

// Primary Febbox user experience. Home, Movies, Series and Search consume the
// same indexed Febbox shares. No TMDB catalog, old website or legacy player is
// consulted by these screens.
private enum XSFebboxTheme {
    static let base = Color(red: 0.035, green: 0.041, blue: 0.065)
    static let surface = Color(red: 0.095, green: 0.105, blue: 0.145)
    static let accent = Color(red: 1.0, green: 0.29, blue: 0.39)
    static let secondary = Color.white.opacity(0.65)
}

struct XSFebboxPremiumHomeView: View {
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    @State private var showAccount = false

    private var moviePicks: [XSFebboxIndexedItem] { catalog.root(shelf: .movies) }
    private var seriesPicks: [XSFebboxIndexedItem] { catalog.root(shelf: .series) }
    private var featured: XSFebboxIndexedItem? {
        moviePicks.first(where: { catalog.artwork(for: $0) != nil })
            ?? seriesPicks.first(where: { catalog.artwork(for: $0) != nil })
            ?? moviePicks.first ?? seriesPicks.first
    }

    var body: some View {
        ZStack {
            XSFebboxTheme.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 26) {
                    if let featured {
                        hero(featured)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            XSBrandMark(size: 100)
                            Text("سينما XS TV")
                                .font(.system(size: 33, weight: .black))
                            Text(catalog.scanning.isEmpty
                                 ? "لا يوجد محتوى ظاهر في مشاركات Febbox حالياً."
                                 : "نجهز لك مكتبة Febbox…")
                                .foregroundStyle(XSFebboxTheme.secondary)
                            if !catalog.scanning.isEmpty { ProgressView().tint(XSFebboxTheme.accent) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
                        .padding(24)
                    }
                    quickDestinations
                    if !catalog.recent.isEmpty {
                        rail("شوهد مؤخراً", eyebrow: "CONTINUE EXPLORING", items: catalog.recent)
                    }
                    rail("أفلام المكتبة", eyebrow: "FEBBOX MOVIES", items: Array(moviePicks.prefix(22)))
                    rail("مسلسلات المكتبة", eyebrow: "FEBBOX SERIES", items: Array(seriesPicks.prefix(22)))
                    let favoriteItems = (catalog.movies + catalog.series)
                        .filter { catalog.favoriteIDs.contains($0.id) }
                    if !favoriteItems.isEmpty {
                        rail("قائمتي", eyebrow: "YOUR FAVORITES", items: Array(favoriteItems.prefix(22)))
                    }
                    libraryStatus
                }
                .padding(.bottom, 50)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .refreshable {
                catalog.refresh(.movies)
                catalog.refresh(.series)
            }
        }
        .overlay(alignment: .top) { topBar }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAccount) { XSFebboxAccountView() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            XSWordmark(compact: true)
            Spacer()
            NavigationLink {
                XSFebboxPremiumSearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("بحث في مكتبة Febbox")
            Button { showAccount = true } label: {
                Image(systemName: "person.crop.circle")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("حساب Febbox")
        }
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .background(
            LinearGradient(colors: [.black.opacity(0.92), .black.opacity(0.35), .clear],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .top)
        )
    }

    private func hero(_ item: XSFebboxIndexedItem) -> some View {
        NavigationLink {
            XSFebboxPremiumEntryView(item: item)
        } label: {
            ZStack(alignment: .bottomLeading) {
                XSFebboxArtworkView(item: item, backdrop: true)
                    .frame(height: 490)
                LinearGradient(colors: [.clear, .black.opacity(0.22), XSFebboxTheme.base],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 11) {
                    Text("FEATURED FROM FEBBOX")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2.5)
                        .foregroundStyle(XSFebboxTheme.accent)
                    Text(item.displayTitle)
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    HStack {
                        Image(systemName: item.isDirectory ? "folder.fill" : "play.fill")
                        Text(item.isDirectory ? "استكشف المحتوى" : "عرض الفيديو")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 18)
                    .frame(height: 42)
                    .foregroundStyle(.black)
                    .background(.white, in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .frame(height: 490)
        }
        .buttonStyle(.plain)
    }

    private var quickDestinations: some View {
        HStack(spacing: 12) {
            NavigationLink { XSFebboxPremiumBrowseView(shelf: .movies) } label: {
                destinationLabel("الأفلام", "film.stack.fill", count: catalog.movies.count)
            }
            NavigationLink { XSFebboxPremiumBrowseView(shelf: .series) } label: {
                destinationLabel("المسلسلات", "play.tv.fill", count: catalog.series.count)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 17)
    }

    private func destinationLabel(_ label: String, _ symbol: String, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(XSFebboxTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.system(size: 16, weight: .bold))
                Text("\(count) عنصر مكتشف")
                    .font(.system(size: 10))
                    .foregroundStyle(XSFebboxTheme.secondary)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(XSFebboxTheme.surface, in: RoundedRectangle(cornerRadius: 17))
    }

    private func rail(_ title: String, eyebrow: String, items: [XSFebboxIndexedItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow).font(.system(size: 10, weight: .heavy))
                    .tracking(2).foregroundStyle(XSFebboxTheme.accent)
                Text(title).font(.system(size: 24, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 19)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink {
                            XSFebboxPremiumEntryView(item: item)
                        } label: {
                            XSFebboxPosterTile(item: item, width: 146)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 19)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var libraryStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("مكتبتك من Febbox")
                .font(.subheadline.bold())
            Text(catalog.scanning.isEmpty
                 ? "القوائم معروضة مباشرة من مجلدات المصدر، بدون الاعتماد على موقع الأفلام السابق."
                 : "جارٍ فهرسة جميع المجلدات والمواسم تدريجياً. تقدر تتصفح المكتبة أثناء الفهرسة.")
                .font(.caption)
                .foregroundStyle(XSFebboxTheme.secondary)
            if catalog.scanning.contains(.movies) || catalog.scanning.contains(.series) {
                ProgressView().tint(XSFebboxTheme.accent).padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
        .background(XSFebboxTheme.surface, in: RoundedRectangle(cornerRadius: 15))
        .padding(.horizontal, 19)
    }
}

struct XSFebboxPremiumBrowseView: View {
    let shelf: XSFebboxShelf
    var parentID: String = "0"
    var title: String? = nil
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    @State private var search = ""
    @State private var alphabetical = false

    private var visible: [XSFebboxIndexedItem] {
        let basic = search.isEmpty
            ? catalog.children(shelf: shelf, parentID: parentID)
            : catalog.search(search, shelf: shelf)
        let items = basic.filter { $0.isDirectory || $0.isPlayable || $0.isSubtitle }
        return alphabetical
            ? items.sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
            : items
    }

    var body: some View {
        ZStack {
            XSFebboxTheme.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 17) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title ?? shelf.title)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                            Text(parentID == "0" ? "كل ما توفر من Febbox" : "المواسم والملفات من المصدر")
                                .font(.caption).foregroundStyle(XSFebboxTheme.secondary)
                        }
                        Spacer()
                        Button {
                            alphabetical.toggle()
                        } label: {
                            Label(alphabetical ? "A–Z" : "ترتيب المصدر",
                                  systemImage: "arrow.up.arrow.down")
                                .font(.caption.bold())
                        }
                        .tint(.white)
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 22)
                    if parentID == "0" && catalog.scanning.contains(shelf) {
                        HStack(spacing: 9) {
                            ProgressView().tint(XSFebboxTheme.accent)
                            Text("تتم فهرسة بقية محتوى Febbox في الخلفية…")
                                .font(.caption)
                                .foregroundStyle(XSFebboxTheme.secondary)
                        }
                    }
                    if let error = catalog.failed[shelf] {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("تعذر تحميل بعض عناصر المكتبة", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text(error).font(.caption)
                            Button("إعادة المحاولة") { catalog.refresh(shelf) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    if visible.isEmpty && !catalog.scanning.contains(shelf) {
                        Text("ما فيه عناصر بهذا المجلد، أو ما ظهرت من مشاركة Febbox.")
                            .font(.subheadline).foregroundStyle(XSFebboxTheme.secondary)
                            .frame(maxWidth: .infinity, minHeight: 180)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 21) {
                        ForEach(visible) { item in
                            NavigationLink {
                                XSFebboxPremiumEntryView(item: item)
                            } label: {
                                XSFebboxPosterTile(item: item, width: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 35)
            }
            .scrollIndicators(.hidden)
            .searchable(text: $search, prompt: "بحث في \(shelf.title)")
            .refreshable { catalog.refresh(shelf) }
        }
        .navigationTitle(parentID == "0" ? shelf.title : (title ?? shelf.title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct XSFebboxPremiumSearchView: View {
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    @State private var text = ""
    @State private var selected = 0

    private var results: [XSFebboxIndexedItem] {
        catalog.search(text, shelf: selected == 1 ? .movies :
                                      (selected == 2 ? .series : nil))
    }

    var body: some View {
        ZStack {
            XSFebboxTheme.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("البحث في Febbox")
                        .font(.system(size: 29, weight: .bold))
                    Picker("القسم", selection: $selected) {
                        Text("الكل").tag(0)
                        Text("الأفلام").tag(1)
                        Text("المسلسلات").tag(2)
                    }
                    .pickerStyle(.segmented)
                    if text.isEmpty {
                        Text("اكتب اسم الفيلم أو المسلسل أو الحلقة. النتائج مأخوذة فقط من الملفات والمجلدات التي فُهرست من Febbox.")
                            .font(.subheadline)
                            .foregroundStyle(XSFebboxTheme.secondary)
                    } else {
                        Text("\(results.count) نتيجة")
                            .font(.caption).foregroundStyle(XSFebboxTheme.secondary)
                    }
                    ForEach(results) { item in
                        NavigationLink {
                            XSFebboxPremiumEntryView(item: item)
                        } label: {
                            XSFebboxSearchRow(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(17)
            }
        }
        .searchable(text: $text, prompt: "اسم الفيلم أو المسلسل")
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct XSFebboxPremiumEntryView: View {
    let item: XSFebboxIndexedItem
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    @State private var variants: [XSFebboxQuality] = []
    @State private var selectedQuality: XSFebboxQuality?
    @State private var loading = false
    @State private var playbackError: String?
    @State private var loginRequired = false
    @State private var showAccount = false

    private var children: [XSFebboxIndexedItem] {
        catalog.children(shelf: item.shelf, parentID: item.fid)
    }

    var body: some View {
        ZStack {
            XSFebboxTheme.base.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ZStack(alignment: .bottomLeading) {
                        XSFebboxArtworkView(item: item, backdrop: true)
                            .frame(height: 275)
                        LinearGradient(colors: [.clear, XSFebboxTheme.base],
                                       startPoint: .top, endPoint: .bottom)
                    }
                    .frame(height: 275)
                    VStack(alignment: .leading, spacing: 15) {
                        Text(item.displayTitle)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        HStack {
                            Label(item.shelf == .movies ? "أفلام" : "مسلسلات",
                                  systemImage: item.shelf == .movies ? "film" : "play.tv")
                            if item.isDirectory {
                                Label("مجلد", systemImage: "folder")
                            } else {
                                Text(item.fileExtension.uppercased())
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(XSFebboxTheme.secondary)
                        HStack(spacing: 12) {
                            Button {
                                catalog.toggleFavorite(item)
                            } label: {
                                Label(catalog.isFavorite(item) ? "في قائمتي" : "أضف للقائمة",
                                      systemImage: catalog.isFavorite(item) ? "checkmark" : "plus")
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                            if !item.isDirectory {
                                Button {
                                    Task { await loadPlaybackLinks() }
                                } label: {
                                    Label("تحديث روابط التشغيل", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if item.isDirectory {
                            HStack {
                                Text("المواسم والحلقات والملفات")
                                    .font(.title3.bold())
                                Spacer()
                                Text("\(children.count) عنصر")
                                    .font(.caption).foregroundStyle(XSFebboxTheme.secondary)
                            }
                            ForEach(children) { child in
                                NavigationLink {
                                    XSFebboxPremiumEntryView(item: child)
                                } label: {
                                    XSFebboxSearchRow(item: child)
                                }
                                .buttonStyle(.plain)
                            }
                            if children.isEmpty {
                                Text(catalog.scanning.contains(item.shelf)
                                     ? "جارٍ الوصول إلى المجلدات التابعة…"
                                     : "لا توجد ملفات ظاهرة في هذا المجلد.")
                                    .font(.footnote)
                                    .foregroundStyle(XSFebboxTheme.secondary)
                            }
                        } else if item.isPlayable {
                            if loading {
                                HStack {
                                    ProgressView().tint(XSFebboxTheme.accent)
                                    Text("جارٍ التحقق من روابط التشغيل…")
                                }
                                .font(.caption)
                            }
                            ForEach(variants) { quality in
                                Button {
                                    catalog.opened(item)
                                    selectedQuality = quality
                                } label: {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("تشغيل · \(quality.name)")
                                        Spacer()
                                    }
                                    .font(.system(size: 15, weight: .bold))
                                    .padding(15)
                                    .foregroundStyle(.white)
                                    .background(XSFebboxTheme.accent, in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain)
                            }
                            if let playbackError {
                                Label(playbackError, systemImage: "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                                if loginRequired {
                                    Button {
                                        showAccount = true
                                    } label: {
                                        Label("تسجيل الدخول إلى Febbox", systemImage: "person.crop.circle")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(XSFebboxTheme.accent)
                                }
                            }
                        } else if item.isSubtitle {
                            Label("ملف ترجمة من Febbox", systemImage: "captions.bubble")
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: item.id) {
            if item.isPlayable { await loadPlaybackLinks() }
        }
        .sheet(isPresented: $showAccount, onDismiss: {
            Task { await loadPlaybackLinks() }
        }) {
            XSFebboxAccountView()
        }
        .fullScreenCover(item: $selectedQuality) { quality in
            XSFebboxVLCPlaybackView(quality: quality)
        }
    }

    private func loadPlaybackLinks() async {
        guard !loading, item.isPlayable else { return }
        loading = true
        playbackError = nil
        defer { loading = false }
        do {
            variants = try await XSFebboxLibraryService.shared.publicVideoQualities(for: item.entry)
            loginRequired = false
        } catch {
            variants = []
            loginRequired = (error as? XSFebboxError).map {
                if case .signInRequired = $0 { return true }
                return false
            } ?? false
            playbackError = error.localizedDescription
        }
    }
}

private struct XSFebboxArtworkView: View {
    let item: XSFebboxIndexedItem
    var backdrop = false
    @EnvironmentObject private var catalog: XSFebboxCatalogStore

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [XSFebboxTheme.surface,
                                        Color.purple.opacity(0.15),
                                        XSFebboxTheme.base],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let artwork = catalog.artwork(for: item) {
                    AsyncImage(url: artwork, transaction: Transaction(animation: nil)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 9) {
            Image(systemName: item.isDirectory ? "folder.fill" : "play.rectangle.fill")
                .font(.system(size: backdrop ? 56 : 38, weight: .thin))
            if backdrop {
                Text("XS TV").font(.system(size: 14, weight: .heavy)).tracking(2)
            }
        }
        .foregroundStyle(.white.opacity(0.37))
    }
}

private struct XSFebboxPosterTile: View {
    let item: XSFebboxIndexedItem
    let width: CGFloat?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            XSFebboxArtworkView(item: item)
                .aspectRatio(0.70, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .overlay(RoundedRectangle(cornerRadius: 15)
                    .stroke(.white.opacity(0.09), lineWidth: 1))
            Text(item.displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(.white)
            Text(item.isDirectory ? "مجلد · \(item.shelf.title)" :
                    item.fileExtension.uppercased())
                .font(.system(size: 10))
                .foregroundStyle(XSFebboxTheme.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
    }
}

private struct XSFebboxSearchRow: View {
    let item: XSFebboxIndexedItem
    var body: some View {
        HStack(spacing: 12) {
            XSFebboxArtworkView(item: item)
                .frame(width: 79, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle).font(.system(size: 14, weight: .semibold))
                    .lineLimit(2).foregroundStyle(.white)
                Text(item.folderTrail.joined(separator: " / "))
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(XSFebboxTheme.secondary)
                Text(item.isDirectory ? "مجلد" : item.fileExtension.uppercased())
                    .font(.caption2).foregroundStyle(XSFebboxTheme.accent)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(8)
        .background(XSFebboxTheme.surface.opacity(0.67),
                    in: RoundedRectangle(cornerRadius: 13))
    }
}
