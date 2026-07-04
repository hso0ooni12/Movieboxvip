import SwiftUI

struct AppConfiguration: Decodable {
    let appName: String
    let homeURL: URL
    let opensExternalHostsInSafari: Bool
    let accentHex: String
    let adBlockingEnabled: Bool

    static let shared: AppConfiguration = {
        guard
            let url = Bundle.main.url(forResource: "AppConfig", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let configuration = try? JSONDecoder().decode(AppConfiguration.self, from: data)
        else {
            return AppConfiguration(
                appName: "Stream Web",
                homeURL: URL(string: "https://streamimdb.ru/")!,
                opensExternalHostsInSafari: false,
                accentHex: "#E50914",
                adBlockingEnabled: true
            )
        }

        return configuration
    }()

    var accentColor: Color {
        Color(hex: accentHex) ?? .red
    }

    func isExternal(_ url: URL) -> Bool {
        guard let homeHost = homeURL.host?.lowercased(),
              let targetHost = url.host?.lowercased() else {
            return false
        }

        return targetHost != homeHost && !targetHost.hasSuffix(".\(homeHost)")
    }
}

private extension Color {
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }

        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: 1
        )
    }
}
