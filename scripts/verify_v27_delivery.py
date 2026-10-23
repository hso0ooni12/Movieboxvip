"""Delivery checks complement runtime JS tests and native Swift route tests."""
import json
from pathlib import Path
snapshot=json.loads(Path('FrameNative/Resources/etwatch-catalog.json').read_text())
assert len(snapshot['items']) >= 120
assert len(snapshot['shelves']) >= 8
items={item['id']:item for item in snapshot['items']}
assert len(items)==len(snapshot['items'])
for shelf in snapshot['shelves']:
    assert shelf['title'] and shelf['itemIDs']
    assert all(key in items for key in shelf['itemIDs'])
for item in items.values():
    assert item['kind'] in ('movie','series')
    assert item['sourceURL'].startswith('https://www.etwatch.net/')
    assert item['poster'].startswith('https://')
    assert not item['playableURL']
root=Path('FrameNative/Views/EnhancedRootView.swift').read_text()
assert 'XSSportsLiveViewV33()' in root
assert 'XSCinemaNativeHomeView()' in root
assert 'XSETWatchPortalView(' not in root
print('V27 delivery PASS:',len(items),'source titles,',len(snapshot['shelves']),'source shelves, native tabs + original Sports')
