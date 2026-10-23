import SwiftUI

// Native-only editorial shelves inspired by the user's reference screenshots.
// Every collection is derived from actual Cinemeta catalog entries and their
// published rating/year. No invented Netflix/Oscar affiliations or streams.
private enum XSEditorialPalette27 {
    static let mint = Color(red: 0.50, green: 0.77, blue: 0.67)
    static let soft = Color.white.opacity(0.64)
    static let base = Color(red: 0.027, green: 0.031, blue: 0.049)
    static let outline = Color.white.opacity(0.11)
}

struct XSAtmosphericCinemaBackdropV27: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                XSEditorialPalette27.base
                RadialGradient(
                    colors: [Color(red: 0.19, green: 0.25, blue: 0.27).opacity(0.75), .clear],
                    center: .init(x: 0.23, y: 0.04),
                    startRadius: 20,
                    endRadius: max(proxy.size.width, 410))
                RadialGradient(
                    colors: [Color(red: 0.33, green: 0.23, blue: 0.19).opacity(0.50), .clear],
                    center: .init(x: 0.91, y: 0.62),
                    startRadius: 15,
                    endRadius: max(proxy.size.width, 500))
                LinearGradient(colors: [.clear, .black.opacity(0.13)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

struct XSEditorialCollectionsV27: View {
    @EnvironmentObject private var store: XSCinemaNativeStore

    private func releaseYear(_ value: String) -> Int? {
        guard let range = value.range(of: #"(?:19|20)\d{2}"#,
                                      options: .regularExpression) else { return nil }
        return Int(value[range])
    }

    private var recentMovies: [XSCinemaMedia] {
        store.movies.filter { (releaseYear($0.year) ?? 0) >= 2023 }
            .sorted { (releaseYear($0.year) ?? 0) > (releaseYear($1.year) ?? 0) }
    }
    private var classicMovies: [XSCinemaMedia] {
        store.movies.filter {
            let y = releaseYear($0.year) ?? 9999
            return y < 2000 && y >= 1920
        }
    }
    private var recentSeries: [XSCinemaMedia] {
        store.series.filter { (releaseYear($0.year) ?? 0) >= 2022 }
            .sorted { (releaseYear($0.year) ?? 0) > (releaseYear($1.year) ?? 0) }
    }
    private var ratedMovies: [XSCinemaMedia] {
        store.movies.filter { $0.rating > 0 }
            .sorted { $0.rating > $1.rating }
    }
    private var ratedSeries: [XSCinemaMedia] {
        store.series.filter { $0.rating > 0 }
            .sorted { $0.rating > $1.rating }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 33) {
            if !store.shelves.isEmpty {
                ForEach(store.shelves) { shelf in
                    rail("", title: shelf.title, items: store.shelfItems(shelf))
                }
            } else {
            rail("TOP RATED", title: "الأفلام الأعلى تقييماً",
                 items: ratedMovies)
            rail("TRENDING SHOWS", title: "مسلسلات رائجة",
                 items: store.series)
            rail("NEW & NOTABLE", title: "أفلام حديثة",
                 items: recentMovies)
            rail("CRITICS' PICKS", title: "مسلسلات الأعلى تقييماً",
                 items: ratedSeries)
            rail("THIS YEAR & RECENTLY", title: "مسلسلات جديدة",
                 items: recentSeries)
            rail("CINEMA CLASSICS", title: "كلاسيكيات السينما",
                 items: classicMovies)
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func rail(_ eyebrow: String, title: String,
                      items: [XSCinemaMedia]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !eyebrow.isEmpty {
                            Text(eyebrow).font(.system(size: 10, weight: .bold))
                                .tracking(2.3).foregroundStyle(XSEditorialPalette27.mint)
                        }
                        Text(title)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    NavigationLink {
                        XSEditorialCollectionBrowseV27(title: title, items: items)
                    } label: {
                        HStack(spacing: 5) {
                            Text("عرض الكل")
                            Image(systemName: "arrow.up.left")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(XSEditorialPalette27.soft)
                    }
                }
                .padding(.horizontal, 21)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(Array(items.prefix(25))) { media in
                            NavigationLink {
                                XSCinemaNativeDetailView(media: media)
                            } label: {
                                editorialPoster(media)
                            }
                            .buttonStyle(XSEditorialPressStyleV27())
                        }
                    }
                    .padding(.horizontal, 19)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func editorialPoster(_ media: XSCinemaMedia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { bounds in
                ZStack {
                    LinearGradient(colors: [
                        Color(red: 0.20, green: 0.20, blue: 0.26),
                        XSEditorialPalette27.base
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let url = media.imageURL {
                        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.20))) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: media.kind == .movie ? "film.stack" : "play.tv")
                                    .font(.system(size: 27, weight: .ultraLight))
                                    .foregroundStyle(.white.opacity(0.31))
                            }
                        }
                    }
                }
                .frame(width: bounds.size.width, height: bounds.size.height)
                .clipped()
            }
            .frame(width: 158, height: 227)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(XSEditorialPalette27.outline))
            Text(media.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                if media.rating > 0 {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color(red: 0.99, green: 0.76, blue: 0.43))
                    Text(String(format: "%.1f", media.rating))
                }
                if !media.year.isEmpty {
                    Text(String(media.year.prefix(4)))
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(XSEditorialPalette27.soft)
        }
        .frame(width: 158, alignment: .leading)
    }
}

