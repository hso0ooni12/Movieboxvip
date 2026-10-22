"""Create a tiny, resilient offline-native browse cache from public Cinemeta.
Only metadata (titles/artwork IDs), NO playable video URLs, stream scraping,
tokens or third-party copyrighted media downloads.
"""
from pathlib import Path
import json,urllib.request,time
BASE="https://v3-cinemeta.strem.io/catalog"
root=Path("FrameNative/Resources")
root.mkdir(parents=True,exist_ok=True)
for kind in ("movie","series"):
    url=f"{BASE}/{kind}/top.json"
    req=urllib.request.Request(url,headers={"User-Agent":"XS-TV-Native-Cinema/1.0","Accept":"application/json"})
    with urllib.request.urlopen(req,timeout=35) as res:
        data=json.load(res)
    output=[]
    for item in data.get("metas",[])[:55]:
        if not isinstance(item,dict) or not isinstance(item.get("id"),str) or not isinstance(item.get("name"),str):continue
        record={key:item[key] for key in
            ("id","name","poster","background","description","releaseInfo","year","imdbRating","moviedb_id")
            if key in item and isinstance(item[key],(str,int,float))}
        output.append(record)
    assert len(output)>=18,f"Bootstrap catalog {kind}: only {len(output)} titles"
    path=root/f"xs-cinema-{kind}-bootstrap.json"
    path.write_text(json.dumps({"metas":output},ensure_ascii=False,separators=(",",":")),encoding="utf-8")
    print(kind,"bootstrap",len(output),"titles",path.stat().st_size,"bytes")
print("Local movie & series tiles guaranteed even when runtime catalog endpoint is unavailable.")
