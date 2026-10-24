"""Fast repository-level validation before Xcode compilation."""
import json
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[1]
feed = json.loads((root / "Resources/SampleFeed.json").read_text())
assert feed["version"] == 1
assert isinstance(feed["entries"], dict)
for key, value in feed["entries"].items():
    assert isinstance(key, str) and key
    for source in value["sources"]:
        assert source["url"].startswith("https://")
        assert all(source.get(name) for name in ("id", "label", "quality"))
with (root / "Resources/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
assert info["CFBundleDisplayName"] == "Gemflix"
swift_sources = list((root / "Sources").glob("*.swift"))
assert len(swift_sources) >= 4
for path in swift_sources:
    text = path.read_text()
    assert "http://" not in text
player = (root / "Sources/EmbeddedPlayer.swift").read_text()
assert "WKWebView" in player and "WKNavigationDelegate" in player
assert "vidsrc.pk" in player and "vidlink.pro" in player
assert "EmbeddedPlayerScreen" in player
assert "availableSubtitles" in player and "selectSubtitle" in player
assert "callAsyncJavaScript" in player and "CaptionParser.parse" in player
assert "captionDelay" in player and "captionBottom" in player
print(f"PASS: {len(swift_sources)} native Swift sources, JSON feed, Info.plist")
