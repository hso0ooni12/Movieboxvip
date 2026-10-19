import SwiftUI

// Febbox is the sole movies-and-series inventory. No TMDB discovery,
// FrameXTV source lookup or fabricated title rows are used by these views.
// The existing Sports and VLC engines are deliberately separate.

@MainActor
final class XSFebboxCatalogStore: ObservableObject {
    @Published private(set) var movies: [XSFebboxEntry] = []
    @Published private(set) var series: [XSFebboxEntry] = []
    @Published private(set) var loadingMovies = false
    @Published private(set) var loadingSeries = false
    @Published private(set) var moreMovies = true
    @Published private(set) var moreSeries = true
    @Published private(set) var errorMovies: String?
    @Published private(set) var errorSeries: String?

    private var movieNext = 1
    private var seriesNext = 1

    func entries(_ shelf: XSFebboxShelf) -> [XSFebboxEntry] {
        shelf == .movies ? movies : series
    }
    func loading(_ shelf: XSFebboxShelf) -> Bool {
        shelf == .movies ? loadingMovies : loadingSeries
    }
    func hasMore(_ shelf: XSFebboxShelf) -> Bool {
        shelf == .movies ? moreMovies : moreSeries
    }
    func error(_ shelf: XSFebboxShelf) -> String? {
        shelf == .movies ? errorMovies : errorSeries
    }

    func load(_ shelf: XSFebboxShelf, refresh: Bool = false) async {
        guard !loading(shelf) else { return }
        if refresh {
            if shelf == .movies {
                movies = []; movieNext = 1; moreMovies = true; errorMovies = nil
            } else {
                series = []; seriesNext = 1; moreSeries = true; errorSeries = nil
            }
        }
        guard hasMore(shelf) else { return }
        let page = shelf == .movies ? movieNext : seriesNext
        if shelf == .movies { loadingMovies = true }
        else { loadingSeries = true }
        defer {
            if shelf == .movies { loadingMovies = false }
            else { loadingSeries = false }
        }
        do {
            let result = try await XSFebboxLibraryService.shared.page(
                shelf: shelf, parent: "0", number: page, force: refresh
            )
            guard !Task.isCancelled else { return }
            if shelf == .movies {
                let known = Set(movies.map(\.id))
                let added = result.entries.filter { !known.contains($0.id) }
                movies.append(contentsOf: added)
                movieNext += 1
                moreMovies = result.hasNext && !added.isEmpty
                errorMovies = nil
            } else {
                let known = Set(series.map(\.id))
                let added = result.entries.filter { !known.contains($0.id) }
                series.append(contentsOf: added)
                seriesNext += 1
                moreSeries = result.hasNext && !added.isEmpty
                errorSeries = nil
            }
        } catch {
            if shelf == .movies { errorMovies = error.localizedDescription }
            else { errorSeries = error.localizedDescription }
        }
    }
}

@MainActor
final class XSFebboxSavedItems: ObservableObject {
    @Published private(set) var savedIDs: Set<String> = []
    private let key = "XS.TV.Febbox.favorites.v1"

    init() {
        savedIDs = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    func contains(_ entry: XSFebboxEntry) -> Bool { savedIDs.contains(entry.id) }
    func toggle(_ entry: XSFebboxEntry) {
        if !savedIDs.insert(entry.id).inserted { savedIDs.remove(entry.id) }
        UserDefaults.standard.set(Array(savedIDs).sorted(), forKey: key)
    }
}

private extension XSFebboxEntry {
    var catalogTitle: String {
        let clean = name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    var isVisibleContent: Bool { isDirectory || playable }
}

struct XSFebboxPremiumHomeView: View {
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    @EnvironmentObject private var favorites: XSFebboxSavedItems
    @Binding var showSettings: Bool
    @State private var showAccount = false

    private var featured: XSFebboxEntry? {
        catalog.movies.first(where: \.isVisibleContent)
            ?? catalog.series.first(where: \.isVisibleContent)
    }

