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
                .refreshable { await app.loadHome(force: true) }
            }
        }
        .toolbarBackground(XSCinemaStyle.background.opacity(0.92), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { XSWordmark(compact: true) }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink { MyListView() } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("My List")
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
        }
        .navigationDestination(for: MediaItem.self) { DetailView(item: $0) }
    }

    private var cinematicHero: some View {
        let item = featuredItems[min(featuredIndex, featuredItems.count - 1)]
        return ZStack(alignment: .bottomLeading) {
            RemotePoster(item: item, backdrop: true, cornerRadius: 0)
                .frame(height: 555)
                .clipped()
                .id(item.id)
                .transition(.opacity)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.12), location: 0),
                    .init(color: .black.opacity(0.08), location: 0.26),
                    .init(color: XSCinemaStyle.background.opacity(0.45), location: 0.48),
                    .init(color: XSCinemaStyle.background.opacity(0.96), location: 0.82),
                    .init(color: XSCinemaStyle.background, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Circle().fill(XSCinemaStyle.accent).frame(width: 7, height: 7)
                    Text("TONIGHT'S FEATURE")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(.white.opacity(0.95))
                }

                Text(item.title)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .tracking(-1.1)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 20, y: 3)

                HStack(spacing: 10) {
                    Text(item.year)
                    Circle().frame(width: 3, height: 3)
                    Text(item.kind == .tv ? "SERIES" : "MOVIE")
                    if item.voteAverage > 0 {
                        Circle().frame(width: 3, height: 3)
                        Image(systemName: "star.fill").foregroundStyle(XSCinemaStyle.warm)
                        Text(item.ratingText)
                    }
                }
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.83))

                if !item.overview.isEmpty {
                    Text(item.overview)
                        .font(.system(size: 14, weight: .regular))
                        .lineSpacing(4)
                        .lineLimit(2)
                        .foregroundStyle(.white.opacity(0.77))
                        .padding(.top, 1)
                }

                HStack(spacing: 10) {
                    NavigationLink {
                        FrameXTVPlayerScreen(item: item, playback: FrameXTVPlayback(tmdbID: item.tmdbID))
                    } label: {
                        Label("Watch now", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.black)
                            .background(.white, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    NavigationLink(value: item) {
                        Label("Explore", systemImage: "info.circle")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.18)))
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 6)

                HStack(spacing: 8) {
                    ForEach(featuredItems.indices, id: \.self) { index in
                        Button {
                            withAnimation(.easeInOut(duration: 0.28)) { featuredIndex = index }
                        } label: {
                            Capsule()
                                .fill(index == featuredIndex ? .white : .white.opacity(0.32))
                                .frame(width: index == featuredIndex ? 28 : 7, height: 5)
                                .frame(height: 22)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Feature \(index + 1)")
                    }
                    Spacer()
                    Text("\(featuredIndex + 1) / \(featuredItems.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.58))
                }
                .padding(.top, 7)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .frame(height: 555)
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
                                        Rectangle().fill(.black.opacity(0.48))
                                            .frame(height: 24)
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 11, weight: .bold))
                                            .frame(width: 29, height: 29)
                                            .foregroundStyle(.black)
                                            .background(.white, in: Circle())
                                            .padding(11)
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
