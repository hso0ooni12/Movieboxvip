import Foundation
import Security
import CryptoKit

struct IPTVCredentials: Codable, Equatable {
    var host: String
    var username: String
    var password: String

    var normalizedHost: String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        if !value.lowercased().hasPrefix("http://") && !value.lowercased().hasPrefix("https://") {
            value = "http://" + value
        }
        return value
    }

    // A change in server, user or password invalidates cached channel data,
    // without persisting any login fields into the cache key.
    var fingerprint: String {
        let source = "\(normalizedHost.lowercased())\u{001F}\(username)\u{001F}\(password)"
        return SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var alternateHosts: [String] {
        // Public provider endpoints only; credentials are never added to source.
        let primary = normalizedHost
        let providerHosts = [
            "http://vpn.liondnscloud.ru:80",
            "http://line.goalozne.store:80"
        ]
        let isKnownProvider = providerHosts.contains { $0.lowercased() == primary.lowercased() }
        return isKnownProvider ? [primary] + providerHosts.filter { $0.lowercased() != primary.lowercased() } : [primary]
    }

    var isComplete: Bool {
        !normalizedHost.isEmpty && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
}

struct IPTVCategory: Identifiable, Hashable, Codable {
    let categoryID: String
    let categoryName: String
    let parentID: Int?

    var id: String { categoryID }

    enum CodingKeys: String, CodingKey {
        case categoryID = "category_id"
        case categoryName = "category_name"
        case parentID = "parent_id"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categoryID = c.xsString(forKey: .categoryID) ?? ""
        categoryName = c.xsString(forKey: .categoryName) ?? "Sports"
        parentID = c.xsInt(forKey: .parentID)
    }
}

struct IPTVLiveStream: Identifiable, Hashable, Codable {
    let streamID: Int
    let name: String
    let streamIcon: String?
    let categoryID: String
    let epgChannelID: String?
    let containerExtension: String?
    let added: String?

    var id: Int { streamID }

    enum CodingKeys: String, CodingKey {
        case streamID = "stream_id"
        case name
        case streamIcon = "stream_icon"
        case categoryID = "category_id"
        case epgChannelID = "epg_channel_id"
        case containerExtension = "container_extension"
        case added
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        streamID = c.xsInt(forKey: .streamID) ?? 0
        name = c.xsString(forKey: .name) ?? "Live Channel"
        streamIcon = c.xsString(forKey: .streamIcon)
        categoryID = c.xsString(forKey: .categoryID) ?? ""
        epgChannelID = c.xsString(forKey: .epgChannelID)
        containerExtension = c.xsString(forKey: .containerExtension)
        added = c.xsString(forKey: .added)
    }
}

private extension KeyedDecodingContainer {
    func xsString(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(Int(value)) }
        return nil
    }

    func xsInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key), let intValue = Int(value) { return intValue }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        return nil
    }
}

enum IPTVError: LocalizedError {
    case invalidCredentials
    case invalidServerResponse
    case noSportsChannels

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "The IPTV login details were rejected by the server."
        case .invalidServerResponse: return "The IPTV server returned an invalid response."
        case .noSportsChannels: return "No live channels were returned by this IPTV subscription. Check the server and account status."
        }
    }
}

final class IPTVCredentialVault {
    static let shared = IPTVCredentialVault()
    private let service = "com.xsstore.xstv.iptv"
    private let account = "xtream-credentials"

    private init() {}