    var body: some View {
        ZStack {
            XSV3ScreenBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 28) {
                    Color.clear.frame(height: 65)
                    if let featured {
                        NavigationLink {
                            XSFebboxTitleDestination(entry: featured)
                        } label: {
                            XSFebboxFeaturedCard(entry: featured)
                        }
                        .buttonStyle(XSV3PressStyle())
                        .padding(.horizontal, 18)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(XSV3.coral)
                        Text("المحتوى من FebBox مباشرة")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.76))
                    }
                    .padding(.horizontal, 23)
                    XSFebboxHomeRail(title: "الأفلام", eyebrow: "MOVIES", entries: catalog.movies)
                    XSFebboxHomeRail(title: "المسلسلات", eyebrow: "SERIES", entries: catalog.series)
                    let favoritesList = (catalog.movies + catalog.series).filter { favorites.contains($0) }
                    if !favoritesList.isEmpty {
                        XSFebboxHomeRail(title: "قائمتي", eyebrow: "MY LIST", entries: favoritesList)
                    }
                    if catalog.loadingMovies || catalog.loadingSeries {
                        ProgressView("جاري تحديث المحتوى من FebBox")
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                    } else if featured == nil {
                        VStack(spacing: 10) {
                            Label("لا يوجد محتوى ظاهر حالياً", systemImage: "externaldrive")
                            if let error = catalog.errorMovies ?? catalog.errorSeries {
                                Text(error).font(.caption).foregroundStyle(.orange)
                            }
                            Button("إعادة المحاولة") {
                                Task {
                                    await catalog.load(.movies, refresh: true)
                                    await catalog.load(.series, refresh: true)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.bottom, 60)
            }
            .refreshable {
                async let movie: Void = catalog.load(.movies, refresh: true)
                async let tv: Void = catalog.load(.series, refresh: true)
                _ = await (movie, tv)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 14) {
                XSWordmark(compact: true)
                Spacer()
                NavigationLink {
                    XSFebboxGlobalLibrarySearch()
                } label: {
                    Image(systemName: "magnifyingglass").frame(width: 36, height: 44)
                }
                NavigationLink {
                    XSFebboxSavedView()
                } label: {
                    Image(systemName: "bookmark").frame(width: 36, height: 44)
                }
                Button { showAccount = true } label: {
                    Image(systemName: "person.crop.circle").frame(width: 36, height: 44)
                }
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 36, height: 44)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .background(.black.opacity(0.82))
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if catalog.movies.isEmpty { await catalog.load(.movies) }
            if catalog.series.isEmpty { await catalog.load(.series) }
        }
        .sheet(isPresented: $showAccount) { XSFebboxAccountView() }
    }
}

private struct XSFebboxFeaturedCard: View {
    let entry: XSFebboxEntry

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            XSFebboxPoster(entry: entry)
                .frame(height: 320)
            LinearGradient(
                colors: [.clear, .black.opacity(0.45), .black.opacity(0.94)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 8) {
                Label("FEATURED FROM FEBBOX", systemImage: "sparkles")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(XSV3.coral)
                Text(entry.catalogTitle)
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                Label(entry.isDirectory ? "استعراض الحلقات والملفات" : "تفاصيل الفيلم والتشغيل",
                      systemImage: "play.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(20)
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.15)))
    }
}

private struct XSFebboxHomeRail: View {
    let title: String
    let eyebrow: String
    let entries: [XSFebboxEntry]

