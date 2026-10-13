from pathlib import Path

root = Path(__file__).resolve().parents[1]
root_view = (root / "FrameNative/Views/EnhancedRootView.swift").read_text(encoding="utf-8")
sports = (root / "FrameNative/Views/SportsLiveViewV32.swift").read_text(encoding="utf-8")
search = (root / "FrameNative/Views/GlobalSearchView.swift").read_text(encoding="utf-8")

checks = {
    "sports v32 selected": "XSSportsLiveViewV32()" in root_view,
    "global search toolbar on every tab": root_view.count(".xsGlobalSearchToolbar()") >= 5,
    "global search destination": "XSGlobalSearchView()" in root_view,
    "sports full screen player": ".fullScreenCover(item: $selectedStream)" in sports,
    "sports explicit close": "Button { dismiss() }" in sports,
    "native AVPlayer controls": "AVPlayerViewController" in sports and "showsPlaybackControls = true" in sports,
    "HLS first source": 'var extensions = ["m3u8"]' in sports,
    "TS fallback source": 'extensions.contains("ts")' in sports,
    "video track verification": "loadTracks(withMediaType: .video)" in sports,
    "channel artwork fallback": "generatedArtwork" in sports and "beIN SPORTS" in sports,
    "search has visible text field": 'TextField("Type a title…"' in search,
    "search results show titles": "Text(item.title)" in search,
    "search results open details": "DetailView(item: item)" in search,
}

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)

if failed:
    raise SystemExit("V32 checks failed: " + ", ".join(failed))

print("V32 sports/search integrity PASS")