    func save(_ credentials: IPTVCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func load() -> IPTVCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(IPTVCredentials.self, from: data)
    }

    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

actor IPTVService {
    static let shared = IPTVService()

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 11
        configuration.timeoutIntervalForResource = 22
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    // Check all provider endpoints in order. Never change the user's chosen
    // player server or send credentials to unrelated domains.
    func validate(_ credentials: IPTVCredentials) async throws {
        var lastError: Error = IPTVError.invalidServerResponse
        for host in credentials.alternateHosts {
            var candidate = credentials
            candidate.host = host
            do {
                let data = try await request(credentials: candidate, action: nil)
                guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let userInfo = object["user_info"] as? [String: Any] else {
                    throw IPTVError.invalidServerResponse
                }
                let auth: Bool
                if let value = userInfo["auth"] as? Int { auth = value == 1 }
                else if let value = userInfo["auth"] as? String { auth = value == "1" || value.lowercased() == "true" }
                else if let value = userInfo["auth"] as? Bool { auth = value }
                else { auth = false }
                guard auth else { throw IPTVError.invalidCredentials }
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func loadSports(credentials: IPTVCredentials) async throws -> ([IPTVCategory], [IPTVLiveStream]) {
        let (_, categories, streams) = try await loadLiveCatalog(credentials: credentials)
        return (categories, streams)
    }

    // Categories and live streams are fetched concurrently on each candidate.
    // The successful host is passed back so stream playback uses THAT endpoint.
    func loadLiveCatalog(credentials: IPTVCredentials) async throws -> (IPTVCredentials, [IPTVCategory], [IPTVLiveStream]) {
        var lastError: Error = IPTVError.invalidServerResponse
        for host in credentials.alternateHosts {
            var candidate = credentials
            candidate.host = host
            do {
                async let categoryData = request(credentials: candidate, action: "get_live_categories")
                async let streamData = request(credentials: candidate, action: "get_live_streams")
                let (catBytes, liveBytes) = try await (categoryData, streamData)
                let decoder = JSONDecoder()
                guard let categories = try? decoder.decode([IPTVCategory].self, from: catBytes),
                      let streams = try? decoder.decode([IPTVLiveStream].self, from: liveBytes) else {
                    throw IPTVError.invalidServerResponse
                }

                let excludedIDs = Set(categories.filter { Self.isAdultChannel($0.categoryName) }.map(\.categoryID))
                let permitted = streams.filter {
                    $0.streamID > 0 && !excludedIDs.contains($0.categoryID) && !Self.isAdultChannel($0.name)
                }
                guard !permitted.isEmpty else {
                    throw IPTVError.noSportsChannels
                }

                let sportsCategories = categories.filter { Self.isSportsCategory($0.categoryName) }
                let sportsIDs = Set(sportsCategories.map(\.categoryID))
                let matched = permitted.filter { stream in
                    sportsIDs.contains(stream.categoryID) || Self.isSportsChannel(stream.name)
                }

                // The old app displayed nothing for subscriptions whose category
                // names didn't contain English sports keywords. When there are
                // real channels but no match, show the non-adult live catalog.
                if matched.isEmpty {
                    return (candidate, categories.filter { !excludedIDs.contains($0.categoryID) }, permitted)
                }

                let filteredIDs = Set(matched.map(\.categoryID))
                let visibleCategories = categories.filter { filteredIDs.contains($0.categoryID) }
                return (candidate, visibleCategories, matched)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    nonisolated func streamURL(for stream: IPTVLiveStream, credentials: IPTVCredentials) -> URL? {
        let ext = stream.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? stream.containerExtension!
            : "m3u8"
        let user = credentials.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.username
        let pass = credentials.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.password
        return URL(string: "\(credentials.normalizedHost)/live/\(user)/\(pass)/\(stream.streamID).\(ext)")
    }

    private func request(credentials: IPTVCredentials, action: String?) async throws -> Data {
        guard var components = URLComponents(string: "\(credentials.normalizedHost)/player_api.php") else {
            throw IPTVError.invalidServerResponse
        }
        var query: [URLQueryItem] = [
            URLQueryItem(name: "username", value: credentials.username),
            URLQueryItem(name: "password", value: credentials.password)
        ]
        if let action { query.append(URLQueryItem(name: "action", value: action)) }
        components.queryItems = query
        guard let url = components.url else { throw IPTVError.invalidServerResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("XS-TV/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
            throw IPTVError.invalidServerResponse
        }
        return data
    }

    private static func isAdultChannel(_ raw: String) -> Bool {
        let value = normalized(raw)
        return ["adult", "xxx", "18+", "porn", "erotic", "sex channel", "للكبار", "إباحي"].contains { value.contains($0) }
    }

    private static func isSportsCategory(_ raw: String) -> Bool {
        let value = normalized(raw)
        let keywords = [
            "sport", "sports", "football", "soccer", "bein", "dazn", "espn", "sky sports", "ssc", "match", "arena",
            "رياض", "رياضي", "رياضة", "كورة", "كرة", "مباريات", "الدوري", "دوري"
        ]
        return keywords.contains { value.contains($0) }
    }

    private static func isSportsChannel(_ raw: String) -> Bool {
        let value = normalized(raw)
        let keywords = [
            "bein sport", "bein sports", "bein", "sport", "espn", "dazn", "sky sport", "ssc", "ad sport",
            "dubai sport", "riyadiya", "رياض", "رياضي", "كورة", "مباراة"
        ]
        return keywords.contains { value.contains($0) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}

@MainActor
final class IPTVSportsStore: ObservableObject {
    @Published var categories: [IPTVCategory] = []
    @Published var streams: [IPTVLiveStream] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var credentials: IPTVCredentials?

    private let service = IPTVService.shared
    private let vault = IPTVCredentialVault.shared
    private let cacheKey = "xs.iptv.liveCatalog.v5"

    private struct CatalogCache: Codable {
        let credentialSignature: String
        let savedAt: Date
        let categories: [IPTVCategory]
        let streams: [IPTVLiveStream]
    }

    private func restoreCache(for credentials: IPTVCredentials) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(CatalogCache.self, from: data),
              cached.credentialSignature == credentials.fingerprint,
              Date().timeIntervalSince(cached.savedAt) < 3600 else { return }
        categories = cached.categories
        streams = cached.streams
    }

    private func persistCache(for credentials: IPTVCredentials) {
        let entry = CatalogCache(
            credentialSignature: credentials.fingerprint,
            savedAt: Date(),
            categories: categories,
            streams: streams
        )
        if let data = try? JSONEncoder().encode(entry) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    var usesEmbeddedCredentials: Bool {
        XSIPTVEmbeddedConfig.isConfigured && XSIPTVEmbeddedConfig.credentials != nil
    }

    init() {
        if let embedded = XSIPTVEmbeddedConfig.credentials {
            credentials = embedded
            try? vault.save(embedded)
        } else {
            credentials = vault.load()
        }
        if let credentials { restoreCache(for: credentials) }
    }

    func save(credentials: IPTVCredentials) async throws {
        try await service.validate(credentials)
        try vault.save(credentials)
        self.credentials = credentials
        categories = []
        streams = []
        try await refresh()
    }

    func disconnect() {
        vault.clear()
        categories = []
        streams = []
        errorMessage = nil
        UserDefaults.standard.removeObject(forKey: cacheKey)
        if let embedded = XSIPTVEmbeddedConfig.credentials {
            credentials = embedded
            try? vault.save(embedded)
        } else {
            credentials = nil
        }
    }

    func refresh() async throws {
        guard let original = credentials else { throw IPTVError.invalidCredentials }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (resolved, resultCategories, resultStreams) =
                try await service.loadLiveCatalog(credentials: original)
            // Do not overwrite a newer account when a prior refresh finishes.
            guard credentials == original else { return }
            credentials = resolved
            categories = resultCategories
            streams = resultStreams
            // Key cached listings by the configured account, not the chosen
            // fallback endpoint, so relaunch displays them instantly.
            persistCache(for: original)
            try? vault.save(resolved)
        } catch {
            // Cached channels remain visible during temporary server outages.
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func streamURL(for stream: IPTVLiveStream) -> URL? {
        guard let credentials else { return nil }
        return service.streamURL(for: stream, credentials: credentials)
    }
}
