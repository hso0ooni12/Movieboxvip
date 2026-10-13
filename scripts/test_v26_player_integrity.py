from pathlib import Path

src = Path('FrameNative/FrameXTVPlayerV6.swift').read_text()

required = {
    'V24 source-owned subtitle selection': 'sourceSubtitles.select(payload)',
    'V24 source subtitle reset': 'sourceSubtitles.reset()',
    'V24 subtitle request state': 'private func clearSubtitleRequest()',
    'subtitle catalog owner frame': 'subtitleFrameID',
    'subtitle selection acknowledgement': 'xs:subtitleSelected',
    'server selection': 'func selectServer(_ server: XSServerOption)',
    'server command': '"action": "server"',
    'subtitle appearance panel': 'private var subtitleStylePanel: some View',
    'subtitle timing panel': 'private var subtitleDelayPanel: some View',
    'persistent subtitle size': '@AppStorage("XSTV.subtitleFontScale")',
    'persistent subtitle position': '@AppStorage("XSTV.subtitleBottomPadding")',
    'persistent subtitle background style': '@AppStorage("XSTV.subtitleBackgroundStyle")',
    'persistent subtitle background opacity': '@AppStorage("XSTV.subtitleBackgroundOpacity")',
    'floating appearance button': '.accessibilityLabel("Subtitle appearance")',
    'floating timing button': '.accessibilityLabel("Subtitle timing")',
    'source subtitle utility strip hider': 'function hideSubtitleUtilityDock()',
    'fade-only player panel': 'panelOverlay(proxy)\n                        .transition(.opacity)',
    'tap controls': '.onTapGesture',
    'PiP': 'player.requestPiP()',
    'AirPlay': 'XSAirPlayPicker()',
    'seek backward': 'player.seekBy(-10)',
    'seek forward': 'player.seekBy(10)',
}

missing = [name for name, marker in required.items() if marker not in src]
if missing:
    raise SystemExit('V26 integrity check missing: ' + ', '.join(missing))

# V8 removed the old native four-button strip. V26 must not reintroduce it.
for obsolete in [
    'Image(systemName: "tortoise")',
    'Image(systemName: "character.bubble")',
]:
    if obsolete in src:
        raise SystemExit(f'V26 obsolete native subtitle toolbar control still present: {obsolete}')

# The real CC menu still owns language selection and Off.
if 'panelRow(title: "Off"' not in src:
    raise SystemExit('V26 lost the real subtitle Off row')
if 'openPanel(.subtitles)' not in src:
    raise SystemExit('V26 lost the real CC/subtitle panel launcher')

print('V26 player integrity: PASS')
print('  - V24 subtitle/server bridge preserved')
print('  - V25 appearance persistence preserved')
print('  - FrameXTV subtitle utility strip hidden without touching the CC language popup')
print('  - new floating appearance/timing dock present')
print('  - playback controls/PiP/AirPlay/seek markers present')
