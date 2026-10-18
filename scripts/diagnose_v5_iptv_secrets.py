"""Opt-in build diagnostic for the user's configured Xtream account.

Runs with GitHub Actions Secrets ONLY; no credential is committed or printed.
This reports coarse host/account/catalog status, without printing URLs,
request exceptions, query strings, or any user-specific fields.
"""
import json
import os
import urllib.parse
import urllib.request

public_candidates = [
    "http://vpn.liondnscloud.ru:80",
    "http://line.goalozne.store:80",
]
host = os.getenv("XS_IPTV_HOST", "").strip().rstrip("/")
username = os.getenv("XS_IPTV_USERNAME", "")
password = os.getenv("XS_IPTV_PASSWORD", "")
if not host or not username or not password:
    print("IPTV diagnostics: GitHub repository secrets incomplete.")
    raise SystemExit(0)
if not host.startswith(("http://", "https://")):
    host = "http://" + host
print("IPTV diagnostics: configured host matches supplied provider:",
      "yes" if host.lower() in [x.lower() for x in public_candidates] else "no")

hosts = [host] + [x for x in public_candidates if x.lower() != host.lower()] if host.lower() in [x.lower() for x in public_candidates] else [host]

def request(candidate, action=None):
    query = {"username": username, "password": password}
    if action:
        query["action"] = action
    url = candidate + "/player_api.php?" + urllib.parse.urlencode(query)
    req = urllib.request.Request(url, headers={"User-Agent":"XS-TV/1.0 (iOS)"})
    with urllib.request.urlopen(req, timeout=8) as response:
        return json.load(response)

for index, candidate in enumerate(hosts, 1):
    try:
        auth_data = request(candidate)
        if not isinstance(auth_data, dict):
            print(f"IPTV endpoint {index}: invalid API response")
            continue
        info = auth_data.get("user_info") or {}
        auth = str(info.get("auth", "0")).lower() in ("1", "true")
        if not auth:
            print(f"IPTV endpoint {index}: provider did not authenticate this build account")
            continue
        streams = request(candidate, "get_live_streams")
        if not isinstance(streams, list):
            print(f"IPTV endpoint {index}: login accepted, but live list unavailable")
            continue
        print(f"IPTV endpoint {index}: authentication accepted; {len(streams)} live stream entries")
        if streams:
            print("IPTV diagnostics: at least one host can return a live catalog.")
            break
    except Exception as exc:
        # HTTPError may contain the full credential-bearing URL: never print it.
        print(f"IPTV endpoint {index}: request failed ({type(exc).__name__}); region or provider may restrict CI.")
else:
    print("IPTV diagnostics: no tested endpoint returned usable live entries from this CI runner.")
print("IPTV diagnostics finished; credentials were not printed.")
