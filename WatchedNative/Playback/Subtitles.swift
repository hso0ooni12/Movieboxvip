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
}

struct ExternalSubtitle: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let language: String
    let url: URL
}

/// Populated only by the verified site's playback adapter once the watch-page archive is supplied.
/// The homepage archive contains no movie stream URL or playback response schema.
struct PlaybackDescriptor: Identifiable, Sendable {
    let id: String
    let title: MediaTitle
    let sources: [VideoSource]
    let subtitles: [ExternalSubtitle]
    var resumeAt: Double = 0
    var season: Int?
    var episode: Int?
}
