import Foundation

/// Reads data serialized by the supplied Next.js page. Does not execute page scripts.
struct FlightDocument {
    private(set) var records: [(String, Any)] = []
    private var values: [String: Any] = [:]

    init(_ text: String) {
        let bytes = Array(text.utf8)
        var cursor = 0
        while cursor < bytes.count {
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 10, bytes[cursor] != 58 { cursor += 1 }
            guard cursor < bytes.count, bytes[cursor] == 58 else {
                while cursor < bytes.count, bytes[cursor] != 10 { cursor += 1 }; cursor += 1; continue
            }
            let key = String(decoding: bytes[start..<cursor], as: UTF8.self)
            cursor += 1
            guard !key.isEmpty, key.allSatisfy({ $0.isHexDigit }) else {
                while cursor < bytes.count, bytes[cursor] != 10 { cursor += 1 }; cursor += 1; continue
            }
            let valueStart = cursor
            if cursor < bytes.count, bytes[cursor] == 84 {
                cursor += 1
                let sizeStart = cursor
                while cursor < bytes.count, bytes[cursor] != 44, bytes[cursor] != 10 { cursor += 1 }
                if cursor < bytes.count, bytes[cursor] == 44,
                   let length = Int(String(decoding: bytes[sizeStart..<cursor], as: UTF8.self), radix: 16),
                   length >= 0, length <= bytes.count - cursor - 1 {
                    cursor += 1
                    let value = String(decoding: bytes[cursor..<(cursor + length)], as: UTF8.self)
                    add(key, value); cursor += length
                    if cursor < bytes.count, bytes[cursor] == 10 { cursor += 1 }
                    continue
                }
                cursor = valueStart
            }
            while cursor < bytes.count, bytes[cursor] != 10 { cursor += 1 }
            let data = Data(bytes[valueStart..<cursor])
            if let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                add(key, value)
            }
            cursor += 1
        }
    }

    private mutating func add(_ key: String, _ value: Any) {
        records.append((key, value)); values[key] = value
    }

    func resolve(_ value: Any) -> Any {
        guard let string = value as? String, string.hasPrefix("$"), !string.hasPrefix("$$") else { return value }
        var key = String(string.dropFirst())
        if key.hasPrefix("L") || key.hasPrefix("@") { key.removeFirst() }
        return values[key] ?? value
    }

    func dictionaries() -> [[String: Any]] {
        var result: [[String: Any]] = []
        var seen = Set<String>()
        func visit(_ value: Any, depth: Int) {
            guard depth < 64 else { return }
            if let reference = value as? String, reference.hasPrefix("$") {
                guard seen.insert(reference).inserted else { return }
                let resolved = resolve(value)
                if resolved is [Any] || resolved is [String: Any] { visit(resolved, depth: depth + 1) }
            } else if let dict = value as? [String: Any] {
                result.append(dict)
                for key in dict.keys.sorted() { if let child = dict[key] { visit(child, depth: depth + 1) } }
            } else if let array = value as? [Any] {
                for child in array { visit(child, depth: depth + 1) }
            }
        }
        for (_, value) in records { visit(value, depth: 0) }
        return result
    }

    func home() throws -> HomeSnapshot {
        var featured: [MediaTitle] = []
        var rails: [MediaRail] = []
        var providers: [ProviderOption] = []
        var seenRail = Set<String>()
        for props in dictionaries() {
            if let options = props["providers"] as? [[String: Any]] {
                providers = options.compactMap { value in
                    guard let id = value["id"] as? String, let label = value["label"] as? String else { return nil }
                    return ProviderOption(id: id, label: label)
                }
            }
            let raw = resolve(props["items"] ?? props["initialItems"] ?? NSNull())
            guard let entries = raw as? [[String: Any]] else { continue }
            let kind = (props["mediaType"] as? String).flatMap(MediaKind.init(rawValue:))
            let items = entries.compactMap { MediaTitle(site: $0, kind: kind) }
            guard !items.isEmpty else { continue }
            let title: String?
            if let name = props["title"] as? String, !name.hasPrefix("$") { title = name }
            else if let provider = props["defaultProviderId"] as? String,
                    let option = providers.first(where: { $0.id == provider }) { title = "On \(option.label)" }
            else { title = nil }
            if let title {
                let key = title + ":" + items.map(\.id).joined(separator: ",")
                if seenRail.insert(key).inserted { rails.append(MediaRail(id: title, title: title, items: items)) }
            } else if featured.isEmpty { featured = items }
        }
        guard !featured.isEmpty || !rails.isEmpty else { throw WatchedError.malformed }
        return HomeSnapshot(featured: featured, rails: rails, providers: providers, capturedAt: nil)
    }

    func catalog(kind: MediaKind) throws -> CatalogPage {
        for value in dictionaries() {
            let page = resolve(value["initialPage"] ?? NSNull()) as? [String: Any] ?? value
            guard let raw = page["results"] as? [[String: Any]], let number = page["page"] as? Int else { continue }
            return CatalogPage(items: raw.compactMap { MediaTitle(site: $0, kind: kind) }, page: number,
                               totalPages: min(500, page["total_pages"] as? Int ?? number))
        }
        throw WatchedError.malformed
    }

    func detail(fallback: MediaTitle) throws -> TitleDetails {
        for props in dictionaries() {
            // The inspected browse component receives {item, activeSeason}. Its item uses the site's normalized fields.
            if let value = props["item"] as? [String: Any],
               let title = MediaTitle(site: value, kind: fallback.kind), title.tmdbID == fallback.tmdbID {
                let seasons = (value["seasons"] as? [[String: Any]] ?? []).compactMap { raw -> ShowSeason? in
                    guard let number = raw["number"] as? Int, number >= 0 else { return nil }
                    let episodes = (raw["episodes"] as? [[String: Any]] ?? []).compactMap { episode -> MediaEpisode? in
                        guard let id = episode["id"] as? Int, let episodeNumber = episode["number"] as? Int,
                              let name = episode["name"] as? String else { return nil }
                        return MediaEpisode(id: id, name: name, episode_number: episodeNumber,
                                            still_path: episode["still"] as? String, overview: episode["overview"] as? String)
                    }
                    return ShowSeason(number: number, name: raw["name"] as? String ?? "", episodeCount: raw["episodeCount"] as? Int ?? episodes.count, episodes: episodes)
                }
                return TitleDetails(title: title, seasons: seasons, activeSeason: props["activeSeason"] as? Int)
            }
        }
        throw WatchedError.malformed
    }

    /// The watch route, unlike the browse route, serializes its initial stream alongside a progress target.
    /// Match the exact title/episode and honor the server's clearance flag before accepting a stream.
    func playback(title: MediaTitle, origin: URL, season: Int?, episode: Int?, resumeAt: Double) throws -> PlaybackDescriptor {
        for props in dictionaries() {
            guard let progress = resolve(props["progress"] ?? NSNull()) as? [String: Any],
                  progress["tmdbId"] as? Int == title.tmdbID,
                  progress["mediaType"] as? String == title.kind.rawValue else { continue }
            if title.kind == .tv {
                guard progress["season"] as? Int == season, progress["episode"] as? Int == episode else { continue }
            }
            if props["cleared"] as? Bool == false { throw WatchedError.verificationRequired }
            guard let stream = resolve(props["stream"] ?? NSNull()) as? [String: Any] else { continue }
            guard stream["placeholder"] as? Bool != true else { throw WatchedError.unavailable }
            return try VODResponseDecoder.descriptor(stream, title: title, origin: origin, season: season, episode: episode, resumeAt: resumeAt)
        }
        throw WatchedError.malformed
    }
}

enum HTMLFlightDecoder {
    static func document(fromHTML html: String) throws -> FlightDocument {
        let pattern = #"self\.__next_f\.push\(\[1,("(?:\\.|[^"\\])*")\]\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let string = html as NSString
        var flight = ""
        for match in regex.matches(in: html, range: NSRange(location: 0, length: string.length)) {
            let literal = string.substring(with: match.range(at: 1))
            guard let data = "[\(literal)]".data(using: .utf8),
                  let values = try? JSONSerialization.jsonObject(with: data) as? [String], let value = values.first else { continue }
            flight += value
        }
        guard !flight.isEmpty else { throw WatchedError.malformed }
        return FlightDocument(flight)
    }
}
