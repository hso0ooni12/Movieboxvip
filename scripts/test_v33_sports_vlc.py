from pathlib import Path

sports = Path('FrameNative/Views/SportsLiveViewV33.swift').read_text(encoding='utf-8')
root = Path('FrameNative/Views/EnhancedRootView.swift').read_text(encoding='utf-8')
project = Path('project-native.yml').read_text(encoding='utf-8')

haystack = sports + root + project

required = [
    'import VLCKitSPM',
    'let player = VLCMediaPlayer()',
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
    assert marker in haystack, f'missing V33/V34 sports marker: {marker}'

# VLC media assignment supports both the original direct form and the V35
# hardened form that configures live-network options before assignment.
direct_media = 'player.media = VLCMedia(url: urls[index])' in sports
configured_media = (
    'let media = VLCMedia(url: urls[index])' in sports
    and 'media.addOptions(options)' in sports
    and 'player.media = media' in sports
)
assert direct_media or configured_media, 'missing VLC media assignment'

assert 'VLCKitSPM:' in project
assert '- package: VLCKitSPM' in project
assert 'NSAllowsArbitraryLoadsInMedia: true' in project

# The drawable must never consume player-chrome taps. V35 deliberately upgrades
# the canvas gesture from show-only to direct hide/show while preserving this.
assert 'withAnimation(.easeOut(duration: 0.15)) { controlsVisible.toggle() }' not in sports
assert 'Color.clear' in sports
assert (
    '.onTapGesture {\n                    revealControls()\n                }' in sports
    or '.onTapGesture {\n                    toggleControlsFromCanvas()\n                }' in sports
)

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

print('V33/V35 sports integrity PASS: VLC playback + server-only settings + non-interactive drawable + tap controls')
