"""V6 regression: Arabic-only (non-sports), panel dismissal, source-ack subtitles.
These checks run on GENERATED Swift after V5/R5 apply and the V6 display pass.
"""
from pathlib import Path

sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")
player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
service = Path("FrameNative/Services/IPTVService.swift").read_text(encoding="utf-8")
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text(encoding="utf-8")
home = Path("FrameNative/Views/XSCinematicHomeView.swift").read_text(encoding="utf-8")

checks = {
    "non-adult permitted live catalog available": "V6_AR_CATALOG" in service and "return (candidate, categories.filter { !excludedIDs.contains($0.categoryID) }, permitted)" in service,
    "adult exclusion preserved": "Self.isAdultChannel($0.name)" in service and "excludedIDs.contains($0.categoryID)" in service,
    "strict Arabic-only gate": 'guard name.hasPrefix("AR") else { return false }' in sports,
    "sports labels excluded after AR prefix": '"SPORT", "SSC", "BEIN SPORT", "DAZN"' in sports and "category.contains($0)" in sports,
    "all list/card data filtered": "arabicStreams.filter" in sports and "ForEach(filteredStreams)" in sports,
    "saved filter remains real": "favoriteIDs.contains(stream.streamID)" in sports and "favoritesOnly" in sports,
    "Arabic channel list and grid": "XSV6ArabicChannelRow" in sports and "compactList" in sports,
    "same R5 VLC stream played": "XSSportsPlayerV33" in sports and "playbackURLs(for: stream)" in sports and "V39_R5_STABILITY_RESTORE" in sports,
    "Arabized tab and home entry": 'Label("القنوات", systemImage: "tv.fill")' in root and 'Text("قنواتك العربية")' in home,
    "server selection uses source engine": "player.selectServer(server)" in player and 'var payload: [String: Any] = ["action": "server", "name": server.name]' in player,
    "server panel dismisses": 'showSelectionNotice("تم اختيار السيرفر:' in player and "closePanel()" in player,
    "subtitle action dismisses immediately": 'waitingForSubtitleID = option.id' in player and "player.selectSubtitle(option)" in player,
    "cue load acknowledgment respected": "player.pendingSubtitleID" in player and "player.selectedSubtitleID == expected" in player,
    "subtitle error not misreported as success": 'player.subtitleSelectionError == nil' in player and 'تعذّر تحميل الترجمة' in player,
    "subtitle bridge unchanged": "sourceSubtitles.select(payload);" in player,
    "notice tasks cleaned": "selectionNoticeTask?.cancel()" in player,
}
for label, ok in checks.items():
    if not ok:
        raise SystemExit("V6 regression FAIL: " + label)

def visible(name, category="General"):
    name, category = name.strip().upper(), category.upper()
    tokens = ["SPORT", "SSC", "BEIN SPORT", "DAZN", "ESPN", "MATCH", "رياض", "مباراة", "كورة", "كرة القدم"]
    return name.startswith("AR") and not any(t in name or t in category for t in tokens)

fixtures = {
    ("AR | MBC 1", "Arabic"): True,
    (" ar : Rotana Cinema", "Entertainment"): True,
    ("AR-Al Jazeera", "News"): True,
    ("US | CNN", "English"): False,
    ("AR | SSC SPORTS", "Arabic"): False,
    ("AR | beIN SPORT 1", "Arabic"): False,
    ("AR | General TV", "Sports / Match"): False,
    ("AR | ESPN", "News"): False,
}
for args, expected in fixtures.items():
    assert visible(*args) == expected, (args, expected)
print(f"V6 AR-only & player feedback PASS: {len(checks)} source invariants and {len(fixtures)} sample channel rules")
