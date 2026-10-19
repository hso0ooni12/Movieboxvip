"""Read-only subtitle track probe for user's already configured Xtream VOD.
Shows only aggregate track availability, never titles, URLs, or credentials.
"""
import json, os, shutil, subprocess, urllib.parse, urllib.request
host=os.getenv("XS_IPTV_HOST","").strip().rstrip("/")
username=os.getenv("XS_IPTV_USERNAME","")
password=os.getenv("XS_IPTV_PASSWORD","")
if not host or not username or not password:
    print("Subtitle diagnostic: account not configured")
    raise SystemExit(0)
if not host.startswith(("http://","https://")): host="http://"+host
if not shutil.which("ffprobe"):
    print("Subtitle diagnostic: ffprobe unavailable on this runner")
    raise SystemExit(0)

def get(action,**extra):
    params=dict(username=username,password=password,action=action,**extra)
    request=urllib.request.Request(host+"/player_api.php?"+urllib.parse.urlencode(params))
    with urllib.request.urlopen(request,timeout=20) as resp:
        return json.load(resp)

try:
    categories=get("get_vod_categories")
    titles=get("get_vod_streams")
    series=get("get_series")
except Exception as error:
    print("Subtitle diagnostic: VOD request failed ("+type(error).__name__+")")
    raise SystemExit(0)

subcats={str(x.get("category_id")) for x in categories
         if any(q in str(x.get("category_name","")).lower()
                for q in ("sub","arabic","مترجم","ترجمة","arab"))}
print("Movie categories possibly indicating subtitles:",len(subcats))
blocked=("xxx","adult","porn","hentai","18+","anime","انمي")
movies=[x for x in titles
        if isinstance(x,dict) and x.get("stream_id") and
           str(x.get("container_extension","")).lower() in ("mkv","mp4") and
           not any(w in str(x.get("name","")).lower() for w in blocked)]
preferred=[x for x in movies if str(x.get("category_id")) in subcats]
samples=(preferred[:3] + movies[:3])[:5]
unique=[];ids=set()
for m in samples:
    if m["stream_id"] not in ids:
        unique.append(m)
        ids.add(m["stream_id"])

safe=lambda v: urllib.parse.quote(v,safe="")
def probe(kind,stream_id,extension):
    url=(host+"/"+kind+"/"+safe(username)+"/"+safe(password)+"/"+
         str(stream_id)+"."+str(extension).lower())
    try:
        cmd=["ffprobe","-v","error","-rw_timeout","8000000","-probesize",
             "1000000","-analyzeduration","1500000","-show_entries",
             "stream=codec_type:stream_tags=language,title","-of","json",url]
        result=subprocess.run(cmd,capture_output=True,text=True,timeout=22)
        if result.returncode!=0: return None
        streams=json.loads(result.stdout or "{}").get("streams",[])
        subs=[s for s in streams if s.get("codec_type")=="subtitle"]
        found=any(any(marker in str(s.get("tags",{}).get(key,"")).lower()
                      for marker in ("arabic","ara","العربية","عربي"))
                  for s in subs for key in ("language","title"))
        return (len(subs),found)
    except Exception:
        return None

success=0; found_ar=0; no_tracks=0
for movie in unique:
    result=probe("movie",movie["stream_id"],movie["container_extension"])
    if result is None:
        print("Sampled movie track probe: inconclusive")
    else:
        success+=1;found_ar+=int(result[1]);no_tracks+=int(result[0]==0)
        print("Sampled movie subtitle tracks:",result[0],
              "Arabic detected:" + ("yes" if result[1] else "no"))

try:
    target=next(x for x in series if isinstance(x,dict) and x.get("series_id"))
    details=get("get_series_info",series_id=str(target["series_id"]))
    episodes=details.get("episodes",{})
    episode=next(x for bucket in episodes.values() for x in bucket
                 if isinstance(x,dict) and x.get("id"))
    result=probe("series",episode["id"],episode.get("container_extension","mp4"))
    if result is not None:
        print("Sampled series episode subtitle tracks:",result[0],
              "Arabic detected:" + ("yes" if result[1] else "no"))
    else:
        print("Sampled series episode track probe: inconclusive")
except Exception:
    print("Series subtitle probe: inconclusive")
print("Track probe summary:",success,"movies inspected;",
      found_ar,"with Arabic tracks;",no_tracks,"without subtitle tracks.")
