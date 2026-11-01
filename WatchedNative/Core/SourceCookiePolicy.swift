import Foundation

enum SourceCookiePolicy {
    static func isFirstParty(domain: String) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == "watched.cx" || host.hasSuffix(".watched.cx")
    }
}
