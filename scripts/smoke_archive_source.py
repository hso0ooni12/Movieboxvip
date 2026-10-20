import json, urllib.parse, urllib.request
queries=[
  'mediatype:movies AND licenseurl:http* AND NOT collection:classic_tv',
  'mediatype:movies AND licenseurl:http* AND (collection:classic_tv OR subject:episodes OR title:episode)',
]
def get(url):
  req=urllib.request.Request(url,headers={"User-Agent":"XS-TV-OpenCinema/1.0"})
  with urllib.request.urlopen(req,timeout=20) as resp:
    return json.load(resp)
def isAllowed(raw):
  return any(x in raw.lower().replace("https://","http://") for x in (
    "creativecommons.org/licenses/by/","creativecommons.org/licenses/by-sa/",
    "creativecommons.org/publicdomain/zero/"))
for label,q in zip(("movies","series"),queries):
  params=urllib.parse.urlencode({"q":q, "rows":30, "page":1, "output":"json","fl[]":"identifier",
                                  "sort[]":"downloads desc"})
  try:
    data=get("https://archive.org/advancedsearch.php?"+params)
    docs=data.get("response",{}).get("docs",[])
    print(label,"search_count",len(docs))
    licensed=video=0
    for entry in docs[:14]:
      ident=entry.get("identifier","")
      if not ident: continue
      try:
        md=get("https://archive.org/metadata/"+urllib.parse.quote(ident))
        raw=md.get("metadata",{}).get("licenseurl","")
        if not isinstance(raw,str):continue
        if not isAllowed(raw):continue
        licensed+=1
        video+=int(any(any(f.get("name","").lower().endswith(x) for x in
             (".mp4",".webm",".mkv")) and int(f.get("size",0) or 0)>5_000_000
                  for f in md.get("files",[])))
      except Exception as e:print(label,"metadata_exception",type(e).__name__)
    print(label,"license_and_video",licensed,video)
  except Exception as e:print(label,"search_exception",type(e).__name__)
