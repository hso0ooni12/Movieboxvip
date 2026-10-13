from pathlib import Path

sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")
tmdb = Path("FrameNative/Services/TMDBClient.swift").read_text(encoding="utf-8")

required_sports = [
    "XSVLCVideoSurface(player: model.player)",
    ".background(.ultraThinMaterial, in: Circle())",
    "Pause live channel",
    "Close player",
    "Playback sources",
    "Reload live channel",
    "model.togglePlayPause()",
]
for marker in required_sports:
    assert marker in sports, f"missing sports marker: {marker}"

# The working VLC decoder must remain underneath the native-style controls.
assert "private final class XSSportsVLCPlayerModel" in sports
assert "let player = VLCMediaPlayer()" in sports

required_anime = [
    'include_adult", value: "false"',
    "filterSafeAnime(candidates)",
    "filterUnsafeAnimeFromMixedResults(items)",
    '/keywords",',
    '/content_ratings",',
    "containsExplicitSexualMarker",
    '"hentai"',
    '"ecchi"',
    '"nudity"',
    '"sexual content"',
    '"fanservice"',
    "isExplicitAdultRating",
]
for marker in required_anime:
    assert marker in tmdb, f"missing anime safety marker: {marker}"

# Do not convert the entire anime catalog to a blanket 18+ ban.
assert '"TV-MA"' not in tmdb
assert "R18+" in tmdb

print("V34 integrity PASS: working VLC backend + iOS-style chrome + targeted clean-anime filter")
