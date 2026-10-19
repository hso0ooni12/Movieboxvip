import Foundation

// Resolve provider 30x redirects before handing a VOD URL to VLC 4.
// URLSession.bytes(for:) returns as soon as headers arrive. We don't download
// the actual movie: no iteration over bytes, no storage, no URL logging.
// This is an optional preflight; the original Xtream URL stays available.
actor XSVODRedirectResolver {
    static let shared = XSVODRedirectResolver()

    func resolve(_ original: URL) async -> URL {
        var request = URLRequest(url: original,
                                 cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 9)
        request.setValue("bytes=0-1023", forHTTPHeaderField: "Range")
        request.setValue("XS-TV/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("video/*,*/*", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return original }
            // Signed CDN URLs may be short-lived; re-resolve every time user
            // presses Play instead of persisting final URLs.
            return response.url ?? original
        } catch {
            return original
        }
    }
}
