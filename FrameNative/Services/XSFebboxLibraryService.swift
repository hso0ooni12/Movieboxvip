import Foundation
import WebKit

// XS TV Febbox read-only shared-library integration (V18).
// Uses only public Febbox share links which are explicitly shared by their
// owner. No user cookie, client token, password or transient stream URL
// is shipped or saved to the IPA. We query pages lazily instead of downloading
// the media itself. Playback links may still require Febbox authorization.

enum XSFebboxShelf: String, CaseIterable, Identifiable, Sendable, Codable {
    case movies = "C2jBoH52"
    case series = "eHH8d0S1"

    var id: String { rawValue }
    var title: String { self == .movies ? "الأفلام" : "المسلسلات" }
    var symbol: String { self == .movies ? "film.stack.fill" : "tv.fill" }
    var publicSharePage: URL {
        URL(string: "https://www.febbox.com/share/\(rawValue)")!
    }
}

struct XSFebboxEntry: Identifiable, Hashable, Sendable {
    let shelf: XSFebboxShelf
    let fid: String
    let parentID: String
    let filename: String
    let isDirectory: Bool
    let fileExtension: String
    let sizeBytes: Int64
    let durationSeconds: Double
    let thumbnail: URL?

    var id: String { shelf.rawValue + "-" + fid }
    var name: String {
        if isDirectory { return filename }
        let suffix = fileExtension.isEmpty ? "" : "." + fileExtension
        return !suffix.isEmpty && filename.lowercased().hasSuffix(suffix.lowercased())
            ? String(filename.dropLast(suffix.count)) : filename
    }
    var playable: Bool {
        ["mp4","m4v","mov","mkv","avi","ts","m3u8","webm"].contains(fileExtension.lowercased())
    }
    var subtitles: Bool {
        ["srt","vtt","ass","ssa","sub"].contains(fileExtension.lowercased())
    }
    var icon: String {
        if isDirectory { return "folder.fill" }
        if playable { return "play.rectangle.fill" }
        if subtitles { return "captions.bubble.fill" }
        return "doc.fill"
    }
}

struct XSFebboxPage: Sendable {
    let entries: [XSFebboxEntry]
    let hasNext: Bool
}

struct XSFebboxQuality: Identifiable, Sendable, Hashable {
    let name: String
    let url: URL
    var id: String { url.absoluteString }
}

enum XSFebboxError: LocalizedError {
    case invalidResponse
    case unavailable(String)
    case noAuthorizedPlayback
    case signInRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "تعذر قراءة استجابة مكتبة Febbox."
        case .unavailable(let reason): return reason
        case .noAuthorizedPlayback:
            return "لم يوفّر Febbox رابط تشغيل لهذه الحلقة حتى بعد فحص صلاحيات المشاركة."
        case .signInRequired:
            return "يلزم تسجيل الدخول بحساب Febbox المصرّح له قبل تشغيل هذا الملف."
        }
    }
}

