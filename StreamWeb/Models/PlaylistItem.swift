import Foundation

enum PlaylistMediaKind: String, Codable, CaseIterable {
    case live
    case movie
    case series
}

struct PlaylistItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let streamURL: URL
    let logoURL: URL?
    let group: String
    let kind: PlaylistMediaKind
}
