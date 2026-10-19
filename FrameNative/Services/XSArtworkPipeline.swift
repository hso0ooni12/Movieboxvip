import Foundation
import SwiftUI
import UIKit
import ImageIO

// V10_ARTWORK_PIPELINE
// A single actor prevents duplicate download/decode of identical posters.
// NSCache automatically drops decoded bitmaps under memory pressure;
// the caller's SwiftUI .task(id:) cancels UI assignments on recycled cells.
// The original framextv sources and video player are never touched.
actor XSArtworkPipeline {
    static let shared = XSArtworkPipeline()

    private let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 80 * 1024 * 1024
        cache.countLimit = 220
        return cache
    }()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    func image(for url: URL, maxDimension: Int) async -> UIImage? {
        let pixelBound = min(1800, max(160, maxDimension))
        // The requested CDN image-size is part of the URL. Geometry-specific
        // bounds prevent accidentally decoding an overlarge bitmap in a rail.
        let key = "\(url.absoluteString)#\(pixelBound)"
        let cacheKey = key as NSString

        if let image = cache.object(forKey: cacheKey) {
            return image
        }
        if let job = inFlight[key] {
            return await job.value
        }

        let job = Task.detached(priority: .utility) { () -> UIImage? in
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 16
                request.cachePolicy = .useProtocolCachePolicy
                let (bytes, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode),
                      !bytes.isEmpty else { return nil }
                return XSArtworkPipeline.decode(bytes, maxDimension: pixelBound)
            } catch {
                return nil
            }
        }
        inFlight[key] = job
        let image = await job.value
        inFlight[key] = nil
        if let image {
            let cost = Int(image.size.width * image.scale * image.size.height * image.scale * 4)
            cache.setObject(image, forKey: cacheKey, cost: max(1, cost))
        }
        return image
    }

    // ImageIO creates a thumbnail directly from compressed bytes, avoiding
    // the peak-memory cost of first decoding a full-resolution original.
    nonisolated private static func decode(_ bytes: Data, maxDimension: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(bytes as CFData, sourceOptions) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: thumbnail)
    }
}
