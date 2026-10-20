"""Source health check: public metadata only. Never download full video or log secrets."""
import json,urllib.request,urllib.error,time
checks=[
("Cinemeta global catalog","https://v3-cinemeta.strem.io/catalog/movie/top.json"),
("Public Domain Movies manifest","https://caching.stremio.net/publicdomainmovies.now.sh/manifest.json"),
("Public Domain Movies catalog","https://caching.stremio.net/publicdomainmovies.now.sh/catalog/movie/publicdomainmovies.json"),
("OpenSubtitles v3 manifest","https://opensubtitles-v3.strem.io/manifest.json"),
("OpenSubtitles v3 Arabic sample","https://opensubtitles-v3.strem.io/subtitles/movie/tt1375666.json"),
("ANDRO Arabic manifest","https://androsubs.vercel.app/manifest.json"),
("ANDRO Arabic sample","https://androsubs.vercel.app/subtitles/movie/tt1375666.json"),
("WatchHub manifest","https://watchhub.strem.io/manifest.json"),
]
ok=0
for name,url in checks:
    now=time.monotonic()
    try:
        req=urllib.request.Request(url,headers={"User-Agent":"XS-TV-Cinema/1.0","Accept":"application/json"})
        with urllib.request.urlopen(req,timeout=13) as r:
            payload=r.read(640_000)
            status=r.status
        o=json.loads(payload)
        if "manifest" in name:
            msg="manifest="+str(o.get("name","unknown"))
        elif "catalog" in name:
            titles=o.get("metas",[])
            msg="items="+str(len(titles))
        else:
            subs=o.get("subtitles",[])
            ar=sum(x.get("lang") in ("ar","ara","arabic") for x in subs)
            msg="total_subtitles="+str(len(subs))+", arabic="+str(ar)
        print(name,"HTTP",status,round((time.monotonic()-now)*1000),"ms",msg)
        ok+=1
    except Exception as exc:
        print(name,"failed:",type(exc).__name__)
print("Provider checks responded:",ok,"/",len(checks))
# Source availability is dynamic. Don't block compilation when independent
# providers fail; runtime should show normal provider-specific failure states.
