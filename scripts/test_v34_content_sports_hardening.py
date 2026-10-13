from pathlib import Path


tmdb = Path("FrameNative/Services/TMDBClient.swift").read_text(encoding="utf-8")
sports = Path("FrameNative/Views/SportsLiveViewV33.swift").read_text(encoding="utf-8")
root = Path("FrameNative/Views/EnhancedRootView.swift").read_text(encoding="utf-8")

required_tmdb = [
    "AnimeSafetyResponse",
    "content_ratings,keywords",
    "AnimeSafety.containsBlockedTerms",
    "result.adult != true",
    "TV-MA",
    "fanservice",
    "nudity",
    "hentai",
    "ecchi",
    "guard adult != true else { return nil }",
]
for marker in required_tmdb:
    assert marker in tmdb, f"missing anime safety marker: {marker}"

required_sports = [
    "import VLCKitSPM",
    "VLCMediaPlayer(options:",
    "--clock-jitter=0",
    "--clock-synchro=0",
    "--drop-late-frames",
    "--skip-frames",
    'var extensions: [String] = ["ts"]',
    "player.rate = 1.0",
    "controlsHideTask",
    "scheduleControlsHide()",
    "2_700_000_000",
    "XSSportsServerSettingsView",
    "Server Address",
]
for marker in required_sports:
    assert marker in sports, f"missing sports hardening marker: {marker}"

# Sports settings must expose server only. Do not render account credentials.
settings_start = sports.index("private struct XSSportsServerSettingsView")
settings_end = sports.index("private struct XSSportsChannelCardV33")
settings = sports[settings_start:settings_end]
assert "Username" not in settings
assert "Password" not in settings
assert "SecureField" not in settings

# V33 sports remains wired into the main navigation.
assert "XSSportsLiveViewV33()" in root

print("V34 anime safety + sports playback integrity PASS")