actor XSFebboxLibraryService {
    static let shared = XSFebboxLibraryService()
    private let pageSize = 50
    private var cache: [String: (fetched: Date, items: XSFebboxPage)] = [:]

    private static func scalar(_ any: Any?) -> String {
        if let string = any as? String { return string }
        if let number = any as? NSNumber { return number.stringValue }
        return ""
    }
    private static func number(_ any: Any?) -> Double {
        if let number = any as? NSNumber { return number.doubleValue }
        if let string = any as? String { return Double(string) ?? 0 }
        return 0
    }

    func page(shelf: XSFebboxShelf, parent: String = "0",
              number: Int = 1, force: Bool = false) async throws -> XSFebboxPage {
        guard parent.range(of: #"^\d+$"#, options: .regularExpression) != nil,
              (1...10000).contains(number) else {
            throw XSFebboxError.invalidResponse
        }
        let key = shelf.rawValue + ":" + parent + ":" + String(number)
        if !force, let saved = cache[key],
           Date().timeIntervalSince(saved.fetched) < 180 {
            return saved.items
        }

        var components = URLComponents(string: "https://www.febbox.com/file/file_share_list")!
        components.queryItems = [
            .init(name: "share_key", value: shelf.rawValue),
            .init(name: "pwd", value: ""),
            .init(name: "parent_id", value: parent),
            .init(name: "page", value: String(number)),
            .init(name: "is_html", value: "0")
        ]
        guard let url = components.url else { throw XSFebboxError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 22)
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; XS TV shared folder browser)", forHTTPHeaderField: "User-Agent")
        request.setValue(shelf.publicSharePage.absoluteString, forHTTPHeaderField: "Referer")

        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw XSFebboxError.invalidResponse }
        guard http.statusCode == 200 else {
            throw XSFebboxError.unavailable(http.statusCode == 401 || http.statusCode == 403
                ? "Febbox يطلب صلاحية لهذا المجلد."
                : "تعذر تحميل المجلد (HTTP \(http.statusCode)).")
        }
        guard let document = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              Self.number(document["code"]) == 1,
              let data = document["data"] as? [String: Any],
              let rows = data["file_list"] as? [[String: Any]] else {
            throw XSFebboxError.unavailable("فهرس هذا المجلد غير متاح حالياً من Febbox.")
        }

        let items: [XSFebboxEntry] = rows.compactMap { row in
            let fid = Self.scalar(row["fid"])
            guard !fid.isEmpty,
                  fid.range(of: #"^\d+$"#, options: .regularExpression) != nil else { return nil }
            let ext = Self.scalar(row["ext"]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let filename = Self.scalar(row["file_name"])
            let isDir = Self.number(row["is_dir"]) == 1
            guard !filename.isEmpty else { return nil }

            let imageFields = ["thumb_big", "thumb", "thumb_small"]
            let thumb = imageFields.compactMap { field -> URL? in
                let raw = Self.scalar(row[field])
                guard let u = URL(string: raw), u.scheme == "https" else { return nil }
                return u
            }.first

            return XSFebboxEntry(shelf: shelf, fid: fid,
                parentID: Self.scalar(row["parent_id"]),
                filename: filename, isDirectory: isDir, fileExtension: ext,
                sizeBytes: Int64(Self.number(row["file_size_bytes"])),
                durationSeconds: Self.number(row["runtime"]), thumbnail: thumb)
        }
        let result = XSFebboxPage(entries: items, hasNext: rows.count >= pageSize)
        if cache.count > 300 { cache.removeAll(keepingCapacity: true) }
        cache[key] = (Date(), result)
        return result
    }

    // A signed-in Febbox web session belongs to this app's WebKit data store.
    // Read only Febbox cookies, in memory, for a Febbox-owned endpoint.
    // Do not embed cookies in the IPA, publish them, or log their values.
    private func accountCookies() async -> [HTTPCookie] {
        let all: [HTTPCookie] = await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
        return all.filter {
            let domain = $0.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "febbox.com" || domain.hasSuffix(".febbox.com")
        }
    }

    func hasAccountSession() async -> Bool {
        await accountCookies().contains { $0.name == "ui" && !$0.value.isEmpty }
    }

    // This is an optional and read-only capability: some Febbox shared files
    // allow quality inspection anonymously; others need account permission.
    // The app must never guess private links or persist expiring CDN URLs.
    func publicVideoQualities(for item: XSFebboxEntry) async throws -> [XSFebboxQuality] {
        guard !item.isDirectory, item.playable else { return [] }
        var components = URLComponents(string: "https://www.febbox.com/console/video_quality_list")!
        components.queryItems = [.init(name: "fid", value: item.fid)]
        guard let url = components.url else { throw XSFebboxError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 18)
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(item.shelf.publicSharePage.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let cookies = await accountCookies()
        // The WebKit browser session is used only for Febbox video requests.
        // HTTPCookie builds a correctly escaped header without persisting secrets.
        for (name, value) in HTTPCookie.requestHeaderFields(with: cookies) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        let (body, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let html = object["html"] as? String, !html.isEmpty else {
            throw cookies.contains(where: { $0.name == "ui" })
                ? XSFebboxError.noAuthorizedPlayback : XSFebboxError.signInRequired
        }
        // Each .file_quality element in the original Febbox response contains
        // data-url/data-quality attributes; no alternate servers are invented.
        let blocks = html.components(separatedBy: "file_quality")
        let attribute = try NSRegularExpression(pattern: #"data-(url|quality)\s*=\s*["']([^"']+)["']"#,
                                                 options: [.caseInsensitive])
        var qualities: [XSFebboxQuality] = []
        for block in blocks.dropFirst() {
            var attrs: [String: String] = [:]
            let segment = String(block.prefix(1300))
            let range = NSRange(segment.startIndex..<segment.endIndex, in: segment)
            for match in attribute.matches(in: segment, range: range) {
                guard let k = Range(match.range(at: 1), in: segment),
                      let v = Range(match.range(at: 2), in: segment) else { continue }
                attrs[String(segment[k]).lowercased()] = String(segment[v])
            }
            guard let raw = attrs["url"]?.replacingOccurrences(of: "&amp;", with: "&"),
                  let u = URL(string: raw),
                  ["https", "http"].contains(u.scheme?.lowercased() ?? ""),
                  u.host != nil else { continue }
            qualities.append(XSFebboxQuality(name: attrs["quality"] ?? "Source", url: u))
        }
        guard !qualities.isEmpty else {
            throw cookies.contains(where: { $0.name == "ui" })
                ? XSFebboxError.noAuthorizedPlayback : XSFebboxError.signInRequired
        }
        return Array(Set(qualities)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
