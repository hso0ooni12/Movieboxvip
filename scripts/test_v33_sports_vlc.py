from pathlib import Path
import runpy

# Apply the latest hardening layer and the compile-safe VLCKit construction
# before integrity checks / Xcode build.
runpy.run_path('scripts/app_v34_content_sports_hardening.py', run_name='__main__')
runpy.run_path('scripts/app_v34_compile_fix.py', run_name='__main__')

sports = Path('FrameNative/Views/SportsLiveViewV33.swift').read_text(encoding='utf-8')
root = Path('FrameNative/Views/EnhancedRootView.swift').read_text(encoding='utf-8')
project = Path('project-native.yml').read_text(encoding='utf-8')
tmdb = Path('FrameNative/Services/TMDBClient.swift').read_text(encoding='utf-8')

required = [
    'import VLCKitSPM',
    'VLCMediaPlayer(options:',
    'guard let media = VLCMedia(url:',
    'XSVLCVideoSurface',
    'XSSportsServerSettingsView',
    'Server Address',
    'xs.iptv.serverOverride',
    'XSSportsLiveViewV33()',
    '--clock-jitter=0',
    '--clock-synchro=0',
    '--drop-late-frames',
    '--skip-frames',
    'player.rate = 1.0',
    'controlsHideTask',
    'scheduleControlsHide()',
    '2_700_000_000',
    'var extensions: [String] = ["ts"]',
]
for marker in required:
    haystack = sports + root + project
    assert marker in haystack, f'missing V33/V34 sports marker: {marker}'

assert 'VLCKitSPM:' in project
assert '- package: VLCKitSPM' in project
assert 'NSAllowsArbitraryLoadsInMedia: true' in project

# Sports settings must never expose editable username/password fields.
settings_start = sports.index('private struct XSSportsServerSettingsView')
settings_end = sports.index('private struct XSSportsChannelCardV33')
settings = sports[settings_start:settings_end]
assert 'Username' not in settings
assert 'Password' not in settings
assert 'SecureField' not in settings
assert 'username:' not in settings
assert 'password:' not in settings

# Embedded credentials are still reused internally while only host is overridden.
assert 'username: embedded.username' in sports
assert 'password: embedded.password' in sports

# Strict anime safety must go beyond TMDB's generic include_adult=false flag.
anime_markers = [
    'AnimeSafetyResponse',
    'content_ratings,keywords',
    'AnimeSafety.containsBlockedTerms',
    'result.adult != true',
    'guard adult != true else { return nil }',
    'TV-MA',
    'hentai',
    'ecchi',
    'nudity',
    'fanservice',
    'محتوى جنسي',
]
for marker in anime_markers:
    assert marker in tmdb, f'missing anime safety marker: {marker}'

print('V34 anime safety + VLC live playback + auto-hide integrity PASS')
