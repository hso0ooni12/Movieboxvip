"""Supplementary non-streaming provider and Arabic subtitle checks."""
import json,urllib.request,urllib.error,time
targets=[
("vidrock_movies_index","https://vidrock.net/list/movie.json"),
("vidrock_series_index","https://vidrock.net/list/tv.json"),
("vidrock_movie_embed","https://vidrock.net/movie/603"),
("vidfast_movie_embed","https://vidfast.vc/movie/603?sub=ar"),
("vidfast_series_embed","https://vidfast.vc/tv/1399/1/1?sub=ar"),
("andro_manifest","https://androsubs.vercel.app/manifest.json"),
("arabic_sub_the_dark_knight","https://opensubtitles-v3.strem.io/subtitles/movie/tt0468569.json"),
("arabic_sub_shawshank","https://opensubtitles-v3.strem.io/subtitles/movie/tt0111161.json"),
("arabic_sub_inception","https://opensubtitles-v3.strem.io/subtitles/movie/tt1375666.json"),
("arabic_sub_got_s1e1","https://opensubtitles-v3.strem.io/subtitles/series/tt0944947:1:1.json"),
("arabic_sub_friends_s1e1","https://opensubtitles-v3.strem.io/subtitles/series/tt0108778:1:1.json"),
]
for key,url in targets:
    now=time.monotonic()
    req=urllib.request.Request(url,headers={
      "User-Agent":"XS-TV-Source-Research/1.1",
      "Range":"bytes=0-262143",
      "Accept":"application/json,text/html;q=0.7,*/*;q=0.2"})
    try:
        with urllib.request.urlopen(req,timeout=9) as res:
            status=res.status;type_=res.headers.get("Content-Type","").split(";")[0]
            blob=res.read(262144)
        datum={"status":status,"type":type_,"ms":round((time.monotonic()-now)*1000),
               "bytes_read":len(blob)}
        if "sub_" in key and "json" in type_:
            try:
                payload=json.loads(blob);subs=payload.get("subtitles",[])
                datum.update({"tracks":len(subs),
                              "arabic_tracks":sum(str(s.get("lang","")).lower() in
                                  ("ar","ara","arabic") for s in subs)})
            except Exception as e:datum["parsing"]=type(e).__name__
        elif key=="andro_manifest" and "json" in type_:
            try:
                payload=json.loads(blob)
                datum.update({"addon":payload.get("name"),"resources":payload.get("resources")})
            except Exception as e:datum["parsing"]=type(e).__name__
        elif "index" in key and "json" in type_:
            try:
                payload=json.loads(blob)
                datum["index_root_type"]=type(payload).__name__
                datum["estimated_index_items"]=len(payload)
            except Exception as e:datum["parsing"]=type(e).__name__
        print(key,json.dumps(datum))
    except urllib.error.HTTPError as e:
        print(key,json.dumps({"status":e.code,"ms":round((time.monotonic()-now)*1000)}))
    except Exception as e:
        print(key,json.dumps({"error":type(e).__name__,"ms":round((time.monotonic()-now)*1000)}))
