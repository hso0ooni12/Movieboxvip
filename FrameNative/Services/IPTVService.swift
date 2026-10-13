import Foundation
import Security

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

    var isComplete: Bool {
        !normalizedHost.isEmpty && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
}

struct IPTVCategory: Identifiable, Hashable, Decodable {
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

struct IPTVLiveStream: Identifiable, Hashable, Decodable {
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
        case .noSportsChannels: return "No sports channels were found in this subscription."
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
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    func validate(_ credentials: IPTVCredentials) async throws {
        let data = try await request(credentials: credentials, action: nil)
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
    }

    func loadSports(credentials: IPTVCredentials) async throws -> ([IPTVCategory], [IPTVLiveStream]) {
        async let categoriesData = request(credentials: credentials, action: "get_live_categories")
        async let streamsData = request(credentials: credentials, action: "get_live_streams")

        let (categoryBytes, streamBytes) = try await (categoriesData, streamsData)
        let decoder = JSONDecoder()
        let categories = (try? decoder.decode([IPTVCategory].self, from: categoryBytes)) ?? []
        let streams = (try? decoder.decode([IPTVLiveStream].self, from: streamBytes)) ?? []

        let sportsCategories = categories.filter { Self.isSportsCategory($0.categoryName) }
        let sportsIDs = Set(sportsCategories.map(\.categoryID))
        let sportsStreams = streams.filter { stream in
            sportsIDs.contains(stream.categoryID) || Self.isSportsChannel(stream.name)
        }

        guard !sportsStreams.isEmpty else { throw IPTVError.noSportsChannels }
        return (sportsCategories, sportsStreams)
    }

    func streamURL(for stream: IPTVLiveStream, credentials: IPTVCredentials) -> URL? {
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

    private static func isSportsCategory(_ raw: String) -> Bool {
        let value = normalized(raw)
        let keywords = [
            "sport", "sports", "football", "soccer", "bein", "dazn", "espn", "sky sports",
            "رياض", "رياضي", "رياضة", "كورة", "كرة", "مباريات", "الدوري", "دوري"
        ]
        return keywords.contains { value.contains($0) }
    }

    private static func isSportsChannel(_ raw: String) -> Bool {
        let value = normalized(raw)
        let keywords = [
            "bein sport", "bein sports", "sport", "espn", "dazn", "sky sport", "ssc", "ad sport",
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

    init() {
        credentials = vault.load()
    }

    func save(credentials: IPTVCredentials) async throws {
        try await service.validate(credentials)
        try vault.save(credentials)
        self.credentials = credentials
        try await refresh()
    }

    func disconnect() {
        vault.clear()
        credentials = nil
        categories = []
        streams = []
        errorMessage = nil
    }

    func refresh() async throws {
        guard let credentials else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (categories, streams) = try await service.loadSports(credentials: credentials)
            self.categories = categories
            self.streams = streams
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    func streamURL(for stream: IPTVLiveStream) -> URL? {
        guard let credentials else { return nil }
        return service.streamURL(for: stream, credentials: credentials)
    }
}
