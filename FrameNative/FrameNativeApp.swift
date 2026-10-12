import SwiftUI

@main
struct FrameNativeApp: App {
    @StateObject private var app = AppState()
    @StateObject private var library = LibraryStore()

    init() {
        UserDefaults.standard.register(defaults: [
            "FrameNative.tmdbToken": "automatic-proxy"
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
