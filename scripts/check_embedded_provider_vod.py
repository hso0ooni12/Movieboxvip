"""Safely test whether the already configured user's Xtream account offers VOD.
Never print credentials, host, URLs, title names, or exception messages.
"""
import json, os, urllib.parse, urllib.request
host = os.getenv("XS_IPTV_HOST", "").strip().rstrip("/")
user = os.getenv("XS_IPTV_USERNAME", "")
pw = os.getenv("XS_IPTV_PASSWORD", "")
if not host or not user or not pw:
    print("VOD diagnostic: credentials not configured")
    raise SystemExit(0)
if not host.startswith(("http://", "https://")): host = "http://" + host

def request(action, **kwargs):
    q = dict(username=user, password=pw, action=action, **kwargs)
    req = urllib.request.Request(host + "/player_api.php?" + urllib.parse.urlencode(q),
                                headers={"User-Agent": "XS-TV-iOS/1.0", "Accept":"application/json"})
    with urllib.request.urlopen(req, timeout=23) as resp:
        data = resp.read(40 * 1024 * 1024 + 1)
    if len(data) > 40 * 1024 * 1024: raise ValueError("large response")
    return json.loads(data)

print("VOD diagnostic: testing configured provider without revealing account information")
for action, label in [
    ("get_vod_categories", "Movie categories"),
    ("get_series_categories", "Series categories"),
    ("get_vod_streams", "Movies available"),
    ("get_series", "Series available"),
]:
    try:
        items=request(action)
        if isinstance(items, list):
            print(f"{label}: {len(items)}")
            if action == "get_vod_streams" and items:
                extensions = {str(row.get("container_extension","")).lower() for row in items if isinstance(row,dict)}
                print("Movie container types:", ",".join(sorted(e for e in extensions if e in {"mkv","mp4","avi","ts","m3u8","mov"})))
            if action == "get_series" and items:
                example = next((r for r in items if isinstance(r,dict) and r.get("series_id")),None)
                if example:
                    try:
                        detail=request("get_series_info",series_id=str(example["series_id"]))
                        episodes=detail.get("episodes",{}) if isinstance(detail,dict) else {}
                        print("Series episode discovery:", "supported" if isinstance(episodes,dict) and episodes else "no episodes exposed")
                    except Exception as e:
                        print("Series episode discovery: request failed ("+type(e).__name__+")")
        else:
            print(f"{label}: not a list")
    except Exception as e:
        print(f"{label}: request failed ({type(e).__name__})")
print("VOD diagnostic finished; no account data printed")
