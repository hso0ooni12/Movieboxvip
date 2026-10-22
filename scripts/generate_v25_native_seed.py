"""Generate verifiable offline catalog snapshots from live Cinemeta on every CI build.

Those snapshots are metadata (not movie files or playback links). Startup can
render real posters even if Cinemeta temporarily fails on the iPhone.
"""
import urllib.request,json,base64,pathlib,re

def fetch(kind):
    url="https://v3-cinemeta.strem.io/catalog/"+kind+"/top.json"
    req=urllib.request.Request(url,headers={"User-Agent":"XS-TV-iOS/1.0","Accept":"application/json"})
    with urllib.request.urlopen(req,timeout=28) as res: result=json.load(res)
    raw=result.get("metas",[])
    items=[]
    for entry in raw:
        if not isinstance(entry,dict):continue
        name=str(entry.get("name") or "").strip()
        imdb=str(entry.get("id") or "").strip()
        if not name or not imdb:continue
        moviedb=entry.get("moviedb_id") or None
        site=None
        if moviedb and str(moviedb).isdigit():
            slug=re.sub(r"[^a-z0-9]+","-",name.lower().replace("&"," and ")).strip("-")
            year=(re.search(r"(?:19|20)\d{2}",str(entry.get("releaseInfo") or "")))
            site="https://www.etwatch.net/"+("movie" if kind=="movie" else "series")+"/"+str(moviedb)+"-"+slug+("-"+year.group() if year else "")
        def valid_string(x):
            return x if isinstance(x,str) else None
        try:rating=float(entry.get("imdbRating") or 0)
        except (ValueError,TypeError):rating=0.0
        items.append({
            "id":kind+":"+imdb,
            "title":name,
            "kind":kind,
            "poster":valid_string(entry.get("poster")),
            "backdrop":valid_string(entry.get("background")),
            "summary":str(entry.get("description") or "")[:1800],
            "year":str(entry.get("releaseInfo") or ""),
            "rating":rating,
            "playableURL":None,
            "sourceURL":site,
            "licenseURL":None,
            "imdbID":imdb,
            "episodes":[]
        })
    if len(items)<15:raise RuntimeError("Insufficient "+kind+" metadata from source")
    return items

movie=fetch("movie")
series=fetch("series")
data={}
for kind,items in (("movies",movie),("series",series)):
    binary=json.dumps(items,ensure_ascii=False,separators=(",",":")).encode()
    data[kind]=base64.b64encode(binary).decode()
target=pathlib.Path("FrameNative/Services/XSCinemaNativeSeed.swift")
target.write_text(
    "// Generated from Cinemeta public catalog metadata. Not playable streams.\n"
    "import Foundation\n"
    "enum XSCinemaNativeSeed {\n"
    "  private static func decode(_ text: String) -> [XSCinemaMedia] {\n"
    "    guard let data=Data(base64Encoded:text),\n"
    "          let result=try? JSONDecoder().decode([XSCinemaMedia].self,from:data) else { return [] }\n"
    "    return result\n"
    "  }\n"+
    "  static let movies = decode(\""+data["movies"]+"\")\n"+
    "  static let series = decode(\""+data["series"]+"\")\n"
    "}\n",encoding="utf-8")
print("Generated verified native metadata seeds: movies",len(movie),"series",len(series),
      "valid ETWatch detail page routes",sum(bool(x["sourceURL"]) for x in movie+series),
      "metadata only, no streams")
