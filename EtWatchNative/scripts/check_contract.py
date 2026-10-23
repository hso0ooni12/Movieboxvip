"""Fast repository-level validation before Xcode compilation."""
import json
import pathlib
import plistlib

root = pathlib.Path(__file__).resolve().parents[1]
feed = json.loads((root / "Resources/SampleFeed.json").read_text())
assert feed["version"] == 1
assert isinstance(feed["entries"], dict)
assert isinstance(feed["football"], list)
for key, value in feed["entries"].items():
    assert isinstance(key, str) and key
    for source in value["sources"]:
        assert source["url"].startswith("https://")
        assert all(source.get(name) for name in ("id", "label", "quality"))
with (root / "Resources/Info.plist").open("rb") as handle:
    info = plistlib.load(handle)
assert info["CFBundleDisplayName"] == "EtWatch Native"
swift_sources = list((root / "Sources").glob("*.swift"))
assert len(swift_sources) >= 4
for path in swift_sources:
    text = path.read_text()
    assert "WKWebView" not in text and "import WebKit" not in text
    assert "http://" not in text
print(f"PASS: {len(swift_sources)} native Swift sources, JSON feed, Info.plist")
