"""V9 catalog reliability: no blank 403, compact navigation, automatic paging.
Source-regression guards complement (but cannot replace) real-device tests.
"""
from pathlib import Path

api = Path("FrameNative/Services/TMDBClient.swift").read_text()
browse = Path("FrameNative/Views/ReferenceBrowseViews.swift").read_text()
model = Path("FrameNative/Core/XSCatalogCollection.swift").read_text()
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text()

checks = {
    "403 is recovered from for unsupported catalog routes":
        "catch APIError.http(let status, _) where status == 403 || status == 404" in api,
    "valid popular route fallback":
        "private func fallbackCatalogPage" in api and '"/movie/popular"' in api and '"/tv/popular"' in api,
    "genres match actual items in fallback, no synthetic genre posters":
        'combined.filter { $0.genreIDs.contains(id) }' in api,
    "platform labels not fabricated":
        "if providerCategory {" in api and "items: []" in api and "notice:" in api,
    "403 capabilities cached":
        "private actor XSCatalogEndpointSupport" in api and "markUnsupported(capabilityKey)" in api,
    "notice information modeled explicitly":
        "let notice: String?" in model and "init(items: [MediaItem], hasMore: Bool, notice: String? = nil)" in model,
    "compact grouped catalog navigation":
        "private enum CatalogGroup" in browse and
        'case platforms = "المنصات"' in browse and
        'case genres = "الأنواع"' in browse and
        "ForEach(activeCollections)" in browse,
    "legacy triple separate large filter bars removed":
        'chipRail(title: "المنصات"' not in browse and
        'chipRail(title: "التصنيفات"' not in browse,
    "no hardcoded poster count caps":
        'items.prefix(18)' not in browse and 'items.prefix(30)' not in browse,
    "automatic loading via lazy footer":
        'autoLoadNextPages()' in browse and '.task(id:' in browse,
    "bounded retries with cancellation":
        'failures >= 3' in browse and 'Task.isCancelled' in browse and
        'Task.sleep(nanoseconds: delay)' in browse,
    "manual load more/retry buttons removed":
        'Button("إعادة محاولة تحميل المزيد")' not in browse and
        'Button("إعادة المحاولة")' not in browse,
    "stale request protection":
        'requestGeneration == generation' in browse and
        'categoryID == selectedCollection.id' in browse,
    "last working home items as recovery":
        "let available = app.list(for: kind)" in browse,
    "provider denial explicitly explained":
        "private var providerUnavailable" in browse and
        'selectedCollection.isProvider && catalogNotice != nil' in browse,
    "original R5 subtitle and server machinery protected":
        "sourceSubtitles.select(payload);" in player and
        "func selectServer(_ server: XSServerOption)" in player,
}

for label, result in checks.items():
    if not result:
        raise SystemExit("V9 regression failed: " + label)

print(f"V9 catalog UX PASS: {len(checks)} source integrity checks")
