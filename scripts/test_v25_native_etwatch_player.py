"""V25 native catalog and site-owned watch player regression guards."""
from pathlib import Path
model=Path("FrameNative/Services/XSCinemaNativeSource.swift").read_text()
api=Path("FrameNative/Services/XSCinemaV25FlexibleCatalog.swift").read_text()
ui=Path("FrameNative/Views/XSCinemaNativeExperience.swift").read_text()
player=Path("FrameNative/Views/XSCinemaV25SitePlayerView.swift").read_text()
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
proj=Path("project-native.yml").read_text()
checks={
 "Source parsed flexibly per title": "JSONSerialization.jsonObject" in api
        and "compactMap { media" in api
        and "moviedb_id" in api,
 "Cinemeta catalog sources real": "/catalog/" in api and "/meta/" in api
        and "v3-cinemeta.strem.io" in api,
 "Robust new store actually used": "XSCinemaV25FlexibleCatalog.shared.catalog" in model
        and "XSCinemaCatalogAPI.shared.catalog(" not in model.split("final class XSCinemaNativeStore")[1],
 "No blocking public domain fetch in first paint": "async let c" not in model.split("func boot(force")[1].split("func more(")[0]
        and "Task { [weak self] in" in model,
 "Offline cache for both catalog types": "UserDefaults.standard.data(forKey:" in model
        and "persist(values, key: movieCache)" in model
        and "persist(values, key: seriesCache)" in model,
 "No forced site webview on home": "XSCinemaNativeHomeView()" in root
        and "XSCinemaNativeBrowseView(kind:.series)" in root
        and "XSSportsLiveViewV33()" in root
        and "XSETWatchPortalView" not in root,
 "Direct watch route from real TMDB ID": "watch/movie/" in player
        and "watch/tv/" in player
        and "tmdbID > 0" in player,
 "Player uses site WebKit, not extracted media": "WKWebView" in player
        and "websiteDataStore = .default()" in player
        and "iframe" not in player
        and "m3u8" not in player
        and "get_vod_streams" not in player,
 "Movie playback uses separate full-screen viewer": "if let tmdb = item.tmdbID" in ui
        and "XSCinemaV25SitePlayerView(selection:chosen)" in ui,
 "Series episodes use the actual season number": "season:ep.season,episode:ep.number" in ui,
 "Search uses flexible API not old fragile decoder": "XSCinemaV25FlexibleCatalog.shared.search" in ui
        and "XSCinemaCatalogAPI.shared.search" not in ui,
 "Real error and browser fallback": "تعذر فتح صفحة المشاهدة" in player
        and "جرب في Safari" in player,
 "Sports IPTV separate": "XSSportsLiveViewV33()" in root
        and "get_vod_streams" not in player+ui,
 "Original whole-site view excluded": "- Views/XSETWatchPortalView.swift" in proj,
}
for name,valid in checks.items():
    if not valid:
        raise SystemExit("V25 integration FAILED: "+name)
print("V25 native catalog + direct website watch player + Sports guard tests PASS:",len(checks))
