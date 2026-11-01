import AVFoundation
import Foundation

enum NativeMediaAsset {
    static func item(url: URL) -> AVPlayerItem {
        // AVFoundation and the native HTTP client use only the user's actual, scoped source session.
        let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
        let options: [String: Any] = url.isFileURL ? [:] : [AVURLAssetHTTPCookiesKey: cookies]
        return AVPlayerItem(asset: AVURLAsset(url: url, options: options))
    }
}
