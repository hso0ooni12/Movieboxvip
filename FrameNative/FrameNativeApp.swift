import SwiftUI

@main
struct FrameNativeApp: App {
    @StateObject private var app = AppState()
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(library)
                .preferredColorScheme(.dark)
        }
    }
}
