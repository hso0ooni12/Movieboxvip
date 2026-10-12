import SwiftUI

@main
struct XSTVApp: App {
    @StateObject private var app = AppState()
    @StateObject private var library = LibraryStore()

    init() {
        UserDefaults.standard.register(defaults: [
            "FrameNative.tmdbToken": "automatic-proxy",
            "XSTV.autoNextEpisode": true
        ])
        XSTVPlaybackEnvironment.configure()
    }

    var body: some Scene {
        WindowGroup {
            EnhancedRootView()
                .environmentObject(app)
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
