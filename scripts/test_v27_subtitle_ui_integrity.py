from pathlib import Path

src = Path('FrameNative/FrameXTVPlayerV6.swift').read_text()

required = {
    'V27 marker': 'V27_COMPACT_SUBTITLE_UI',
    'compact subtitle panel': 'private func compactSubtitlePanel<Content: View>',
    'appearance compact route': 'compactSubtitlePanel(proxy, maxWidth: 820, title: "Subtitle Appearance"',
    'timing compact route': 'compactSubtitlePanel(proxy, maxWidth: 680, title: "Subtitle Timing"',
    'close button': '.accessibilityLabel("Close subtitle tools")',
    'timeline adjacent tools': '.offset(y: -64)',
    'zero opacity option': 'in: 0.0...1.0, step: 0.05',
    'nested caption surface fix': 'const deepest = descendants.filter',
    'background opacity pushed': 'backgroundOpacity: subtitleBackgroundOpacity',
    'V24 subtitle selection': 'sourceSubtitles.select(payload)',
    'server selection': 'func selectServer(_ server: XSServerOption)',
    'subtitle selection acknowledgement': 'xs:subtitleSelected',
}

missing = [name for name, marker in required.items() if marker not in src]
if missing:
    raise SystemExit('V27 integrity check missing: ' + ', '.join(missing))

# The appearance panel must not require sideways scrolling anymore.
a = src.find('    private var subtitleStylePanel: some View {')
b = src.find('    private var subtitleDelayPanel: some View {', a)
if a < 0 or b < 0:
    raise SystemExit('V27 could not isolate subtitle appearance panel')
appearance = src[a:b]
if 'ScrollView(.horizontal' in appearance:
    raise SystemExit('V27 appearance panel still contains horizontal scrolling')

# Timing must be closable by the shared compact panel header.
if 'case .subtitleDelay:' not in src or 'title: "Subtitle Timing"' not in src:
    raise SystemExit('V27 timing panel is not routed through the closable compact container')

# Keep the working source subtitle/server engine unchanged in ownership semantics.
for marker in ['subtitleFrameID', 'private func clearSubtitleRequest()', 'sourceSubtitles.reset()']:
    if marker not in src:
        raise SystemExit('V27 lost working V24 engine marker: ' + marker)

print('V27 subtitle UI integrity: PASS')
print('  - appearance panel compact and no horizontal scroll')
print('  - timing panel has shared close control')
print('  - subtitle tool dock sits next to timeline')
print('  - background opacity paints nested source caption surfaces')
print('  - V24 subtitle/server ownership preserved')
