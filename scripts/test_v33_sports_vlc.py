from pathlib import Path

sports = Path('FrameNative/Views/SportsLiveViewV33.swift').read_text(encoding='utf-8')
root = Path('FrameNative/Views/EnhancedRootView.swift').read_text(encoding='utf-8')
project = Path('project-native.yml').read_text(encoding='utf-8')

required = [
    'import VLCKitSPM',
    'let player = VLCMediaPlayer()',
    'player.media = VLCMedia(url: urls[index])',
    'XSVLCVideoSurface',
    'XSSportsServerSettingsView',
    'Server Address',
    'xs.iptv.serverOverride',
    'XSSportsLiveViewV33()',
    'controlsHideTask',
    'revealControls()',
    '4_000_000_000',
    '.allowsHitTesting(false)',
    'view.isUserInteractionEnabled = false',
    'uiView.isUserInteractionEnabled = false',
]
for marker in required:
    haystack = sports + root + project
    assert marker in haystack, f'missing V33/V34 sports marker: {marker}'

assert 'VLCKitSPM:' in project
assert '- package: VLCKitSPM' in project
assert 'NSAllowsArbitraryLoadsInMedia: true' in project

# Tapping the video surface must reveal controls only. The VLC drawable itself
# must never receive the tap, otherwise VLCKit can toggle pause internally.
assert 'withAnimation(.easeOut(duration: 0.15)) { controlsVisible.toggle() }' not in sports
assert '.onTapGesture {\n                    revealControls()\n                }' in sports
assert 'Color.clear' in sports

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

print('V33/V34 sports integrity PASS: VLC playback + server-only settings + tap-to-show controls without pause')