    var body: some View {
        let visible = Array(entries.filter(\.isVisibleContent).prefix(16))
        if !visible.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                XSV3SectionTitle(eyebrow: eyebrow, title: title)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 13) {
                        ForEach(visible) { entry in
                            NavigationLink {
                                XSFebboxTitleDestination(entry: entry)
                            } label: {
                                XSFebboxPosterTile(entry: entry, width: 140)
                            }
                            .buttonStyle(XSV3PressStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct XSFebboxPremiumCatalogView: View {
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    let shelf: XSFebboxShelf
    @State private var query = ""
    @State private var alphabetical = false

    private var visible: [XSFebboxEntry] {
        let input = catalog.entries(shelf).filter(\.isVisibleContent)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = q.isEmpty ? input : input.filter { $0.catalogTitle.localizedStandardContains(q) }
        return alphabetical ? matched.sorted {
            $0.catalogTitle.localizedStandardCompare($1.catalogTitle) == .orderedAscending
        } : matched
    }
    private let columns = [GridItem(.adaptive(minimum: 106, maximum: 180), spacing: 11)]

    var body: some View {
        ZStack {
            XSV3ScreenBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(shelf == .movies ? "MOVIE COLLECTION" : "SERIES COLLECTION")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(2.5).foregroundStyle(XSV3.coral)
                            Text(shelf.title).font(.system(size: 33, weight: .black, design: .rounded))
                        }
                        Spacer()
                        Button { alphabetical.toggle() } label: {
                            Label(alphabetical ? "A–Z" : "الترتيب الأصلي",
                                  systemImage: "arrow.up.arrow.down")
                                .font(.caption.bold())
                                .padding(10)
                                .background(.white.opacity(0.11), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 16)

                    LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
                        ForEach(visible) { entry in
                            NavigationLink {
                                XSFebboxTitleDestination(entry: entry)
                            } label: {
                                XSFebboxPosterTile(entry: entry, width: nil)
                            }
                            .buttonStyle(XSV3PressStyle())
                            .contextMenu {
                                XSFebboxSaveButton(entry: entry)
                            }
                        }
                    }
                    if catalog.loading(shelf) {
                        ProgressView().tint(.white).frame(maxWidth: .infinity)
                    }
                    if let error = catalog.error(shelf) {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("إعادة المحاولة") {
                            Task { await catalog.load(shelf) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if catalog.hasMore(shelf) && query.isEmpty {
                        Button {
                            Task { await catalog.load(shelf) }
                        } label: {
                            HStack {
                                Spacer()
                                Label("عرض المزيد", systemImage: "chevron.down")
                                Spacer()
                            }
                            .padding(14)
                            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                        }
                        .buttonStyle(.plain)
                        .disabled(catalog.loading(shelf))
                    }
                    if !query.isEmpty {
                        Text("البحث في العناوين المحملة. اضغط «عرض المزيد» لجلب بقية المكتبة.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 50)
            }
            .scrollIndicators(.hidden)
            .refreshable { await catalog.load(shelf, refresh: true) }
        }
        .searchable(text: $query, prompt: "ابحث في \(shelf.title)")
        .navigationTitle(shelf.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if catalog.entries(shelf).isEmpty { await catalog.load(shelf) }
        }
    }
}

struct XSFebboxTitleDestination: View {
    let entry: XSFebboxEntry
    var body: some View {
        if entry.isDirectory {
            XSFebboxPremiumFolderView(folder: entry)
        } else {
            XSFebboxFileDetailsView(file: entry)
        }
    }
}

struct XSFebboxPremiumFolderView: View {
    let folder: XSFebboxEntry
    @State private var entries: [XSFebboxEntry] = []
    @State private var nextPage = 1
    @State private var loading = false
    @State private var more = true
    @State private var error: String?
    @State private var search = ""
    private let columns = [GridItem(.adaptive(minimum: 105, maximum: 180), spacing: 12)]

    private var visible: [XSFebboxEntry] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = entries.filter(\.isVisibleContent)
        return q.isEmpty ? all : all.filter { $0.catalogTitle.localizedStandardContains(q) }
    }

    var body: some View {
        ZStack {
            XSV3ScreenBackdrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 17) {
                    XSFebboxFeaturedCard(entry: folder).frame(height: 245)
                    HStack {
                        Label(folder.shelf == .series ? "المواسم والحلقات" : "الملفات المتاحة",
                              systemImage: "rectangle.stack.fill")
                            .font(.title3.bold())
                        Spacer()
                        Text("\(entries.count)").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(visible.sorted {
                            $0.catalogTitle.localizedStandardCompare($1.catalogTitle) == .orderedAscending
                        }) { child in
                            NavigationLink {
                                XSFebboxTitleDestination(entry: child)
                            } label: {
                                XSFebboxPosterTile(entry: child, width: nil)
                            }
                            .buttonStyle(XSV3PressStyle())
                            .contextMenu { XSFebboxSaveButton(entry: child) }
                        }
                    }
                    if loading { ProgressView().tint(.white).frame(maxWidth: .infinity) }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.orange)
                        Button("إعادة المحاولة") { Task { await loadMore() } }
                    }
                    if more && search.isEmpty {
                        Button("عرض المزيد من المجلد") { Task { await loadMore() } }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity)
                            .disabled(loading)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                guard !loading else { return }
                entries = []; nextPage = 1; more = true
                await loadMore(force: true)
            }
        }
        .searchable(text: $search, prompt: "ابحث داخل \(folder.catalogTitle)")
        .navigationTitle(folder.catalogTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { if entries.isEmpty { await loadMore() } }
    }

    private func loadMore(force: Bool = false) async {
        guard !loading && more else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await XSFebboxLibraryService.shared.page(
                shelf: folder.shelf, parent: folder.fid, number: nextPage, force: force
            )
            guard !Task.isCancelled else { return }
            let seen = Set(entries.map(\.id))
            let incoming = page.entries.filter { !seen.contains($0.id) }
            entries.append(contentsOf: incoming)
            nextPage += 1
            more = page.hasNext && !incoming.isEmpty
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct XSFebboxPosterTile: View {
    let entry: XSFebboxEntry
    let width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            XSFebboxPoster(entry: entry)
                .aspectRatio(0.69, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
            Text(entry.catalogTitle)
                .font(.system(size: 12, weight: .semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .foregroundStyle(.white)
            Label(entry.isDirectory ? "مجموعة" : entry.fileExtension.uppercased(),
                  systemImage: entry.isDirectory ? "square.stack" : "play.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.59))
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct XSFebboxPoster: View {
    let entry: XSFebboxEntry

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.28, green: 0.16, blue: 0.39),
                             Color(red: 0.10, green: 0.11, blue: 0.20),
                             Color(red: 0.025, green: 0.035, blue: 0.09)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                if let url = entry.thumbnail {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            fallback
                        }
                    }
                } else {
                    fallback
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var fallback: some View {
        VStack(spacing: 10) {
            Image(systemName: entry.isDirectory ?
                  (entry.shelf == .movies ? "film.stack.fill" : "play.tv.fill") : "play.rectangle.fill")
                .font(.system(size: 42, weight: .thin))
                .foregroundStyle(.white.opacity(0.65))
            Text(entry.catalogTitle)
                .font(.system(size: 11, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .foregroundStyle(.white.opacity(0.82))
                .padding(.horizontal, 8)
        }
    }
}

struct XSFebboxSaveButton: View {
    @EnvironmentObject private var favorites: XSFebboxSavedItems
    let entry: XSFebboxEntry
    var body: some View {
        Button {
            favorites.toggle(entry)
        } label: {
            Label(favorites.contains(entry) ? "إزالة من قائمتي" : "إضافة إلى قائمتي",
                  systemImage: favorites.contains(entry) ? "bookmark.fill" : "bookmark")
        }
    }
}

struct XSFebboxSavedView: View {
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    @EnvironmentObject private var favorites: XSFebboxSavedItems
    private var entries: [XSFebboxEntry] {
        (catalog.movies + catalog.series).filter { favorites.contains($0) }
    }
    var body: some View {
        ZStack {
            XSV3ScreenBackdrop()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 12)], spacing: 20) {
                    ForEach(entries) { entry in
                        NavigationLink { XSFebboxTitleDestination(entry: entry) } label: {
                            XSFebboxPosterTile(entry: entry, width: nil)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { XSFebboxSaveButton(entry: entry) }
                    }
                }
                .padding(18)
            }
            if entries.isEmpty {
                Text("قائمتك فارغة. اضغط مطولاً على أي عنوان لحفظه.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("قائمتي")
    }
}

struct XSFebboxGlobalLibrarySearch: View {
    @EnvironmentObject private var catalog: XSFebboxCatalogStore
    @State private var query = ""
    private let columns = [GridItem(.adaptive(minimum: 108), spacing: 12)]

    private var matches: [XSFebboxEntry] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return (catalog.movies + catalog.series)
            .filter { $0.isVisibleContent && $0.catalogTitle.localizedStandardContains(term) }
    }
    var body: some View {
        ZStack {
            XSV3ScreenBackdrop()
            ScrollView {
                LazyVStack(spacing: 18) {
                    LazyVGrid(columns: columns, spacing: 17) {
                        ForEach(matches) { item in
                            NavigationLink { XSFebboxTitleDestination(entry: item) } label: {
                                XSFebboxPosterTile(entry: item, width: nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if catalog.hasMore(.movies) || catalog.hasMore(.series) {
                        Text("للبحث في بقية العناوين، يمكنك تحميل صفحات إضافية من المصدر.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("تحميل المزيد من الفهرس") {
                            Task {
                                if catalog.hasMore(.movies) { await catalog.load(.movies) }
                                if catalog.hasMore(.series) { await catalog.load(.series) }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(catalog.loading(.movies) || catalog.loading(.series))
                    }
                }
                .padding(18)
            }
        }
        .searchable(text: $query, prompt: "بحث في الأفلام والمسلسلات من FebBox")
        .navigationTitle("البحث")
        .task {
            if catalog.movies.isEmpty { await catalog.load(.movies) }
            if catalog.series.isEmpty { await catalog.load(.series) }
        }
    }
}
