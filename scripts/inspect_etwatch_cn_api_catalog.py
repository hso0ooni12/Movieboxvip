"""Inspect only publicly linked ETWatch.cn API listing/dataset landing pages.
No authenticated operations, no deep crawling, no streaming requests.
"""
import urllib.request,urllib.parse,urllib.error,re,html,json
from html.parser import HTMLParser
class Extract(HTMLParser):
 def __init__(self):super().__init__();self.t=[];self.s=[];self.links=[];self.title="";self.in_title=False
 def handle_starttag(self,tag,attrs):
  d=dict(attrs)
  if tag=="script" and d.get("src"):self.s.append(d["src"])
  if tag=="a" and d.get("href"):self.links.append((d.get("href"),d.get("title","")))
  if tag=="title":self.in_title=True
 def handle_endtag(self,tag):
  if tag=="title":self.in_title=False
 def handle_data(self,t):
  x=t.strip()
  if self.in_title:self.title+=x
  if len(x)>2 and not self.in_title:self.t.append(x[:200])
def get(url,limit=350000):
 req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0 (XS-TV-ReadOnly-API-Audit)"})
 with urllib.request.urlopen(req,timeout=14) as resp:return resp.status,resp.read(limit).decode("utf-8","replace"),resp.geturl()
base="http://etwatch.cn"
for path in ("/html/apilist.html","/html/datasetlist.html","/static/front/js/index.js?t=0.13","/static/front/config/config.js?t=1.006"):
 try:
  code,body,final=get(base+path)
  print("RESOURCE",path,"status",code,"chars",len(body))
  if path.endswith(".html"):
   p=Extract();p.feed(body)
   print("PAGE",p.title,"VISIBLE_TEXT",json.dumps(p.t[:45],ensure_ascii=False)[:3300])
   print("SCRIPTS",json.dumps(p.s[:30],ensure_ascii=False))
   print("LINKS",json.dumps(p.links[:20],ensure_ascii=False))
  else:
   api_paths=sorted(set(re.findall(r"(?<!\w)/(?:front/api|api|data|project|interface)/[A-Za-z0-9_/?=&.-]{1,80}",body)))
   print("LITERAL_API_PATHS",json.dumps(api_paths[:28]))
   print("VIDEO_KEYWORDS",{
      "movie":len(re.findall(r"\bmovie\b",body,re.I)),
      "stream":len(re.findall(r"\bstream\b",body,re.I)),
      "video":len(re.findall(r"\bvideo\b",body,re.I)),
      "film":len(re.findall(r"\bfilm\b",body,re.I)),
      "dataset":len(re.findall(r"\bdataset\b",body,re.I))
    })
 except Exception as e:print("RESOURCE",path,"FAILED",type(e).__name__)
