"""Diagnose native V24 catalog and public ETWatch structural integration.
Never download a movie, media segments, credentials or subtitle files.
Per ETWatch robots Disallow, no crawling or bulk page traversal. Request
only the homepage and /movies given by the website navigation.
"""
import json,urllib.request,urllib.error,urllib.parse,re,html
from html.parser import HTMLParser

def get(url):
 req=urllib.request.Request(url,headers={"User-Agent":"XS-TV-iOS-Integration-Diagnostic/1.0","Accept":"application/json,text/html"})
 with urllib.request.urlopen(req,timeout=18) as resp:
  body=resp.read(350000)
  return resp.status,resp.headers.get("Content-Type",""),body

for endpoint in ("https://v3-cinemeta.strem.io/catalog/movie/top.json",
 "https://v3-cinemeta.strem.io/catalog/series/top.json",
 "https://v3-cinemeta.strem.io/catalog/movie/top/skip=20.json",
 "https://v3-cinemeta.strem.io/catalog/movie/top/search=Matrix.json",
 "https://archive.org/advancedsearch.php?q=mediatype%3Amovies%20AND%20licenseurl%3Ahttp%2A&fl%5B%5D=identifier&rows=10&output=json"):
 try:
  status,ct,b=get(endpoint)
  j=json.loads(b)
  titles=j.get("metas",[])
  o={"status":status,"ct":ct.split(";")[0],"bytes":len(b),
     "metas":len(titles),"sample_fields":list(titles[0].keys())[:22] if titles else [],
     "first_id":titles[0].get("id") if titles else "",
     "first_imdb_rating_type":type(titles[0].get("imdbRating")).__name__ if titles else "",
     "error":j.get("error") or j.get("message"),
     "archive_count":len(j.get("response",{}).get("docs",[]))}
  print(endpoint.split("/")[2],endpoint.split("/")[-1][:55],json.dumps(o))
 except Exception as e:print(endpoint.split("/")[-1][:50],"FAILED",type(e).__name__)

for url in ("https://www.etwatch.net/","https://www.etwatch.net/movies"):
 try:
  status,ct,raw=get(url); doc=raw.decode("utf-8","replace")
  tags=[s[:115] for s in re.findall(r'<script[^>]*src="([^"]+)"',doc)][:16]
  links=re.findall(r'<a[^>]*href="([^"]+)"',doc)
  data=re.search(r'<script[^>]*id="__NEXT_DATA__"[^>]*>(.*?)</script>',doc,re.S)
  print("ETWatch direct page",urllib.parse.urlsplit(url).path,status,len(raw),
        "next_data",bool(data),
        "scripts",json.dumps(tags[:7]),
        "anchors",len(links),
        "unique_anchor_prefixes",json.dumps(list(dict.fromkeys(links))[:22]),
        "jsonld",len(re.findall(r'application/ld\+json',doc)),
        "tmdb_word",doc.lower().count("tmdb"),
        "video_word",doc.lower().count("video"),
        "api_word",doc.lower().count("/api/"))
 except Exception as e:print("ETWatch direct page",url,type(e).__name__)
