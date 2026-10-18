"""Baseline contract checks. Run after the original V35 generator pipeline."""
from pathlib import Path
import subprocess

PROTECTED = {
  'FrameNative/FrameXTVPlayerV6.swift': 'a7deaf4aa9c988f0f692bdf264365b91923318ad',
  'FrameNative/Views/SportsLiveViewV33.swift': '19dccf84f02cdf1fd4521775fe982fb93ed41b40',
  'scripts/player_v24_source_menu_bridge.py': '8de18c341f65054677cb97ec66f08716d42f3235',
  'scripts/app_v35_final_polish.py': '5010922629c58dbab4d5416cbfd21d1c9698515a',
  'scripts/xs_source_subtitles.js': '698fdc2acbd656c1e11325e60fdea1e825c040e0',
  'project-native.yml': 'd42469cfb3587d29048a89e0f0fb183b9229eba2'
}
for path, expected_sha in PROTECTED.items():
    actual = subprocess.check_output(['git', 'rev-parse', 'HEAD:' + path], text=True).strip()
    assert actual == expected_sha, f'Baseline V39 component changed: {path}'

state = Path('FrameNative/Core/AppState.swift').read_text()
search = Path('FrameNative/Views/GlobalSearchView.swift').read_text()
details = Path('FrameNative/Views/DetailView.swift').read_text()
components = Path('FrameNative/Views/Components.swift').read_text()
browse = Path('FrameNative/Views/ReferenceBrowseViews.swift').read_text()
assert 'if isLoading || (didLoad && !force)' in state
assert 'defer { isLoading = false }' in state
assert 'try Task.checkCancellation()' in state
assert 'text == trimmedQuery' in search
assert 'Button("Retry Search")' in search
assert 'if item.kind == .movie' in details
assert 'accessibilityReduceMotion' in details and 'accessibilityReduceMotion' in components
assert browse.count('accessibilityReduceMotion') >= 2
assert 'FrameNative.favoriteItems.v2' in state and 'FrameNative.watchProgress.v2' in state
print('V39 premium safety checks PASSED — source player, VLC, playback scripts and saved-data keys protected')
