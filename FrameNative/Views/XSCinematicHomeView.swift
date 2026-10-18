import SwiftUI

// R5 Cinematic: presentation-only components. Player, IPTV and subtitle engines stay untouched.
enum XSCinemaStyle {
    static let background = Color(red: 0.035, green: 0.041, blue: 0.065)
    static let surface = Color(red: 0.095, green: 0.105, blue: 0.145)
    static let accent = Color(red: 1.0, green: 0.29, blue: 0.39)
    static let warm = Color(red: 1.0, green: 0.79, blue: 0.54)
    static let secondary = Color.white.opacity(0.63)
}

struct XSCinematicHomeView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Binding var showSettings: Bool
    @State private var featuredIndex = 0

    private var featuredItems: [MediaItem] {
        let items = Array(app.trendingMovies.prefix(5))
        return items.isEmpty ? Array(app.spotlight.prefix(5)) : items
    }

    var body: some View {
        ZStack {
            XSCinemaStyle.background.ignoresSafeArea()
            if app.isLoading && !app.didLoad {
                PremiumLoadingView(message: "Setting the scene…")
            } else if let error = app.errorMessage, !app.didLoad {
                VStack(spacing: 18) {
                    EmptyStateView(title: "Couldn't Load", message: error, systemImage: "wifi.exclamationmark")
                    Button("Try Again") { Task { await app.loadHome(force: true) } }
                        .buttonStyle(.borderedProminent)
                        .tint(XSCinemaStyle.accent)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !featuredItems.isEmpty {
                            cinematicHero
                        }
                        exploreStrip
                            .padding(.top, 27)
                        liveArenaFeature
                            .padding(.top, 27)
                        continueWatching
                            .padding(.top, 34)
                        cinemaRail("Trending this week", overline: "THE SPOTLIGHT", items: app.trendingMovies)
                            .padding(.top, 37)
                        cinemaRail("Movie night", overline: "HANDPICKED FOR YOU", items: app.popularMovies)
                            .padding(.top, 36)
                        editorialFeature
                            .padding(.top, 38)
                        cinemaRail("Stories worth staying for", overline: "BINGE-WORTHY SERIES", items: app.popularTV)
                            .padding(.top, 36)
                    }
                    .padding(.bottom, 64)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)
                .refreshable { await app.loadHome(force: true) }
            }
        }
        .overlay(alignment: .top) { cinematicHeader }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var cinematicHeader: some View {
        HStack(spacing: 10) {
            XSWordmark(compact: true)
                .accessibilityLabel("XS TV")
            Spacer(minLength: 5)
            NavigationLink {
                XSGlobalSearchView()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 41, height: 44)
            }
            .accessibilityLabel("Search")

            NavigationLink {
                MyListView()
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 41, height: 44)
            }
            .accessibilityLabel("My List")

            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 41, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [XSCinemaStyle.background.opacity(0.90),
                         XSCinemaStyle.background.opacity(0.40)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    private var cinematicHero: some View {
        let item = featuredItems[min(featuredIndex, featuredItems.count - 1)]
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: item, backdrop: true, cornerRadius: 0)
                    .frame(height: 545)
                    .clipped()
                    .id(item.id)

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.46), location: 0.0),
                        .init(color: .clear, location: 0.27),
                        .init(color: XSCinemaStyle.background.opacity(0.25), location: 0.45),
                        .init(color: XSCinemaStyle.background.opacity(0.88), location: 0.78),
                        .init(color: XSCinemaStyle.background, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(XSCinemaStyle.accent)
                            .frame(width: 7, height: 7)
                        Text("THE SPOTLIGHT")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(2.8)
                        Spacer()
                        Text(String(format: "%02d  /  %02d", featuredIndex + 1, featuredItems.count))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(.white.opacity(0.92))

                    Spacer(minLength: 20)

                    Text("FEATURED TONIGHT")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .tracking(2.2)
                        .foregroundStyle(XSCinemaStyle.warm)
                        .padding(.bottom, 8)

                    Text(item.title)
                        .font(.system(size: 37, weight: .black, design: .rounded))
                        .tracking(-1.3)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.40), radius: 10, y: 3)

                    HStack(spacing: 10) {
                        Text(item.year)
                        Circle().frame(width: 3, height: 3)
                        Text(item.kind == .tv ? "SERIES" : "FILM")
                        if item.voteAverage > 0 {
                            Circle().frame(width: 3, height: 3)
                            Image(systemName: "star.fill")
                                .foregroundStyle(XSCinemaStyle.warm)
                            Text(item.ratingText)
                        }
                    }
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.9)
                    .foregroundStyle(.white.opacity(0.84))
                    .padding(.top, 12)

                    if !item.overview.isEmpty {
                        Text(item.overview)
                            .font(.system(size: 13))
                            .lineSpacing(3)
                            .lineLimit(2)
                            .foregroundStyle(.white.opacity(0.80))
                            .padding(.top, 13)
                    }

                    HStack(spacing: 11) {
                        NavigationLink {
                            FrameXTVPlayerScreen(item: item, playback: FrameXTVPlayback(tmdbID: item.tmdbID))
                                .toolbar(.hidden, for: .tabBar)
                        } label: {
                            Label("Play now", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 49)
                                .foregroundStyle(.black)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        NavigationLink(value: item) {
                            Label("Details", systemImage: "info.circle")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 49)
                                .foregroundStyle(.white)
                                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.22)))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                }
                .padding(.horizontal, 22)
                // The image extends beneath the status/nav bars; the content does not.
                .padding(.top, 126)
                .padding(.bottom, 18)
            }
            .frame(height: 545)

            HStack(spacing: 9) {
                ForEach(featuredItems.indices, id: \.self) { index in
                    Button {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            featuredIndex = index
                        }
                    } label: {
                        RemotePoster(item: featuredItems[index], cornerRadius: 9)
                            .frame(maxWidth: .infinity)
                            .frame(height: 74)
                            .overlay(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .stroke(index == featuredIndex ? XSCinemaStyle.accent : .white.opacity(0.13),
                                            lineWidth: index == featuredIndex ? 2.5 : 1)
                            )
                            .opacity(index == featuredIndex ? 1 : 0.65)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Featured title \(index + 1): \(featuredItems[index].title)")
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 3)
        }
    }

    private var exploreStrip: some View {
        VStack(alignment: .leading, spacing: 15) {
            XSCinemaHeadline(eyebrow: "YOUR WORLD OF ENTERTAINMENT", title: "Explore")
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    exploreLink("Movies", symbol: "film.stack", tint: .orange, kind: .movie)
                    exploreLink("Series", symbol: "play.tv", tint: .purple, kind: .tv)
                }
                .padding(.horizontal, 22)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func exploreLink(_ title: String, symbol: String, tint: Color, kind: MediaKind) -> some View {
        NavigationLink {
            XSReferenceCatalogView(kind: kind, title: title)
        } label: {
            VStack(alignment: .leading, spacing: 23) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42, alignment: .leading)
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.43))
                }
                .foregroundStyle(.white)
            }
            .padding(16)
            .frame(width: 155, height: 127)
            .background(
                LinearGradient(colors: [tint.opacity(0.18), XSCinemaStyle.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private var liveArenaFeature: some View {
        NavigationLink {
            XSSportsLiveViewV33()
        } label: {
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 21, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.16, green: 0.13, blue: 0.20), Color(red: 0.09, green: 0.18, blue: 0.20)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sportscourt.fill")
                    .font(.system(size: 90, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.09))
                    .padding(.trailing, -5)
                    .clipped()

                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 7) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text("THE LIVE ARENA")
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(2)
                                .foregroundStyle(XSCinemaStyle.warm)
                        }
                        Text("Your front row to sport.")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Explore live sports channels")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.63))
                    }
                    Spacer(minLength: 10)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .padding(19)
            }
            .frame(height: 131)
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
    }

    @ViewBuilder
    private var continueWatching: some View {
        if !library.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                XSCinemaHeadline(eyebrow: "PICK UP WHERE YOU LEFT OFF", title: "Continue watching")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 13) {
                        ForEach(library.continueWatching, id: \.item.id) { entry in
                            NavigationLink {
                                FrameXTVPlayerScreen(
                                    item: entry.item,
                                    playback: FrameXTVPlayback(
                                        tmdbID: entry.item.tmdbID,
                                        season: entry.season,
                                        episode: entry.episode,
                                        startAt: entry.currentTime
                                    )
                                )
                            } label: {
                                VStack(alignment: .leading, spacing: 9) {
                                    ZStack(alignment: .bottomLeading) {
                                        RemotePoster(item: entry.item, backdrop: true, cornerRadius: 17)
                                            .frame(width: 248, height: 141)
                                        LinearGradient(colors: [.clear, .black.opacity(0.84)], startPoint: .center, endPoint: .bottom)
                                        VStack(alignment: .leading, spacing: 9) {
                                            HStack(spacing: 7) {
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 29))
                                                if let label = entry.episodeLabel {
                                                    Text(label)
                                                        .font(.system(size: 12, weight: .bold))
                                                }
                                                Spacer()
                                                Text("\(Int(entry.fraction * 100))%")
                                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                            }
                                            .foregroundStyle(.white)
                                            ProgressView(value: entry.fraction)
                                                .tint(XSCinemaStyle.accent)
                                                .progressViewStyle(.linear)
                                        }
                                        .padding(12)
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                                    Text(entry.item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .lineLimit(1)
                                        .frame(width: 248, alignment: .leading)
                                }
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func cinemaRail(_ title: String, overline: String, items: [MediaItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 17) {
                XSCinemaHeadline(eyebrow: overline, title: title)
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 13) {
                        ForEach(Array(items.prefix(16))) { item in
                            NavigationLink(value: item) {
                                XSCinemaPosterTile(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 7)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var editorialFeature: some View {
        if let item = app.popularTV.first ?? app.popularMovies.first {
            VStack(alignment: .leading, spacing: 13) {
                XSCinemaHeadline(eyebrow: "THE EDITORIAL PICK", title: "Worth your time")
                NavigationLink(value: item) {
                    ZStack(alignment: .bottomLeading) {
                        RemotePoster(item: item, backdrop: true, cornerRadius: 22)
                            .frame(height: 230)
                        LinearGradient(colors: [.clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("A STORY TO GET LOST IN")
                                .font(.system(size: 10, weight: .black))
                                .tracking(2.3)
                                .foregroundStyle(XSCinemaStyle.warm)
                            Text(item.title)
                                .font(.system(size: 25, weight: .bold, design: .rounded))
                                .lineLimit(2)
                            Label("Discover title", systemImage: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.78))
                        }
                        .foregroundStyle(.white)
                        .padding(20)
                    }
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
            }
        }
    }
}

struct XSCinemaHeadline: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
                .tracking(2.25)
                .foregroundStyle(XSCinemaStyle.accent)
            Text(title)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .tracking(-0.55)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 22)
    }
}

struct XSCinemaPosterTile: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: item, cornerRadius: 16)
                    .frame(width: 146, height: 219)
                LinearGradient(colors: [.clear, .black.opacity(0.48)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if item.voteAverage > 0 {
                    Label(item.ratingText, systemImage: "star.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(XSCinemaStyle.warm)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.77), in: Capsule())
                        .padding(9)
                }
            }
            .frame(width: 146, height: 219)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12)))
            Text(item.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 146, alignment: .leading)
            Text("\(item.year)  •  \(item.kind == .tv ? "Series" : "Film")")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(XSCinemaStyle.secondary)
                .frame(width: 146, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
