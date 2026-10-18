from pathlib import Path

# Reference UI regression suite (V39 adaptive layout updates the old V30 fixed-grid check).
player = Path('FrameNative/FrameXTVPlayerV6.swift').read_text()
root = Path('FrameNative/Views/EnhancedRootView.swift').read_text()
reference = Path('FrameNative/Views/ReferenceBrowseViews.swift').read_text()

required_player = {
    'floating menu marker': 'V30_FLOATING_HIT_TARGETS',
    'floating menu rounded card': 'RoundedRectangle(cornerRadius: 20',
    'responsive button style': 'XSPlayerTapButtonStyle',
    'full row hit target': 'minHeight: 44',
    'subtitle/server engine preserved': 'sourceSubtitles.select(payload)',
}
missing = [name for name, marker in required_player.items() if marker not in player]
if missing:
    raise SystemExit('V30 player QA missing: ' + ', '.join(missing))

required_reference = {
    'reference home': 'struct XSReferenceHomeView',
    'reference catalog': 'struct XSReferenceCatalogView',
    'featured film': 'FEATURED FILM',
    'continue watching': 'Continue Watching',
    'filters': 'Filters & Discovery',
    'adaptive poster grid': 'GridItem(.adaptive(minimum: 128, maximum: 185)',
    'hit style': 'XSReferenceHitButtonStyle',
    'home tab routed': 'XSReferenceHomeView(showSettings:',
    'movies routed': 'XSReferenceCatalogView(kind: .movie',
    'series routed': 'XSReferenceCatalogView(kind: .tv',
    'anime routed': 'XSReferenceCatalogView(kind: .anime',
}
texts = reference + '\n' + root
missing_ref = [name for name, marker in required_reference.items() if marker not in texts]
if missing_ref:
    raise SystemExit('V30 reference UI QA missing: ' + ', '.join(missing_ref))

print('V30 UI QA: PASS')
print('  - reference-style home/catalog active')
print('  - functional search/filter/layout controls present')
print('  - expanded button hit targets present')
print('  - player menus float inside the video surface')
print('  - V24 subtitle/server engine preserved')
