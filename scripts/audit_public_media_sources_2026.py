"""Public, non-secret streaming integration audit.
Only checks catalog, subtitle metadata, and public embed landing responses.
Does NOT stream copyrighted video or scrape media/CDN links.
"""
import json, ssl, time, urllib.request, urllib.error
targets=[
 ("cinemeta_manifest","https://v3-cinemeta.strem.io/manifest.json"),
 ("cinemeta_movie_catalog","https://v3-cinemeta.strem.io/catalog/movie/top.json"),
 ("cinemeta_series_catalog","https://v3-cinemeta.strem.io/catalog/series/top.json"),
 ("cinemeta_series_meta","https://v3-cinemeta.strem.io/meta/series/tt0903747.json"),
 ("opensubtitles_v3_manifest","https://opensubtitles-v3.strem.io/manifest.json"),
 ("opensubtitles_ar_movie","https://opensubtitles-v3.strem.io/subtitles/movie/tt0133093.json"),
 ("opensubtitles_ar_series","https://opensubtitles-v3.strem.io/subtitles/series/tt0903747:1:1.json"),
 ("vidsrc_providers","https://embed.vidsrc.pk/__stream/providers"),
 ("vidsrc_info","https://embed.vidsrc.pk/__stream/mediaInfo?id=550&type=movie"),
 ("vidlink_movie_embed","https://vidlink.pro/movie/603"),
 ("vidlink_series_embed","https://vidlink.pro/tv/1399/1/1"),
 ("vidsrc_movie_embed","https://embed.vidsrc.pk/movie/tt0133093"),
 ("embedwave_movie_embed","https://embedwave.cc/embed/movie/603"),
]
for name,url in targets:
    start=time.monotonic()
    req=urllib.request.Request(url,headers={
        "User-Agent":"XS-TV-Source-Research/1.0",
        "Accept":"application/json,text/html;q=0.8,*/*;q=0.2",
        "Range":"bytes=0-131071"})
    try:
        with urllib.request.urlopen(req,timeout=14) as r:
            payload=r.read(131072)
            status=r.status;ctype=r.headers.get("Content-Type","").split(";")[0]
            redirected=(r.url.split("/")[2]!=url.split("/")[2])
        elapsed=round((time.monotonic()-start)*1000)
        summary={"status":status,"type":ctype,"ms":elapsed,"bytes":len(payload),
                 "redirected_domain":redirected}
        if "json" in ctype or (payload.startswith(b"{") and len(payload)<131072):
            try:
                data=json.loads(payload)
                if isinstance(data,dict):
                    if name.endswith("manifest"):
                        summary.update({"addon_name":data.get("name"),
                                        "resources":data.get("resources")})
                    elif "catalog" in name:
                        summary["catalog_page_items"]=len(data.get("metas",[]))
                        summary["first_result_has_video_url"]=any(
                            "url" in x and bool(x.get("url")) for x in data.get("metas",[])[:8]
                            if isinstance(x,dict))
                    elif "meta" in name:
                        m=data.get("meta",{})
                        summary.update({"series_episode_count":len(m.get("videos",[])),
                                        "has_stream_link":bool(m.get("url"))})
                    elif "subtitles" in name:
                        tracks=data.get("subtitles",[])
                        summary.update({"tracks":len(tracks),
                            "arabic_tracks":len([s for s in tracks if
                                str(s.get("lang","")).lower() in ("ar","ara","arabic")]),
                            "tracks_have_source_hash":sum(1 for s in tracks if
                                s.get("id"))})
                    elif name=="vidsrc_providers":
                        prov=data if isinstance(data,list) else data.get("providers",[])
                        summary["providers"]=len(prov) if isinstance(prov,list) else "unknown"
                    else:
                        summary["json_keys"]=list(data.keys())[:10]
            except Exception as e:
                summary["json_parse"]=type(e).__name__
        print(name,json.dumps(summary,ensure_ascii=False))
    except urllib.error.HTTPError as e:
        print(name,json.dumps({"status":e.code,"ms":round((time.monotonic()-start)*1000)}))
    except Exception as e:
        print(name,json.dumps({"error_type":type(e).__name__,
                               "ms":round((time.monotonic()-start)*1000)}))
