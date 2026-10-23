import SwiftUI
import AVKit

// MARK: - XS TV World Cinema (clean native rebuild)
// The visual system and navigation are independent of provider endpoints.
// Cinemeta provides catalog metadata; ETWatch owns any website playback.
// Sports uses a separate, unmodified IPTV service.

enum XSCinemaStyle {
    static let background = Color(red: 0.026, green: 0.031, blue: 0.051)
    static let surface = Color(red: 0.085, green: 0.096, blue: 0.132)
    static let accent = Color(red: 0.99, green: 0.29, blue: 0.43)
    static let lavender = Color(red: 0.69, green: 0.46, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.79, blue: 0.52)
    static let secondary = Color.white.opacity(0.69)
}

struct XSWorldBackDrop: View {
    var body: some View {
        ZStack {
            XSCinemaStyle.background
            RadialGradient(colors: [XSCinemaStyle.lavender.opacity(0.14), .clear],
                           center: .topLeading, startRadius: 10, endRadius: 480)
            RadialGradient(colors: [XSCinemaStyle.accent.opacity(0.09), .clear],
                           center: .bottomTrailing, startRadius: 10, endRadius: 470)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct XSWorldTapStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.91 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.27, dampingFraction: 0.77),
                       value: configuration.isPressed)
    }
}

struct XSWorldPhoto: View {
    let item: XSCinemaMedia
    var backdrop = false
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [XSCinemaStyle.surface, .purple.opacity(0.24),
                                        XSCinemaStyle.background],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = backdrop ? item.backdropURL : item.imageURL {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.22))) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                                .transition(.opacity)
                        } else {
                            Image(systemName: item.kind == .movie ? "film.stack" : "play.tv")
                                .font(.system(size: 40, weight: .ultraLight))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }
                } else {
                    Image(systemName: item.kind == .movie ? "film.stack" : "play.tv")
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

struct XSWorldBrandHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            XSWordmark(compact: true)
            Spacer()
            NavigationLink {
                XSWorldSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 43, height: 43)
            }
            .accessibilityLabel("بحث")
            NavigationLink {
                XSWorldWatchlist()
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 43, height: 43)
            }
            .accessibilityLabel("قائمتي")
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background {
            LinearGradient(colors: [XSCinemaStyle.background.opacity(0.96),
                                    XSCinemaStyle.background.opacity(0.67)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

struct XSWorldHero: View {
    let items: [XSCinemaMedia]
    @State private var current = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var item: XSCinemaMedia? {
        guard !items.isEmpty else { return nil }
        return items[current % items.count]
    }

    var body: some View {
        Group {
            if let item {
                ZStack(alignment: .bottomLeading) {
                    XSWorldPhoto(item: item, backdrop: true)
                        .id(item.id)
                        .transition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.33), value: current)
                    LinearGradient(stops: [
                        .init(color: XSCinemaStyle.background.opacity(0.15), location: 0),
                        .init(color: .clear, location: 0.27),
                        .init(color: XSCinemaStyle.background.opacity(0.46), location: 0.53),
                        .init(color: XSCinemaStyle.background, location: 0.99)
                    ], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle().fill(XSCinemaStyle.accent)
                                .frame(width: 7, height: 7)
                            Text("THE SPOTLIGHT")
                                .font(.system(size: 10, weight: .black, design: .rounded))
                                .tracking(2.7)
                            Spacer()
                            Text(String(format: "%02d / %02d", current + 1, items.count))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        Text("FEATURED TONIGHT")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(2.2)
                            .foregroundStyle(XSCinemaStyle.gold)
                        Text(item.title)
                            .font(.system(size: 35, weight: .black, design: .rounded))
                            .tracking(-0.8)
                            .minimumScaleFactor(0.68)
                            .lineLimit(2)
                        HStack(spacing: 9) {
                            Text(item.year)
                            Text(item.kind == .movie ? "MOVIE" : "SERIES")
                            if item.rating > 0 {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(XSCinemaStyle.gold)
                                Text(String(format: "%.1f", item.rating))
                            }
                        }
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.77))
                        if !item.summary.isEmpty {
                            Text(item.summary)
                                .font(.system(size: 13))
                                .lineLimit(2)
                                .lineSpacing(4)
                                .foregroundStyle(.white.opacity(0.73))
                        }
                        NavigationLink {
                            XSWorldDetail(item: item)
                        } label: {
                            HStack(spacing: 10) {
                                Label("استكشف العمل", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .foregroundStyle(.black)
                                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
                                Image(systemName: "info.circle.fill")
                                    .frame(width: 51, height: 50)
                                    .foregroundStyle(.white)
                                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                        .buttonStyle(XSWorldTapStyle())
                        HStack(spacing: 7) {
                            ForEach(items.indices, id: \.self) { index in
                                Capsule().fill(current == index
                                    ? XSCinemaStyle.accent : .white.opacity(0.27))
                                    .frame(width: current == index ? 27 : 6, height: 4)
                                    .animation(.easeOut(duration: 0.22), value: current)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 23)
                    .padding(.top, 42)
                    .padding(.bottom, 15)
                }
                .frame(height: 505)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 55).onEnded { value in
                    guard items.count > 1, abs(value.translation.width) > 70,
                          abs(value.translation.width) > abs(value.translation.height) * 1.2 else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.25)) {
                        current = (current + items.count + (value.translation.width < 0 ? 1 : -1)) % items.count
                    }
                })
                .task(id: items.map(\.id).joined(separator: "|")) {
                    guard items.count > 1, !reduceMotion else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: 7_000_000_000)
                        if Task.isCancelled { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            current = (current + 1) % items.count
                        }
                    }
                }
            }
        }
    }
}

