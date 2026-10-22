#!/usr/bin/env python3
"""Build-time snapshot of *metadata* from public Cinemeta (not copyrighted video).

The snapshot gives the iPhone a real, instantly visible offline home screen
even when a catalog request times out. Stream playback stays source-dependent.
"""
from pathlib import Path
from urllib.request import Request, urlopen
import json, re

dest=Path("FrameNative/Services/XSCinemaV25Seed.swift")
dest.parent.mkdir(parents=True,exist_ok=True)

def escape(value):
    # Swift quoted-string-compatible UTF-8 with protected literal interpolation.
    s=json.dumps(str(value or ""),ensure_ascii=False)
    return s.replace("\\(", "\\\\(")

def rows(kind):
    url=f"https://v3-cinemeta.strem.io/catalog/{kind}/top.json"
    req=Request(url,headers={"User-Agent":"XS-TV-Cinema-Build/25","Accept":"application/json"})
    with urlopen(req,timeout=25) as f: data=json.load(f)
    metas=data.get("metas")
    assert isinstance(metas,list) and len(metas)>=10, f"Catalog {kind} unavailable"
    results=[]
    seen=set()
    for entry in metas[:35]:
        imdb=str(entry.get("id") or entry.get("imdb_id") or "")
        title=entry.get("name")
        if not title or not imdb or imdb in seen:continue
        seen.add(imdb)
        try: tmdb=int(entry.get("moviedb_id") or entry.get("tmdb_id") or 0)
        except (TypeError,ValueError):tmdb=0
        poster=entry.get("poster") or ""
        background=entry.get("background") or ""
        year=entry.get("releaseInfo") or str(entry.get("year") or "")
        try:rating=float(entry.get("imdbRating") or 0)
        except (TypeError,ValueError):rating=0
        summary=str(entry.get("description") or "")[:400]
        results.append(f'''        XSCinemaMedia(id:{escape(kind+":"+imdb)},
             title:{escape(title)},kind:.{kind},
             poster:{escape(poster)},backdrop:{escape(background)},
             summary:{escape(summary)},year:{escape(year)},
             rating:{rating:.2f},playableURL:nil,sourceURL:nil,licenseURL:nil,
             imdbID:{escape(imdb)},episodes:[],tmdbID:{str(tmdb) if tmdb else "nil"})''')
    assert len(results)>=10, f"Not enough verified {kind} titles"
    print(f"Live {kind} snapshot: {len(results)} real title records")
    return ",\n".join(results)

movie=rows("movie")
series=rows("series")
dest.write_text(
"import Foundation\n\n"
"/// Actual Cinemeta metadata snapshotted at build time, for immediate UI.\n"
"enum XSCinemaV25Seed {\n"
"    static let movies: [XSCinemaMedia] = [\n"+movie+"\n    ]\n"
"    static let series: [XSCinemaMedia] = [\n"+series+"\n    ]\n"
"}\n",encoding="utf-8"
)
assert dest.stat().st_size>1000
print("Generated Swift native catalog seed",dest, dest.stat().st_size,"bytes")
