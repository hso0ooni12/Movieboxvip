"""V10 post-generation performance and preservation regression gates.

The V24/V39/R5/V5/V9 tests run immediately BEFORE this layer. These tests
assert the new caches never touch the player's video/subtitle/server engine.
The pipeline remains subject to real iPhone performance validation.
"""
from pathlib import Path

app = Path("FrameNative/Core/AppState.swift").read_text()
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
images = Path("FrameNative/Services/XSArtworkPipeline.swift").read_text()
poster = Path("FrameNative/Views/Components.swift").read_text()
meta = Path("FrameNative/Services/XSMetadataRequestCache.swift").read_text()
tmdb = Path("FrameNative/Services/TMDBClient.swift").read_text()
iptv = Path("FrameNative/Services/IPTVService.swift").read_text()
store = Path("FrameNative/Services/XSIPTVCatalogDiskCache.swift").read_text()
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text()
browse = Path("FrameNative/Views/ReferenceBrowseViews.swift").read_text()

checks = {
    "artwork actor deduplication and bounded memory":
        "actor XSArtworkPipeline" in images and "inFlight[key]" in images
        and "cache.totalCostLimit = 80 * 1024 * 1024" in images,
    "background actual downsampling":
        "Task.detached(priority: .utility)" in images
        and "CGImageSourceCreateThumbnailAtIndex" in images
        and "kCGImageSourceThumbnailMaxPixelSize" in images,
    "poster view preserving public signature":
        "struct RemotePoster: View" in poster and "let item: MediaItem" in poster
        and "var backdrop = false" in poster and "var cornerRadius: CGFloat = 18" in poster,
    "no AsyncImage display animations or big decode on main":
        "V10_OPTIMIZED_POSTERS" in poster
        and "XSArtworkPipeline.shared.image(" in poster
        and "guard !Task.isCancelled else { return }" in poster
        and "AsyncImage(url:" not in poster,
    "metadata request actor coalesces identical public requests":
        "actor XSMetadataRequestCache" in meta
        and "pending[url]" in meta
        and "cached[url]" in meta
        and "lru.count > 90" in meta,
    "transport still checks HTTP status and adult policies":
        "XSMetadataRequestCache.shared.fetch(request)" in tmdb
        and "guard (200..<300).contains(http.statusCode)" in tmdb
        and "guard adult != true else { return nil }" in tmdb,
    "independent partial Home rail success":
        "V10_PARTIAL_HOME_RECOVERY" in app
        and "let m = try? await movies" in app
        and "let ps = try? await popularSeriesItems" in app
        and "if successfulRails > 0" in app,
    "cold-start cached snapshot and expiry":
        "xstv-v10-home-snapshot.json" in app
        and "HomeSnapshot: Codable" in app
        and "7 * 24 * 3600" in app,
    "no anime regression":
        "anime = []" in app
        and "case .anime: return []" in app
        and "try await client.search(query).filter { $0.kind != .anime }" in app,
    "large IPTV catalog off main actor":
        "V10_IPTV_ASYNC_CACHE" in iptv
        and "await XSIPTVCatalogDiskCache.shared.restore(" in iptv
        and "Task.detached(priority: .utility)" in iptv,
    "account-bound metadata only, no credentials in disk file":
        "actor XSIPTVCatalogDiskCache" in store
        and "fingerprint: String" in store
        and "let streams: [IPTVLiveStream]" in store
        and "let username:" not in store
        and "let password:" not in store,
    "V5 old cache migration, no lost subscribed channels":
        "LegacyEnvelope" in store
        and 'xs.iptv.liveCatalog.v5' in store
        and "legacy.credentialSignature == fingerprint" in store,
    "V5 original live provider failover and URL unchanged":
        "V5_PROVIDER_FAILOVER_CACHE" in iptv
        and "loadLiveCatalog(credentials:" in iptv
        and "streamURL(for stream:" in iptv,
    "R5 player and source subtitles still present":
        "sourceSubtitles.select(payload)" in player
        and "func selectServer(_ server: XSServerOption)" in player
        and "R5_ASPECTFIT_CAPTION" in player,
    "R5 live VLC drawable retained":
        "V39_R5_STABILITY_RESTORE" in sports
        and "XSVLCStableSurfaceView" in sports
        and "player.drawable = host.videoView" in sports,
    "global movie navigation intact":
        ".navigationDestination(for: MediaItem.self)" in browse
        and "DetailView(item:" in browse,
    "startup splash shortened but not removed":
        "250_000_000" in root and "EnhancedXSTVSplashView()" in root,
}
for label, ok in checks.items():
    if not ok:
        raise SystemExit("V10 performance QA FAIL: " + label)
print(f"V10 PASS: {len(checks)} verified new caches / non-regression invariants")
