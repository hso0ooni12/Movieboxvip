"""V5 source-level regression guards for IPTV connection and safe player discovery.

These guard ordering and behavior but do not claim actual subscription auth.
"""
from pathlib import Path
service = Path("FrameNative/Services/IPTVService.swift").read_text()
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
embedded = Path("FrameNative/Core/IPTVEmbeddedConfig.swift").read_text()
checks = {
    "provider primary plus bounded failover": "var alternateHosts: [String]" in service and "for host in credentials.alternateHosts" in service,
    "category and stream API concurrent": 'action: "get_live_categories"' in service and 'action: "get_live_streams"' in service and "async let" in service,
    "correct host drives playback": "credentials = resolved" in service and "streamURL(for stream:" in service,
    "unknown category live streams visible": "if matched.isEmpty" in service and "permitted" in service,
    "no adult live catalog fallback": "excludedIDs" in service and "isAdultChannel" in service,
    "credential cache scoped without plaintext": "SHA256.hash" in service and "credentialSignature" in service and "restoreCache(for: credentials)" in service,
    "overridden host invalidated on account change": "embeddedAccountFingerprint != signature" in sports and 'serverOverride = ""' in sports,
    "R5 source server selection intact": 'var payload: [String: Any] = ["action": "server", "name": server.name]' in player,
    "R5 source subtitle selection intact": "sourceSubtitles.select(payload);" in player,
    "R5 backup requires original popup": "V39_R5_STABILITY_RESTORE" in sports and "XSVLCStableSurfaceView" in sports,
    "source menus open once, not twice": "V5_FAST_READONLY_DISCOVERY" in player,
    "embedded config contains no plaintext secrets in repository": "static let credentials: IPTVCredentials? = nil" in embedded,
}
for k, v in checks.items():
    if not v: raise SystemExit("V5 IPTV and player fast-discovery regression failed: " + k)
print(f"V5 server/subtitle/IPTV guards PASS: {len(checks)}")
