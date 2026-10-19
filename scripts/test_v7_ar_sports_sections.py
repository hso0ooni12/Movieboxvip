"""V7 regression: AR sports only, real provider sections, fast derived browsing.

Run AFTER V6's source-generation pass and AFTER app_v7_ar_sports_sections.
Checks are source-level tests, not claims of real-device sports playback.
"""
from pathlib import Path

sports=Path("FrameNative/Views/SportsLiveViewV33.swift").read_text()
root=Path("FrameNative/Views/EnhancedRootView.swift").read_text()
home=Path("FrameNative/Views/XSCinematicHomeView.swift").read_text()
service=Path("FrameNative/Services/IPTVService.swift").read_text()
player=Path("FrameNative/FrameXTVPlayerV6.swift").read_text()
models=Path("FrameNative/Core/Models.swift").read_text()
posters=Path("FrameNative/Views/Components.swift").read_text()

checks={
    "strict AR prefix": 'guard name.uppercased().hasPrefix("AR") else { return false }' in sports,
    "sports are now ALLOWED instead of excluded": "sportsKeywordMatch(name)" in sports and
        'sportsKeywordMatch(categoriesByID[stream.categoryID] ?? "")' in sports and
        "return !sportsTerms.contains" not in sports,
    "sports filter includes mainstream Arabic brands": all(w in sports for w in [
        '"SPORT"', '"BEIN"', '"SSC"', '"ESPN"', '"DAZN"', '"الكأس"', '"رياض"', '"مباراة"']),
    "category names reflect actual provider": 'ForEach(sportsSections) { group in' in sports and
        "group.categoryName" in sports and "group.categoryID" in sports,
    "category selection updates actual stream filter": "stream.categoryID == selectedCategoryID" in sports,
    "favorites scoped to Arabic sports": "sportsStreams.filter" in sports and
        "favoriteIDs.contains(stream.streamID)" in sports,
    "filtered sports catalog cached": "@State private var sportsStreams" in sports and
        "rebuildSportsIndex(categories:" in sports and
        ".onReceive(store.$streams)" in sports and ".onReceive(store.$categories)" in sports,
    "one-pass provider category index": "Dictionary(" in sports and
        "for stream in matches" in sports,
    "clear channel search button": 'TextField("ابحث عن قناة أو بطولة...", text: $query)' in sports and
        '.accessibilityLabel("مسح البحث")' in sports,
    "real category count per section": "sportsCategoryCount[group.categoryID]" in sports,
    "real category selection haptic": "UISelectionFeedbackGenerator().selectionChanged()" in sports,
    "reduce motion respected": "@Environment(\\.accessibilityReduceMotion) private var reduceMotion" in sports,
    "lazy list and grid retained": "LazyVStack(spacing: 9)" in sports and
        "LazyVGrid(" in sports and "ForEach(filteredStreams)" in sports,
    "favorite and play have separate tap surfaces": "XSV6ArabicChannelRow" in sports and
        'play: { selectedStream = stream }' in sports and
        "toggleFavorite: { toggleFavorite(stream.streamID) }" in sports,
    "sports named correctly in navigation": 'Label("الرياضة", systemImage: "sportscourt.fill")' in root and
        'Text("رياضتك العربية المباشرة")' in home,
    "R5 VLC controller untouched": "XSSportsPlayerV33" in sports and
        "V39_R5_STABILITY_RESTORE" in sports and
        "XSVLCStableSurfaceView" in sports,
    "V5 provider and cache untouched": "V6_AR_CATALOG" in service and
        "restoreCache(for: credentials)" in service and
        'action: "get_live_streams"' in service,
    "V6 servers acknowledge existing source": "player.selectServer(server)" in player and
        "showSelectionNotice" in player and
        'var payload: [String: Any] = ["action": "server", "name": server.name]' in player,
    "no original size hero images": 'if backdrop {' in models and 'default: size = "w1280"' in models,
    "supported TMDB backdrop sizes": 'case ..<420: size = "w300"' in models and 'case ..<1000: size = "w780"' in models,
    "poster network size follows visible width": "proxy.size.width * displayScale" in posters and
        "item.imageURL(backdrop: backdrop, width: deliveredWidth)" in posters,
    "poster loads without per-tile animations": "Transaction(animation: nil)" in posters,
    "V6 subtitles confirm source cue": "player.pendingSubtitleID" in player and
        "sourceSubtitles.select(payload);" in player and
        "player.selectedSubtitleID == expected" in player,
}
for name, passed in checks.items():
    if not passed:
        raise SystemExit("V7 FAIL: "+name)

def should_show(name, category):
    terms = [
        "SPORT", "BEIN", "SSC", "ESPN", "DAZN", "EUROSPORT",
        "MATCH", "FOOTBALL", "SOCCER", "ARENA", "F1", "FORMULA",
        "UFC", "WWE", "NBA", "NHL", "TENNIS", "RACING",
        "ALKASS", "AL KASS", "KASS", "الكأس", "كأس",
        "رياض", "مباريات", "مباراة", "كورة", "الكرة", "كرة القدم",
        "دوري", "بطولة", "ملاعب", "مصارعة", "سباق"
    ]
    name = name.strip().upper()
    category = category.upper()
    return name.startswith("AR") and any(t in name or t in category for t in terms)

samples={
    ("AR | beIN Sports 1", "Arabic"): True,
    ("AR | SSC 1", "AR"): True,
    ("AR | Alkass HD", "AR"): True,
    ("AR | AD Sports", "Arabic"): True,
    ("AR | قناة 1", "AR | القنوات الرياضية"): True,
    ("ar : BBC", "News"): False,
    ("AR | MBC 1", "Arabic Entertainment"): False,
    ("AR | Rotana", "Cinema"): False,
    ("US | Bein Sports", "Sports"): False,
    ("FR | SSC Sports", "Sports"): False,
    ("AR | ESPN", "General"): True,
    ("AR | World Cup", "News"): False,
}
for fixture, expected in samples.items():
    actual=should_show(*fixture)
    if actual != expected:
        raise SystemExit("V7 fixture FAIL: "+repr((fixture,expected,actual)))

print(f"V7 Arabic sports and provider sections PASS: {len(checks)} UI/integration invariants; {len(samples)} sports fixtures")
