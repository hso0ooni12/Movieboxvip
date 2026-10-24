import SwiftUI

@main
struct GemflixNativeApp: App {
    @StateObject private var store = CinemaStore()

    var body: some Scene {
        WindowGroup {
            MainScreen()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await store.start() }
        }
    }
}

enum CinemaPalette {
    static let base = Color(red: 0.039, green: 0.031, blue: 0.043)
    static let elevated = Color(red: 0.105, green: 0.077, blue: 0.10)
    static let accent = Color(red: 0.94, green: 0.25, blue: 0.35)
    static let secondary = Color(red: 0.73, green: 0.67, blue: 0.70)
}

enum MainSection: Int, CaseIterable {
    case home, movies, series, saved

    var name: String {
        switch self {
        case .home: "الرئيسية"
        case .movies: "الأفلام"
        case .series: "المسلسلات"
        case .saved: "قائمتي"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .movies: "film.stack"
        case .series: "tv"
        case .saved: "bookmark.fill"
        }
    }
}

struct PlayerSelection: Identifiable {
    let id = UUID()
    let title: String
    let entry: PlaybackEntry
}
