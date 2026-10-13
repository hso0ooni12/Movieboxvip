from pathlib import Path

player = Path('FrameNative/FrameXTVPlayerV6.swift').read_text()
components = Path('FrameNative/Views/Components.swift').read_text()
app = Path('FrameNative/FrameNativeApp.swift').read_text()
project = Path('project-native.yml').read_text()

required_player = {
    'V29 marker': 'V29_ULTRA_COMPACT_CHROME',
    '58pt center play': '.frame(width: 58, height: 58)',
    'timeline-adjacent subtitle tools': '.offset(y: -34)',
    'appearance max width': 'maxWidth: 560',
    'timing max width': 'maxWidth: 480',
    '40pt timeline': '.frame(height: 40)',
    '32pt quick tools': '.frame(width: 32, height: 32)',
    'V24 subtitle ownership': 'sourceSubtitles.select(payload)',
    'server selection': 'func selectServer(_ server: XSServerOption)',
}
missing = [name for name, marker in required_player.items() if marker not in player]
if missing:
    raise SystemExit('V29 player QA missing: ' + ', '.join(missing))

if 'proxy.size.width * 0.40, 470' not in player and 'proxy.size.width * 0.36, 430' not in player:
    raise SystemExit('V29/V30 player QA missing: compact quality panel width')

required_perf = {
    'ProMotion opt-in': 'CADisableMinimumFrameDuration: true',
    'explicit generated Info.plist': 'path: FrameNative/Info.plist',
    'Release optimization': 'SWIFT_OPTIMIZATION_LEVEL: "-O"',
    'whole-module compile': 'SWIFT_COMPILATION_MODE: "wholemodule"',
    'larger URL cache': 'memoryCapacity: 128 * 1024 * 1024',
    'smooth browsing marker': 'V29_SMOOTH_BROWSING',
    'no AsyncImage fade': 'Transaction(animation: nil)',
}
texts = project + '\n' + app + '\n' + components
missing_perf = [name for name, marker in required_perf.items() if marker not in texts]
if missing_perf:
    raise SystemExit('V29 performance QA missing: ' + ', '.join(missing_perf))

print('V29 compact + ProMotion QA: PASS')
print('  - smaller/tighter player chrome')
print('  - subtitle tools directly above timeline')
print('  - compact right-side and subtitle panels')
print('  - explicit ProMotion Info.plist opt-in present')
print('  - release optimizations + artwork cache + lighter browsing compositing present')
print('  - V24 subtitle/server engine preserved')
