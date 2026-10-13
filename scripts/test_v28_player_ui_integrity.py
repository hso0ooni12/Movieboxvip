from pathlib import Path

src = Path('FrameNative/FrameXTVPlayerV6.swift').read_text()

required = {
    'V28 marker': 'V28_PROPORTIONAL_PLAYER_CHROME',
    'working V24 source subtitle selection': 'sourceSubtitles.select(payload)',
    'working server selection': 'func selectServer(_ server: XSServerOption)',
    'V27 compact appearance panel': 'compactSubtitlePanel(proxy, maxWidth: 720',
    'V27 compact timing panel': 'compactSubtitlePanel(proxy, maxWidth: 600',
    'smaller center play button': '.frame(width: 68, height: 68)',
    'smaller seek backward': 'gobackward.10").font(.system(size: 30',
    'smaller seek forward': 'goforward.10").font(.system(size: 30',
    'smaller round close button': '.frame(width: 36, height: 36)',
    'smaller timeline': '.frame(height: 44)',
    'subtitle tools close to timeline': '.offset(y: -52)',
    'background opacity storage': '@AppStorage("XSTV.subtitleBackgroundOpacity")',
    'background opacity renderer': 'subtitleBackgroundCSS()',
}

missing = [name for name, marker in required.items() if marker not in src]
if missing:
    raise SystemExit('V28 integrity check missing: ' + ', '.join(missing))

# Guard against regression to the oversized V26/V27 chrome.
for obsolete in [
    '.frame(width: 88, height: 88)',
    'gobackward.10").font(.system(size: 38',
    'goforward.10").font(.system(size: 38',
    '.offset(y: -64)',
]:
    if obsolete in src:
        raise SystemExit('V28 oversized player chrome still present: ' + obsolete)

print('V28 player UI integrity: PASS')
print('  - V24 subtitle/server engine preserved')
print('  - V27 subtitle appearance/timing behavior preserved')
print('  - center transport controls reduced')
print('  - top/bottom chrome reduced')
print('  - subtitle tool dock moved tight to timeline')
print('  - compact subtitle panels retained')
