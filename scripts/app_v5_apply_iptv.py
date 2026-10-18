"""Apply V5 IPTV source only after V35/V39 legacy transforms.

V35 requires the original IPTVService.loadSports return anchors, and V39 R5
requires the unmodified SwiftUI VLC surface. Keep those scripts intact and
inject V5's credential-scoped cache / provider failover at the final stage.
No credentials live in this source, fixture, or repository.
"""
from pathlib import Path

service_path = Path("FrameNative/Services/IPTVService.swift")
fixture = Path("scripts/assets/IPTVServiceV5.swift.txt").read_text(encoding="utf-8")
sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
sports = sports_path.read_text(encoding="utf-8")

required_service = ["import CryptoKit", "loadLiveCatalog(credentials:", "restoreCachedSports()", "credentialSignature"]
for tag in required_service:
    if tag not in fixture:
        raise SystemExit("V5 IPTV injection missing source marker " + tag)

if "V39_R5_STABILITY_RESTORE" not in sports:
    raise SystemExit("V5 refuses to alter Sports screen without the stable R5 VLC drawable")

state = '    @AppStorage(xsSportsServerOverrideKey) private var serverOverride = ""'
if state not in sports:
    raise SystemExit("V5 can't find embedded server override property")
sports = sports.replace(
    state,
    state + '\n    @AppStorage("xs.iptv.embeddedAccountFingerprint.v5") private var embeddedAccountFingerprint = ""',
    1,
)

old = """    private func applyConfiguredServer() {
        guard let embedded = XSIPTVEmbeddedConfig.credentials else { return }
        let trimmed = serverOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = trimmed.isEmpty ? embedded.host : trimmed
        let next = IPTVCredentials(host: host, username: embedded.username, password: embedded.password)
        if store.credentials != next {
            store.credentials = next
            store.categories = []
            store.streams = []
            store.errorMessage = nil
        }
    }"""
new = """    private func applyConfiguredServer() {
        guard let embedded = XSIPTVEmbeddedConfig.credentials else { return }
        // After GitHub credentials change, do not keep using a host override
        // from an old subscription. Never store the password in preferences.
        let signature = embedded.fingerprint
        if embeddedAccountFingerprint != signature {
            serverOverride = ""
            embeddedAccountFingerprint = signature
        }
        let trimmed = serverOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = trimmed.isEmpty ? embedded.host : trimmed
        let next = IPTVCredentials(host: host, username: embedded.username, password: embedded.password)
        if store.credentials != next {
            store.credentials = next
            store.categories = []
            store.streams = []
            store.errorMessage = nil
        }
    }"""
if old not in sports:
    raise SystemExit("V5 cannot find stable configuration method")
sports = sports.replace(old, new, 1)

service_path.write_text("// V5_PROVIDER_FAILOVER_CACHE\n" + fixture, encoding="utf-8")
sports_path.write_text(sports, encoding="utf-8")
print("V5 IPTV installation PASS: account-scoped cache, safe alternate host, old override reset; stable VLC maintained.")
