"""Sanitized test for provider VOD playback extension, redirect and response.
Queries the already configured user account. Never prints URLs, credentials,
IDs, titles (except target match count), redirect locations or exception details.
Range probes read at most 192 bytes each, and do not download full media.
"""
import json, os, time, urllib.parse, urllib.request, urllib.error
host=os.getenv("XS_IPTV_HOST","").strip().rstrip("/")
user=os.getenv("XS_IPTV_USERNAME","")
password=os.getenv("XS_IPTV_PASSWORD","")
if not all((host,user,password)):
    print("Probe: account not configured");raise SystemExit(0)
if not host.startswith(("http://","https://")): host="http://"+host
qs=urllib.parse.urlencode(dict(username=user,password=password,action="get_vod_streams"))
try:
    req=urllib.request.Request(host+"/player_api.php?"+qs,headers={"User-Agent":"XS-TV/1.0 (iOS)"})
    with urllib.request.urlopen(req,timeout=25) as res: rows=json.load(res)
except Exception as e:
    print("Catalog unavailable:",type(e).__name__);raise SystemExit(0)
matches=[a for a in rows if isinstance(a,dict) and
         "blood shine" in str(a.get("name","")).lower()]
print("Blood Shine matching movie entries:",len(matches))
if not matches: raise SystemExit(0)
def probe(movie,ext,ua):
    safe=lambda s:urllib.parse.quote(str(s),safe="")
    url=host+"/movie/"+safe(user)+"/"+safe(password)+"/"+str(movie["stream_id"])+"."+ext
    req=urllib.request.Request(url,headers={"User-Agent":ua,"Range":"bytes=0-1023"})
    start=time.monotonic()
    try:
        with urllib.request.urlopen(req,timeout=15) as resp:
            prefix=resp.read(192)
            return {"status":resp.status,"received":len(prefix),"ms":int((time.monotonic()-start)*1000),
                   "type":(resp.headers.get("Content-Type","").split(";")[0])[:35],
                   "redirected":resp.url!=url}
    except urllib.error.HTTPError as err:
        return {"status":err.code,"received":0,"ms":int((time.monotonic()-start)*1000)}
    except Exception as err:
        return {"error":type(err).__name__}
for movie in matches[:2]:
    providerExt=str(movie.get("container_extension") or "").lower()
    print("Provider extension:",providerExt if providerExt in ("mkv","mp4","ts","m3u8","avi") else "other")
    for ext in dict.fromkeys([providerExt,"mkv","mp4","ts"]):
        if ext not in ("mkv","mp4","ts","m3u8","avi"):continue
        print(ext,"app-UA",probe(movie,ext,"XS-TV/1.0 (iOS)"),
                  "VLC-UA",probe(movie,ext,"LibVLC/4.0.0"))
