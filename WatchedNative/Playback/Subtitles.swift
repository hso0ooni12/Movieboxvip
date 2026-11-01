import Foundation

struct SubtitleCue: Equatable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

enum SubtitleParser {
    static func parse(_ source: String) -> [SubtitleCue] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = lines[index].components(separatedBy: "-->")
            guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]), end > start else { return nil }
            let raw = lines.dropFirst(index + 1).joined(separator: "\n")
            let text = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return SubtitleCue(start: start, end: end, text: text)
        }.sorted { $0.start < $1.start }
    }

    private static func timestamp(_ value: String) -> Double? {
        guard let first = value.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        let parts = first.replacingOccurrences(of: ",", with: ".").split(separator: ":").compactMap { Double($0) }
        if parts.count == 3 { return parts[0] * 3600 + parts[1] * 60 + parts[2] }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return nil
    }

    static func text(at time: Double, offset: Double, cues: [SubtitleCue]) -> String {
        let adjusted = time - offset
        var low = 0, high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].start <= adjusted { low = mid + 1 } else { high = mid }
        }
        guard low > 0 else { return "" }
        let cue = cues[low - 1]
        return adjusted < cue.end ? cue.text : ""
    }
}

struct VideoSource: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let url: URL
    var height: Int?
    var kind: String = "hls"
    var bandwidth: Double?
    var width: Int?
}

struct ExternalSubtitle: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let language: String
    let url: URL
}

struct PlaybackDescriptor: Identifiable, Sendable {
    let id: String
    let title: MediaTitle
    let sources: [VideoSource]
    let subtitles: [ExternalSubtitle]
    var resumeAt: Double = 0
    var season: Int?
    var episode: Int?
    var sessionID: String?
    var usedFallback = false
}

enum VODResponseDecoder {
    static func descriptor(_ value: [String: Any], title: MediaTitle, origin: URL, season: Int?, episode: Int?, resumeAt: Double) throws -> PlaybackDescriptor {
        let stream = value["stream"] as? [String: Any] ?? value
        let rawSources = stream["sources"] as? [[String: Any]] ?? []
        var seen = Set<URL>()
        let sources = rawSources.enumerated().compactMap { index, source -> VideoSource? in
            guard let raw = source["url"] as? String, let url = URL(string: raw, relativeTo: origin)?.absoluteURL,
                  url.scheme == "https", seen.insert(url).inserted else { return nil }
            let kind = source["kind"] as? String ?? stream["kind"] as? String ?? "hls"
            guard kind == "hls" || kind == "mp4" else { return nil }
            let label = source["quality"] as? String ?? "Auto"
            return VideoSource(id: "source-\(index)", label: label, url: url, height: source["height"] as? Int, kind: kind)
        }
        guard !sources.isEmpty else { throw WatchedError.unavailable }
        let tracks = Self.subtitles(stream, origin: origin)
        return PlaybackDescriptor(id: "\(title.id):\(season ?? 0):\(episode ?? 0)", title: title, sources: sources, subtitles: tracks,
                                  resumeAt: resumeAt, season: season, episode: episode, sessionID: stream["sessionId"] as? String)
    }

    static func subtitles(_ value: [String: Any], origin: URL) -> [ExternalSubtitle] {
        let raw = value["subtitles"] as? [[String: Any]] ?? []
        var seen = Set<URL>()
        return raw.enumerated().compactMap { index, track in
            guard let rawURL = track["url"] as? String, let url = URL(string: rawURL, relativeTo: origin)?.absoluteURL,
                  url.scheme == "https", seen.insert(url).inserted else { return nil }
            let language = track["language"] as? String ?? track["lang"] as? String ?? track["srclang"] as? String ?? "und"
            let label = track["label"] as? String ?? track["name"] as? String ?? language
            return ExternalSubtitle(id: "remote-\(index)-\(language)", label: label, language: language, url: url)
        }
    }
}

struct HLSRendition: Equatable, Sendable {
    let width: Int
    let height: Int
    let bandwidth: Double
}

enum HLSMasterParser {
    static func renditions(_ text: String) -> [HLSRendition] {
        guard text.hasPrefix("#EXTM3U") else { return [] }
        var heights = Set<Int>()
        let resolution = try? NSRegularExpression(pattern: #"(?:^|,)RESOLUTION=(\d+)x(\d+)(?:,|$)"#)
        let bandwidth = try? NSRegularExpression(pattern: #"(?:^|,)BANDWIDTH=(\d+)(?:,|$)"#)
        return text.components(separatedBy: .newlines).compactMap { line -> HLSRendition? in
            guard line.hasPrefix("#EXT-X-STREAM-INF:"), let resolution, let bandwidth else { return nil }
            let attributes = String(line.dropFirst("#EXT-X-STREAM-INF:".count)) as NSString
            let range = NSRange(location: 0, length: attributes.length)
            guard let dimensions = resolution.firstMatch(in: attributes as String, range: range),
                  let rate = bandwidth.firstMatch(in: attributes as String, range: range),
                  let width = Int(attributes.substring(with: dimensions.range(at: 1))),
                  let height = Int(attributes.substring(with: dimensions.range(at: 2))),
                  let bits = Double(attributes.substring(with: rate.range(at: 1))), height > 0, width > 0,
                  heights.insert(height).inserted else { return nil }
            return HLSRendition(width: width, height: height, bandwidth: bits)
        }.sorted { $0.height > $1.height }
    }
}
