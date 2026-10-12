# Frame Native iOS

This branch adds a real native iPhone/iPad media-app shell built with SwiftUI + AVKit. It does not use WKWebView.

## Included

- Native Home, Search, My List and Downloads tabs.
- Native media detail screen.
- AVKit video playback with an Apple public test HLS stream in the demo provider.
- Continue-watching entry tracking.
- Persistent favorites.
- Download manager for provider-supplied authorized downloadable files.
- iOS 16+ support.
- GitHub Actions build that outputs an unsigned IPA for re-signing with your own certificate.
- A `ContentProvider` protocol so the UI can be connected to a licensed/private catalog API without rewriting the app.

## Important source boundary

The demo catalog intentionally uses sample metadata and Apple's public test stream. Do not connect the provider to scraped or unauthorized copyrighted streams, and do not use the download manager to bypass DRM or content protection.

## Build from GitHub

The workflow `.github/workflows/build-native-ipa.yml` automatically runs after changes are pushed to the `frame-native` branch. It can also be run manually after the workflow is available on the default branch.

The resulting artifact is named `frame-native-unsigned-ipa` and contains an unsigned `.ipa`. Re-sign it with your own certificate/profile before installing on iPhone.

## Connect your own API

Replace `DemoContentProvider` in `FrameNative/FrameNativeApp.swift` with a provider that conforms to:

```swift
protocol ContentProvider {
    func featured() async throws -> [MediaItem]
    func catalog() async throws -> [MediaItem]
}
```

Each `MediaItem` accepts separate `streamURL` and `downloadURL` values. Only provide URLs you are authorized to distribute/play/download.
