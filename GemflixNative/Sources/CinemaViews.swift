import SwiftUI
import UIKit

struct MainScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var section: MainSection = .home
    @State private var currentPlayer: PlayerSelection?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                CinemaPalette.base.ignoresSafeArea()
                Group {
                    switch section {
                    case .home: GemflixHomeScreen()
                    case .movies: CatalogScreen(kind: .movie)
                    case .series: CatalogScreen(kind: .series)
                    case .saved: GemflixSavedScreen()
                    }
                }
                .padding(.bottom, 77)

                HStack(spacing: 5) {
                    ForEach(MainSection.allCases, id: \.self) { destination in
                        Button {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                                section = destination
                            }
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: destination.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .symbolRenderingMode(.hierarchical)
                                Text(destination.name)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(section == destination ? CinemaPalette.accent : .white.opacity(0.58))
                            .frame(maxWidth: .infinity)
                            .frame(height: 51)
                            .background {
                                if section == destination {
                                    RoundedRectangle(cornerRadius: 18)
                                        .fill(CinemaPalette.accent.opacity(0.13))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(section == destination ? .isSelected : [])
                    }
                }
                .padding(6)
                .background(CinemaPalette.elevated.opacity(0.96), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10)))
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
            .navigationDestination(for: MediaTitle.self) { title in
                TitleDetailScreen(original: title)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $currentPlayer) { value in
            NativePlayerScreen(title: value.title, entry: value.entry)
        }
        .tint(CinemaPalette.accent)
    }
}

struct CatalogScreen: View {
    @EnvironmentObject private var store: CinemaStore
    let kind: MediaKind
    @State private var search = ""
    @State private var selectedGenre = "الكل"

    private let genres = ["الكل", "Action", "Drama", "Comedy", "Thriller", "Horror",
                          "Romance", "Animation", "Crime", "Adventure", "Science Fiction"]

