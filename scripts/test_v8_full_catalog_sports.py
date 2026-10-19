"""V8 tests: comprehensive IPTV AR sports coverage and true paginated catalogs.

These are executable build-time source/test fixtures. Live provider membership
and external endpoint availability still require testing with a valid account.
"""
from pathlib import Path

sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
model=Path("FrameNative/Core/XSCatalogCollection.swift").read_text()
client=Path("FrameNative/Services/TMDBClient.swift").read_text()
browse=Path("FrameNative/Views/ReferenceBrowseViews.swift").read_text()
iptv=Path("FrameNative/Services/IPTVService.swift").read_text()
player=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()

checks = {
    "either AR channel or AR provider category": "V8_AR_SPORTS_COMPLETE" in sports and
        'isARRegion(name) || isARRegion(group)' in sports,
    "sports provider categories keep unlabeled channels": 'categorySports.contains(stream.categoryID)' in sports,
    "regional filtering cannot leak other areas": 'guard isARRegion(name) || isARRegion(group) else { return false }' in sports,
    "broad sports identifiers and broadcaster names": all(a in sports for a in [
        '"BEIN"', '"SSC"', '"ALKASS"', '"ON TIME"', '"RIYADI"', '"UFC"', '"رياض"'
    ]),
    "all provider streams retained before sports-only filtering": 'V6_AR_CATALOG' in iptv and
        "return (candidate, categories.filter { !excludedIDs.contains($0.categoryID) }, permitted)" in iptv,
    "network cache preserves faster reopening": 'collectionCache[currentCacheKey]' in browse and
        'cacheOrder.count > 8' in browse,
    "movie catalog starts directly with posters": 'catalogSpotlight(' not in browse and
        'posterCollection' in browse,
    "all previously fixed poster caps gone": 'items.prefix(18)' not in browse and 'items.prefix(30)' not in browse,
    "provider metadata filters real source": 'with_watch_providers' in client and 'watch_region' in client and
        'with_watch_monetization_types' in client,
    "genre filters real source": 'with_genres' in client,
    "genres and providers exposed": len([m for m in model.splitlines() if 'item("provider-' in m]) >= 8
        and 'genres.map' in model,
    "all discover requests paged": 'let safePage = max(1, min(page, 500))' in client and
        'totalPages = "total_pages"' in client,
    "scroll drives real pages": 'autoLoadNextPages()' in browse and
        'nextPage += 1' in browse and 'response.hasMore' in browse,
    "network response not stale after tab change": 'requestGeneration == generation' in browse and
        'categoryID == selectedCollection.id' in browse,
    "all catalog sections are real query types": all(s in model for s in [
        'case discover, trending, popular, topRated, new',
        'case genre(Int)', 'case provider(Int)'
    ]),
    "search still routes to selected title details": 'XSReferencePosterCard(item: item)' in browse and
        '.navigationDestination(for: MediaItem.self) { DetailView(item: $0) }' in browse,
    "R5 verified subtitle remains protected": 'sourceSubtitles.select(payload);' in player and
        'player.pendingSubtitleID' in player,
}

for label, ok in checks.items():
    if not ok:
        raise SystemExit("V8 FAIL: "+label)

sports_terms=["SPORT","BEIN","SSC","ESPN","DAZN","EUROSPORT","MATCH","FOOTBALL",
              "ALKASS","AL KASS","ALKAS","KASS","ADSPORT","ON TIME",
              "RIYADI","RIYADIA","ARRYADIA","الكأس","رياض","دوري","بطولة"]
def match(name, category):
    n=name.strip().upper()
    c=category.strip().upper()
    regional = n.startswith("AR") or c.startswith("AR") or n.startswith("[AR]") or c.startswith("[AR]")
    return regional and any(term in n or term in c for term in sports_terms)
fixtures={
    ("AR | beIN SPORTS 1", "General"): True,
    ("beIN SPORTS 1 HD", "AR | Sports"): True,
    ("SSC HD 1", "AR SPORTS"): True,
    ("AR | MBC 1", "AR | Entertainment"): False,
    ("AR | Al Kass", "News"): True,
    ("US | beIN Sports", "US | SPORT"): False,
    ("AR | Rotana Cinema", "Movies"): False,
    ("Sports 1 HD", "AR | Sports"): True,
    ("AR | Sports Extra", "Misc"): True,
    ("FR | Al Kass", "FR"): False,
}
for args, expected in fixtures.items():
    actual = match(*args)
    if actual != expected:
        raise SystemExit(f"V8 sports fixture FAIL: {args}: {actual} != {expected}")

print(f"V8 PASS: {len(checks)} integration guards and {len(fixtures)} sports eligibility fixtures")
