import Foundation

struct M3UParser {
    func parse(_ text: String) -> [PlaylistItem] {
        let lines = text.components(separatedBy: .newlines)
        var items: [PlaylistItem] = []
        var metadata: String?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXTINF:") {
                metadata = line
                continue
            }

            guard !line.hasPrefix("#"), let url = URL(string: line), let meta = metadata else { continue }

            let name = extractName(from: meta)
            let logo = extractAttribute("tvg-logo", from: meta).flatMap(URL.init(string:))
            let group = extractAttribute("group-title", from: meta) ?? "Other"
            let kind = classify(group: group, name: name)

            items.append(PlaylistItem(name: name, streamURL: url, logoURL: logo, group: group, kind: kind))
            metadata = nil
        }

        return items
    }

    private func extractName(from metadata: String) -> String {
        guard let comma = metadata.lastIndex(of: ",") else { return "Untitled" }
        return String(metadata[metadata.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
    }

    private func extractAttribute(_ key: String, from metadata: String) -> String? {
        let token = key + "=\""
        guard let start = metadata.range(of: token)?.upperBound,
              let end = metadata[start...].firstIndex(of: "\"") else { return nil }
        return String(metadata[start..<end])
    }

    private func classify(group: String, name: String) -> PlaylistMediaKind {
        let value = (group + " " + name).lowercased()
        if value.contains("series") || value.contains("season") || value.contains("episode") { return .series }
        if value.contains("movie") || value.contains("vod") || value.contains("film") { return .movie }
        return .live
    }
}