    private var titles: [MediaTitle] { kind == .movie ? store.movies : store.series }
    private var filteredTitles: [MediaTitle] {
        guard selectedGenre != "الكل" else { return titles }
        return titles.filter { $0.genres.contains { $0.localizedCaseInsensitiveContains(selectedGenre) } }
    }
    private var showingResults: Bool { search.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                searchBar
                genreSelector

                if showingResults {
                    if store.searching { ProgressView().tint(CinemaPalette.accent).frame(maxWidth: .infinity).padding(30) }
                    posterGrid(store.searchResults)
                } else if titles.isEmpty {
                    VStack(spacing: 15) {
                        ProgressView().tint(CinemaPalette.accent)
                        Text(store.errorMessage ?? "جارٍ تحميل المكتبة")
                            .foregroundStyle(CinemaPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    editorialHeader(selectedGenre == "الكل" ? "كل \(kind.title)" : selectedGenre,
                                    detail: "اكتشف أعمالًا جديدة كل يوم")
                    posterGrid(filteredTitles)
                }
            }
            .padding(.bottom, 18)
        }
        .refreshable { await store.reload() }
        .scrollIndicators(.hidden)
        .background(CinemaPalette.base)
        .onChange(of: search) { value in store.search(value, kind: kind) }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(CinemaPalette.accent)
                    Text("GEMFLIX")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .tracking(2.3)
                }
                Text(kind == .movie ? "عالم السينما" : "قصص تستمر")
                    .font(.system(size: 12))
                    .foregroundStyle(CinemaPalette.secondary)
            }
            Spacer()
            Label("ORIGINAL iOS", systemImage: "sparkles")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CinemaPalette.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(CinemaPalette.accent.opacity(0.11), in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
    }

    private var genreSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedGenre = genre }
                    } label: {
                        Text(genre)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(selectedGenre == genre ? .white : CinemaPalette.secondary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 9)
                            .background(selectedGenre == genre ? CinemaPalette.accent : CinemaPalette.elevated,
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(CinemaPalette.accent)
            TextField(kind == .movie ? "ابحث عن فيلم" : "ابحث عن مسلسل", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 14))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CinemaPalette.secondary)
                }
            }
        }
        .padding(14)
        .background(CinemaPalette.elevated, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.075)))
        .padding(.horizontal, 22)
    }

    private func featuredTitle(_ title: MediaTitle) -> some View {
        NavigationLink(value: title) {
            ZStack(alignment: .bottomLeading) {
                PosterImage(url: title.backdropURL ?? title.posterURL, contentMode: .fill)
                    .frame(height: 385)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.08), CinemaPalette.base.opacity(0.98)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 13) {
                    Label("اختيار اليوم", systemImage: "sparkle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CinemaPalette.accent)
                        .tracking(1)
                    Text(title.title)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    HStack(spacing: 9) {
                        Text(title.year)
                        if !title.rating.isEmpty {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                            Text(title.rating)
                        }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.82))
                    HStack(spacing: 7) {
                        Image(systemName: "play.fill")
                        Text("التفاصيل والتشغيل")
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CinemaPalette.base)
                    .padding(.horizontal, 21)
                    .padding(.vertical, 13)
                    .background(CinemaPalette.accent, in: Capsule())
                }
                .padding(23)
            }
            .frame(height: 385)
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.08)))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private func editorialHeader(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 23, weight: .bold, design: .rounded))
                Text(detail).font(.system(size: 12)).foregroundStyle(CinemaPalette.secondary)
            }
            Spacer()
            Image(systemName: "arrow.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CinemaPalette.accent)
        }
        .padding(.horizontal, 22)
    }

    private func horizontalRail(_ titles: [MediaTitle]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 13) {
                ForEach(titles) { title in
                    NavigationLink(value: title) {
                        MediaPoster(item: title, width: 143)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
        }
        .scrollIndicators(.hidden)
    }

    private func posterGrid(_ titles: [MediaTitle]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)], spacing: 19) {
            ForEach(titles) { title in
                NavigationLink(value: title) {
                    MediaPoster(item: title, width: nil)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
    }
}

struct PosterImage: View {
    var url: URL?
    var contentMode: ContentMode = .fill

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.3))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: contentMode)
            case .failure:
                placeholder
            case .empty:
                placeholder.overlay(ProgressView().tint(CinemaPalette.accent))
            @unknown default:
                placeholder
            }
        }
        .background(CinemaPalette.elevated)
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(LinearGradient(colors: [CinemaPalette.elevated, CinemaPalette.base],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "film").font(.title).foregroundStyle(.white.opacity(0.12)))
    }
}

struct MediaPoster: View {
    let item: MediaTitle
    let width: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PosterImage(url: item.posterURL)
                .frame(width: width, height: width.map { $0 * 1.48 })
                .aspectRatio(0.68, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Image(systemName: "star.fill").foregroundStyle(.yellow.opacity(0.9))
                Text(item.rating.isEmpty ? "—" : item.rating)
                if !item.year.isEmpty {
                    Text("·")
                    Text(item.year.prefix(4))
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(CinemaPalette.secondary)
        }
        .frame(width: width)
        .contentShape(Rectangle())
    }
}

