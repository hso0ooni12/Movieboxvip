import Foundation

// Media selection shared by the source-neutral V21 premium VLC player.
// No Xtream account or IPTV provider is involved.
struct XSVODPlaybackSelection: Identifiable {
    let url: URL
    let title: String
    let fallbackURL: URL?
    var id: String { url.absoluteString }
}
