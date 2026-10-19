import Foundation

// V8: discoverable categories are REAL metadata queries (TMDB proxy).
// Service-specific rows indicate provider catalog metadata in US region,
// not a promise that a film or show is playable on that platform.
struct XSCatalogPage {
    let items: [MediaItem]
    let hasMore: Bool
    let notice: String?

    init(items: [MediaItem], hasMore: Bool, notice: String? = nil) {
        self.items = items
        self.hasMore = hasMore
        self.notice = notice
    }
}

struct XSCatalogCollection: Identifiable, Hashable {
    enum Category: Hashable {
        case discover, trending, popular, topRated, new
        case genre(Int)
        case provider(Int)
    }

    let id: String
    let title: String
    let symbol: String
    let category: Category

    var isProvider: Bool {
        if case .provider = category { return true }
        return false
    }

    private static func item(_ id: String, _ title: String, _ icon: String, _ kind: Category) -> XSCatalogCollection {
        XSCatalogCollection(id: id, title: title, symbol: icon, category: kind)
    }

    static func all(for kind: MediaKind) -> [XSCatalogCollection] {
        let movie = kind == .movie
        let standard: [XSCatalogCollection] = [
            item("discover", movie ? "كل الأفلام" : "كل المسلسلات", "square.grid.2x2.fill", .discover),
            item("trending", "الرائجة", "flame.fill", .trending),
            item("popular", "الأكثر شعبية", "star.fill", .popular),
            item("top", "الأعلى تقييماً", "trophy.fill", .topRated),
            item("new", movie ? "الجديدة" : "تُعرض الآن", "sparkles", .new)
        ]
        // Provider IDs are TMDB watch-provider identifiers (not custom fake
        // collections). The TMDB query sets watch_region=US for consistent
        // discovery across supported services.
        let providers: [XSCatalogCollection] = [
            item("provider-8", "Netflix", "play.rectangle.fill", .provider(8)),
            item("provider-350", "Apple TV+", "appletv.fill", .provider(350)),
            item("provider-9", "Prime Video", "play.rectangle", .provider(9)),
            item("provider-337", "Disney+", "sparkles.tv", .provider(337)),
            item("provider-1899", "Max", "tv", .provider(1899)),
            item("provider-15", "Hulu", "play.tv", .provider(15)),
            item("provider-531", "Paramount+", "star.circle", .provider(531)),
            item("provider-386", "Peacock", "tv.circle", .provider(386)),
            item("provider-1715", "Shahid", "play.square", .provider(1715)),
            item("provider-283", "Crunchyroll", "sparkles.rectangle.stack", .provider(283))
        ]

        let genres: [(Int, String, String)] = movie ? [
            (28, "أكشن", "bolt.fill"),
            (12, "مغامرات", "figure.hiking"),
            (35, "كوميديا", "face.smiling"),
            (80, "جريمة", "magnifyingglass"),
            (9648, "غموض", "eye"),
            (53, "إثارة وتشويق", "flame"),
            (27, "رعب", "moon.stars.fill"),
            (878, "خيال علمي", "sparkles"),
            (14, "فانتازيا", "wand.and.stars"),
            (18, "دراما", "theatermasks.fill"),
            (10749, "رومانسي", "heart.fill"),
            (16, "أنيميشن", "pencil.and.outline"),
            (10751, "عائلي", "person.3"),
            (99, "وثائقي", "doc.text.fill"),
            (36, "تاريخي", "building.columns"),
            (10752, "حرب", "shield"),
            (10402, "موسيقي", "music.note"),
            (37, "ويسترن", "sun.max"),
            (10770, "أفلام تلفزيونية", "tv")
        ] : [
            (10759, "أكشن ومغامرات", "bolt.fill"),
            (80, "جريمة", "magnifyingglass"),
            (9648, "غموض ورعب", "moon.stars.fill"),
            (10765, "خيال علمي وفانتازيا", "sparkles"),
            (35, "كوميديا", "face.smiling"),
            (18, "دراما", "theatermasks.fill"),
            (16, "أنيميشن", "pencil.and.outline"),
            (99, "وثائقي", "doc.text.fill"),
            (10751, "عائلي", "person.3"),
            (10762, "أطفال", "figure.and.child.holdinghands"),
            (10764, "برامج واقعية", "person.crop.rectangle.stack"),
            (10768, "حرب وسياسة", "shield"),
            (10766, "مسلسلات طويلة", "rectangle.stack"),
            (10763, "أخبار", "newspaper"),
            (10767, "برامج حوارية", "bubble.left.and.bubble.right")
        ]

        return standard + providers + genres.map {
            item("genre-\($0.0)", $0.1, $0.2, .genre($0.0))
        }
    }
}