struct TitleDetailScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var item: MediaTitle
    @State private var selectedSeason = 1
    @State private var currentPlayer: PlayerSelection?
    @State private var embeddedPlayer: EmbeddedSelection?

    init(original: MediaTitle) { _item = State(initialValue: original) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                GeometryReader { geometry in
                    ZStack(alignment: .bottomLeading) {
                        PosterImage(url: item.backdropURL ?? item.posterURL)
                            .frame(width: geometry.size.width, height: 355)
                            .clipped()
                        LinearGradient(colors: [.clear, CinemaPalette.base.opacity(0.82), CinemaPalette.base],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 10) {
                            Text(item.kind == .movie ? "MOVIE" : "SERIES")
                                .font(.system(size: 10, weight: .black))
                                .tracking(3)
                                .foregroundStyle(CinemaPalette.accent)
                            Text(item.title)
                                .font(.system(size: 31, weight: .black, design: .rounded))
                                .lineLimit(3)
                                .minimumScaleFactor(0.75)
                            HStack(spacing: 10) {
                                Text(item.year)
                                if !item.rating.isEmpty {
                                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                                    Text(item.rating)
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CinemaPalette.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                    }
                    .frame(width: geometry.size.width, height: 355)
                }
                .frame(height: 355)

                HStack(spacing: 11) {
                    Button {
                        play(movieOrFirstEpisode: true)
                    } label: {
                        Label(item.kind == .movie ? "تشغيل الفيلم" : "تشغيل الحلقة الأولى", systemImage: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 53)
                    }
                    .foregroundStyle(CinemaPalette.base)
                    .background(CinemaPalette.accent, in: RoundedRectangle(cornerRadius: 17))
                    Button { store.toggleFavorite(item.id) } label: {
                        Image(systemName: store.favorites.contains(item.id) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 54, height: 53)
                            .background(CinemaPalette.elevated, in: RoundedRectangle(cornerRadius: 17))
                    }
                    .accessibilityLabel("المفضلة")
                }
                .padding(.horizontal, 21)

                if !item.synopsis.isEmpty {
                    Text(item.synopsis)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineSpacing(5)
                        .padding(.horizontal, 22)
                }

                if item.kind == .series {
                    HStack {
                        Text("الحلقات").font(.title2.bold())
                        Spacer()
                        Menu {
                            ForEach(item.seasons, id: \.self) { season in
                                Button("الموسم \(season)") { selectedSeason = season }
                            }
                        } label: {
                            Label("الموسم \(selectedSeason)", systemImage: "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(11)
                                .background(CinemaPalette.elevated, in: Capsule())
                        }
                    }
                    .padding(.horizontal, 22)

                    LazyVStack(spacing: 13) {
                        ForEach(item.episodes.filter { $0.season == selectedSeason }) { episode in
                            Button { play(episode: episode) } label: {
                                HStack(spacing: 12) {
                                    PosterImage(url: episode.artworkURL)
                                        .frame(width: 132, height: 79)
                                        .clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("E\(episode.number) · \(episode.title)")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(.white)
                                            .lineLimit(2)
                                        Text("اضغط للمشاهدة")
                                            .font(.system(size: 11))
                                            .foregroundStyle(CinemaPalette.secondary)
                                    }
                                    Spacer(minLength: 3)
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(CinemaPalette.accent)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22)
                }
            }
            .padding(.bottom, 35)
        }
        .background(CinemaPalette.base.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "arrow.backward")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.57), in: Circle())
            }
            .padding(.leading, 20)
            .padding(.top, 57)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            item = await store.detail(item)
            selectedSeason = item.seasons.first ?? 1
        }
        .fullScreenCover(item: $currentPlayer) { value in
            NativePlayerScreen(title: value.title, entry: value.entry)
        }
        .fullScreenCover(item: $embeddedPlayer) { selection in
            EmbeddedPlayerScreen(selection: selection)
        }
    }

    private func play(movieOrFirstEpisode: Bool = false, episode: Episode? = nil) {
        let selected = episode ?? (movieOrFirstEpisode ? item.episodes.first : nil)
        let key: String = item.kind == .movie
            ? PlaybackKey.movie(item.id)
            : PlaybackKey.episode(item.id, season: selected?.season ?? 1, number: selected?.number ?? 1)
        let title = selected.map { "\(item.title) · S\($0.season) E\($0.number)" } ?? item.title
        if let entry = store.entry(for: key), !entry.sources.isEmpty {
            currentPlayer = PlayerSelection(title: title, entry: entry)
        } else {
            embeddedPlayer = EmbeddedSelection(
                title: title,
                mediaID: item.id,
                kind: item.kind,
                season: selected?.season ?? 1,
                episode: selected?.number ?? 1
            )
        }
    }
}

