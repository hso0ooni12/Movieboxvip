import Foundation

// Build-time IPTV configuration.
// The public repository intentionally contains no IPTV credentials.
// GitHub Actions replaces this file in the runner workspace from repository secrets
// before XcodeGen/build, so the installed app can connect automatically.
enum XSIPTVEmbeddedConfig {
    static let credentials: IPTVCredentials? = nil
    static let isConfigured = false
}
