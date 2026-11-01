"""Create sanitized public catalogue fixtures and artwork from a supplied Safari archive."""
import argparse
import hashlib
import html
import io
import json
from pathlib import Path
import plistlib
import re
from urllib.parse import parse_qs, unquote, urlparse

from PIL import Image, ImageDraw, ImageOps


def dictionaries(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from dictionaries(child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(child)


def normalize(value, fallback=None):
    if not isinstance(value.get("id"), int) or not (value.get("title") or value.get("name")):
        return None
    return {
        "tmdbID": value["id"], "kind": value.get("media_type", fallback or ("movie" if "title" in value else "tv")),
        "name": value.get("title") or value.get("name"), "overview": value.get("overview", ""),
        "posterPath": value.get("poster_path"), "backdropPath": value.get("backdrop_path"),
        "releaseDate": value.get("release_date") or value.get("first_air_date"),
        "rating": value.get("vote_average", 0),
        "genres": [g["name"] for g in value.get("genres", []) if isinstance(g, dict) and "name" in g]
        if isinstance(value.get("genres"), list) else [],
        "runtime": value.get("runtime"),
    }


def build(source, destination):
    archive = plistlib.loads(source.read_bytes())
    page = archive["WebMainResource"]["WebResourceData"].decode("utf-8")
    flight = "".join(json.loads(m) for m in re.findall(r'self\.__next_f\.push\(\[1,("(?:\\.|[^"\\])*")\]\)', page))
    props = []
    for line in flight.splitlines():
        key, _, raw = line.partition(":")
        if not re.fullmatch(r"[a-f0-9]+", key):
            continue
        try:
            value = json.loads(raw)
        except ValueError:
            continue
        for item in dictionaries(value):
            if isinstance(item.get("items") or item.get("initialItems"), list):
                # Only retain public catalogue fields. Do not persist the original document or layout state.
                fields = {k: item[k] for k in ("title", "items", "initialItems", "providers", "defaultProviderId", "mediaType") if k in item}
                props.append(fields)
    featured, rails, providers, seen = [], [], [], set()
    fixture_records = []
    for entry in props:
        if entry.get("providers"):
            providers = entry["providers"]
        items = [normalized for item in entry.get("items", entry.get("initialItems", []))
                 if (normalized := normalize(item, entry.get("mediaType")))]
        if not items:
            continue
        title = entry.get("title")
        if not isinstance(title, str) or title.startswith("$"):
            title = None
        if "defaultProviderId" in entry:
            provider = next((p["label"] for p in providers if p["id"] == entry["defaultProviderId"]), None)
            if provider:
                title = f"On {provider}"
        if title:
            key = (title, tuple((x["kind"], x["tmdbID"]) for x in items))
            if key in seen:
                continue
            seen.add(key)
            rails.append({"id": title, "title": title, "items": items})
        elif not featured:
            featured = items
        else:
            continue
        fixture_records.append(entry)
    snapshot = {"featured": featured, "rails": rails, "providers": providers, "capturedAt": "2026-11-01T00:00:00Z"}
    resources = destination / "WatchedNative/Resources"
    resources.mkdir(parents=True, exist_ok=True)
    (resources / "home-snapshot.json").write_text(json.dumps(snapshot, ensure_ascii=False, separators=(",", ":")))
    fixture = destination / "Tests/Fixtures"
    fixture.mkdir(parents=True, exist_ok=True)
    chunks = "".join(f'{i:x}:["$","$Lcomponent",null,{json.dumps(p, ensure_ascii=False, separators=(",", ":"))}]\n' for i, p in enumerate(fixture_records))
    (fixture / "home-flight.html").write_text('<html><script>self.__next_f.push([1,' + json.dumps(chunks, ensure_ascii=False) + '])</script></html>')
    image_map = {}
    for item in archive.get("WebSubresources", []):
        if not item.get("WebResourceMIMEType", "").startswith("image/"):
            continue
        url = urlparse(item.get("WebResourceURL", ""))
        image_url = parse_qs(url.query).get("url", [item.get("WebResourceURL", "")])[0]
        basename = Path(urlparse(unquote(image_url)).path).name
        if not basename:
            continue
        try:
            image = ImageOps.exif_transpose(Image.open(io.BytesIO(item["WebResourceData"]))).convert("RGB")
        except Exception:
            continue
        image.thumbnail((600, 450))
        name = "art-" + hashlib.sha256(basename.encode()).hexdigest()[:12] + ".jpg"
        image.save(resources / name, quality=68, optimize=True)
        image_map[basename] = name
    (resources / "image-map.json").write_text(json.dumps(image_map, indent=2))
    assets = resources / "Assets.xcassets"
    icon = assets / "AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    image = Image.new("RGB", (1024, 1024), (10, 10, 10))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((150, 210, 874, 814), radius=165, fill=(255, 74, 85))
    draw.polygon([(433, 347), (433, 677), (686, 512)], fill="white")
    image.save(icon / "icon.png", optimize=True)
    (icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "icon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}))
    (assets / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}')
    color = assets / "LaunchBackground.colorset"
    color.mkdir(exist_ok=True)
    (color / "Contents.json").write_text(json.dumps({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.039", "green": "0.039", "blue": "0.039", "alpha": "1.000"}}}], "info": {"author": "xcode", "version": 1}}))
    ids = {(x["kind"], x["tmdbID"]) for x in featured + [i for r in rails for i in r["items"]]}
    print(json.dumps({"featured": len(featured), "rails": [(r["title"], len(r["items"])) for r in rails], "uniqueTitles": len(ids), "bundledImages": len(image_map)}, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    build(arguments.archive, arguments.destination)
