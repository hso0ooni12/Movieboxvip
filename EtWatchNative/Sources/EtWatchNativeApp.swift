import SwiftUI

@main
struct EtWatchNativeApp: App {
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
    static let base = Color(red: 0.035, green: 0.055, blue: 0.075)
    static let elevated = Color(red: 0.09, green: 0.12, blue: 0.15)
    static let accent = Color(red: 0.18, green: 0.83, blue: 0.75)
    static let secondary = Color(red: 0.67, green: 0.73, blue: 0.75)
}

enum MainSection: Int, CaseIterable {
    case movies, series, football

    var name: String {
        switch self {
        case .movies: "الأفلام"
        case .series: "المسلسلات"
        case .football: "المباريات"
        }
    }

    var symbol: String {
        switch self {
        case .movies: "film.stack"
        case .series: "tv"
        case .football: "sportscourt"
        }
    }
}

struct PlayerSelection: Identifiable {
    let id = UUID()
    let title: String
    let entry: PlaybackEntry
}
