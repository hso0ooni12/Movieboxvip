import Foundation

// V10_IPTV_DISK_CACHE
// The full Xtream live catalog can be thousands of rows. Encode/decode and
// atomically persist that large collection off the main UI actor.
// Only category/channel metadata is stored; NEVER the host/user/password.
actor XSIPTVCatalogDiskCache {
    static let shared = XSIPTVCatalogDiskCache()

    private struct Envelope: Codable {
        let fingerprint: String
        let savedAt: Date
        let categories: [IPTVCategory]
        let streams: [IPTVLiveStream]
    }

    private let lifetime: TimeInterval = 60 * 60

    private var cacheFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("xstv-iptv-catalog-v10.json", isDirectory: false)
    }

    func restore(fingerprint: String) -> ([IPTVCategory], [IPTVLiveStream])? {
        guard let file = cacheFile else { return nil }
        // Migrate a legitimate V5 cached snapshot, while removing the oversized
        // UserDefaults entry after success. Do not invalidate on minor upgrades.
        if !FileManager.default.fileExists(atPath: file.path),
           let old = UserDefaults.standard.data(forKey: "xs.iptv.liveCatalog.v5"),
           let legacy = try? JSONDecoder().decode(LegacyEnvelope.self, from: old),
           legacy.credentialSignature == fingerprint,
           Date().timeIntervalSince(legacy.savedAt) < lifetime {
            let snapshot = Envelope(
                fingerprint: fingerprint,
                savedAt: legacy.savedAt,
                categories: legacy.categories,
                streams: legacy.streams
            )
            if let bytes = try? JSONEncoder().encode(snapshot) {
                try? bytes.write(to: file, options: .atomic)
                UserDefaults.standard.removeObject(forKey: "xs.iptv.liveCatalog.v5")
            }
            return (snapshot.categories, snapshot.streams)
        }

        guard let data = try? Data(contentsOf: file),
              let snapshot = try? JSONDecoder().decode(Envelope.self, from: data),
              snapshot.fingerprint == fingerprint,
              Date().timeIntervalSince(snapshot.savedAt) < lifetime,
              !snapshot.streams.isEmpty else { return nil }
        return (snapshot.categories, snapshot.streams)
    }

    func persist(
        fingerprint: String,
        categories: [IPTVCategory],
        streams: [IPTVLiveStream]
    ) {
        guard let file = cacheFile, !streams.isEmpty else { return }
        let snapshot = Envelope(fingerprint: fingerprint, savedAt: Date(),
                                categories: categories, streams: streams)
        if let bytes = try? JSONEncoder().encode(snapshot) {
            try? bytes.write(to: file, options: .atomic)
            UserDefaults.standard.removeObject(forKey: "xs.iptv.liveCatalog.v5")
        }
    }

    func clear() {
        if let file = cacheFile { try? FileManager.default.removeItem(at: file) }
        UserDefaults.standard.removeObject(forKey: "xs.iptv.liveCatalog.v5")
    }

    private struct LegacyEnvelope: Codable {
        let credentialSignature: String
        let savedAt: Date
        let categories: [IPTVCategory]
        let streams: [IPTVLiveStream]
    }
}