struct XSWorldPosterCard: View {
    let item: XSCinemaMedia
    var width: CGFloat = 148

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                XSWorldPhoto(item: item)
                LinearGradient(colors: [.clear, .black.opacity(0.67)],
                               startPoint: .center, endPoint: .bottom)
                if item.rating > 0 {
                    Label(String(format: "%.1f", item.rating), systemImage: "star.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(XSCinemaStyle.gold)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.58), in: Capsule())
                        .padding(9)
                }
            }
            .frame(width: width, height: width * 1.43)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(.white.opacity(0.11)))
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
                .foregroundStyle(.white)
            Text(item.year.isEmpty ? item.kind.label : item.year)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(XSCinemaStyle.secondary)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct XSWorldRail: View {
    let eyebrow: String
    let title: String
    let items: [XSCinemaMedia]
    var ranking = false
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(eyebrow.uppercased())
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(2.5)
                        .foregroundStyle(XSCinemaStyle.accent)
                    Text(title)
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: ranking ? 20 : 13) {
                        ForEach(Array(items.prefix(ranking ? 10 : 30).enumerated()),
                                id: \.element.id) { index, item in
                            NavigationLink {
                                XSWorldDetail(item: item)
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    XSWorldPosterCard(item: item, width: ranking ? 161 : 145)
                                        .padding(.leading, ranking ? 18 : 0)
                                    if ranking {
                                        Text("\(index + 1)")
                                            .font(.system(size: 78, weight: .black, design: .rounded))
                                            .tracking(-9)
                                            .foregroundStyle(XSCinemaStyle.background)
                                            .shadow(color: .white.opacity(0.82), radius: 1.3)
                                            .offset(x: -10, y: -43)
                                            .accessibilityHidden(true)
                                    }
                                }
                            }
                            .buttonStyle(XSWorldTapStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct XSWorldHome: View {
    @EnvironmentObject private var cinema: XSCinemaNativeStore
    private var collection: [XSCinemaMedia] { cinema.movies + cinema.series }

    var body: some View {
        ZStack {
            XSWorldBackDrop()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 29) {
                    XSWorldHero(items: Array(cinema.movies.prefix(5)))
                    discoveryCards
                    XSWorldRail(eyebrow: "POPULAR RIGHT NOW", title: "Trending Movies",
                                items: cinema.movies, ranking: true)
                    XSWorldRail(eyebrow: "BINGE-WORTHY SERIES", title: "Stories worth staying for",
                                items: cinema.series)
                    if !cinema.freeMovies.isEmpty {
                        XSWorldRail(eyebrow: "OPEN-LICENSE PLAYBACK",
                                    title: "مجانية للمشاهدة",
                                    items: cinema.freeMovies)
                    }
                    XSWorldRail(eyebrow: "SELECTED FOR YOU", title: "Your next movie night",
                                items: Array(cinema.movies.dropFirst(8)))
                    XSWorldRail(eyebrow: "POPULAR SERIES", title: "The top 10",
                                items: cinema.series, ranking: true)
                    if !cinema.favorites.isEmpty {
                        XSWorldRail(eyebrow: "YOUR COLLECTION", title: "قائمتي",
                                    items: (collection + cinema.freeMovies).filter {
                                        cinema.favorites.contains($0.id)
                                    })
                    }
                    XSWorldEditorial()
                }
                .padding(.bottom, 52)
            }
            .scrollIndicators(.hidden)
            .refreshable { await cinema.refresh() }
        }
        .safeAreaInset(edge: .top, spacing: 0) { XSWorldBrandHeader() }
        .navigationBarHidden(true)
        .task { await cinema.boot() }
    }

    private var discoveryCards: some View {
        HStack(spacing: 13) {
            NavigationLink {
                XSWorldBrowse(kind: .movie)
            } label: {
                XSWorldDiscoveryCard(title: "Movies", subtitle: "Explore cinema",
                                     symbol: "film.stack.fill", color: XSCinemaStyle.lavender)
            }
            NavigationLink {
                XSWorldBrowse(kind: .series)
            } label: {
                XSWorldDiscoveryCard(title: "Series", subtitle: "Find your next story",
                                     symbol: "play.tv.fill", color: XSCinemaStyle.accent)
            }
        }
        .buttonStyle(XSWorldTapStyle())
        .padding(.horizontal, 18)
    }
}

struct XSWorldDiscoveryCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [color.opacity(0.26),
                                              XSCinemaStyle.surface, XSCinemaStyle.background],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 25))
                        .foregroundStyle(color)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption.bold())
                }
                Spacer()
                Text(title).font(.system(size: 22, weight: .black, design: .rounded))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .foregroundStyle(.white)
            .padding(16)
        }
        .frame(height: 155)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
    }
}

struct XSWorldEditorial: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("BUILT FOR THE BIG SCREEN")
                .font(.system(size: 10, weight: .black))
                .tracking(2.3)
                .foregroundStyle(XSCinemaStyle.accent)
            Text("XS TV")
                .font(.system(size: 39, weight: .black, design: .rounded))
            Text("تجربة سينمائية نيتيف بتصميم مستقل عن المواقع والمشغلات الخارجية.")
                .font(.subheadline)
                .foregroundStyle(XSCinemaStyle.secondary)
                .lineSpacing(5)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [XSCinemaStyle.lavender.opacity(0.20),
                                              XSCinemaStyle.surface],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.10)))
        .padding(.horizontal, 19)
    }
}
