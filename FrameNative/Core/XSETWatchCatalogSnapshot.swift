import Foundation

struct XSCinemaShelf: Codable, Identifiable {
    let id: String
    let title: String
    let itemIDs: [String]
}
struct XSETWatchCatalogSnapshot: Codable {
    let generated: String
    let items: [XSCinemaMedia]
    let shelves: [XSCinemaShelf]
    static let bundled: XSETWatchCatalogSnapshot? = {
        guard let url = Bundle.main.url(forResource: "etwatch-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XSETWatchCatalogSnapshot.self, from: data)
    }()
}
