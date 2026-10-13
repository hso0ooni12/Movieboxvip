from pathlib import Path

sports = Path('FrameNative/Views/SportsLiveViewV33.swift').read_text()
root = Path('FrameNative/Views/EnhancedRootView.swift').read_text()
project = Path('project-native.yml').read_text()

required = [
    'import VLCKitSPM',
    'VLCMediaPlayer()',
    'VLCMedia(url:',
    'XSVLCVideoSurface',
    'XSSportsServerSettingsView',
    'Server Address',
    'xs.iptv.serverOverride',
    'XSSportsLiveViewV33()',
]
for marker in required:
    haystack = sports + root + project
    assert marker in haystack, f'missing V33 marker: {marker}'

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

print('V33 sports VLC/server-only settings integrity PASS')
