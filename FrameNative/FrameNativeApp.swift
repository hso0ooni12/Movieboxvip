import SwiftUI
import Foundation

@main
struct XSTVApp: App {
    @StateObject private var app = AppState()
    @StateObject private var library = LibraryStore()

    init() {
        UserDefaults.standard.register(defaults: [
            "FrameNative.tmdbToken": "automatic-proxy",
            "XSTV.autoNextEpisode": true
        ])

        // Keep browsing and artwork loading smooth by using a larger shared cache.
        URLCache.shared = URLCache(
            memoryCapacity: 128 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "xstv-media-cache"
        )

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