struct XSEditorialCollectionBrowseV27: View {
    let title: String
    let items: [XSCinemaMedia]

    var body: some View {
        ZStack {
            XSAtmosphericCinemaBackdropV27()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("\(items.count) عنوان في هذه المجموعة")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.60))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 13)],
                              spacing: 24) {
                        ForEach(items) { media in
                            NavigationLink {
                                XSCinemaNativeDetailView(media: media)
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    GeometryReader { frame in
                                        ZStack {
                                            Color.white.opacity(0.07)
                                            if let url = media.imageURL {
                                                AsyncImage(url: url) { phase in
                                                    if case .success(let image) = phase {
                                                        image.resizable().scaledToFill()
                                                    } else {
                                                        Image(systemName: "film.stack")
                                                            .foregroundStyle(.white.opacity(0.3))
                                                    }
                                                }
                                            }
                                        }
                                        .frame(width: frame.size.width, height: frame.size.height)
                                        .clipped()
                                    }
                                    .aspectRatio(0.70, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 13))
                                    Text(media.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    if media.rating > 0 {
                                        Label(String(format: "%.1f", media.rating), systemImage: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.white.opacity(0.65))
                                    }
                                }
                            }
                            .buttonStyle(XSEditorialPressStyleV27())
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 50)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct XSEditorialPressStyleV27: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: reduceMotion ? 0 : 0.16),
                       value: configuration.isPressed)
    }
}

struct XSSeasonStripV27: View {
    let seasons: [Int]
    @Binding var selected: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("المواسم")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(seasons.count) مواسم")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 9) {
                    ForEach(seasons, id: \.self) { season in
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) { selected = season }
                        } label: {
                            HStack(spacing: 7) {
                                if selected == season {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                Text("الموسم \(season)")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(selected == season ? .black : .white.opacity(0.82))
                            .padding(.horizontal, 15)
                            .frame(height: 39)
                            .background(selected == season
                                ? XSEditorialPalette27.mint : Color.white.opacity(0.085),
                                in: Capsule())
                            .overlay(Capsule().stroke(
                                selected == season ? .clear : XSEditorialPalette27.outline))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

struct XSEpisodePosterRowV27: View {
    let episode: XSCinemaEpisode
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.white.opacity(0.09))
                if let raw = episode.thumbnail, let imageURL = URL(string: raw) {
                    AsyncImage(url: imageURL) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Image(systemName: "play.rectangle")
                                .font(.system(size: 22))
                                .foregroundStyle(.white.opacity(0.38))
                        }
                    }
                    .frame(width: 122, height: 80)
                    .clipped()
                }
                Text("E\(episode.number)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.74), in: Capsule())
                    .padding(7)
            }
            .frame(width: 122, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 7) {
                Text(episode.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.white)
                Text("S\(episode.season) · E\(episode.number)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer(minLength: 5)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 25))
                .foregroundStyle(XSEditorialPalette27.mint)
        }
        .padding(9)
        .background(.white.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(XSEditorialPalette27.outline))
        .contentShape(Rectangle())
    }
}
