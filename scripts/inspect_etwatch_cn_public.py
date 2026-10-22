"""Read-only inspection of public ETWatch.cn landing-page API references.
Do not authenticate, extract streaming tokens, download videos or query private endpoints.
"""
import re,json,urllib.request,urllib.error,urllib.parse,socket,html
from html.parser import HTMLParser

class Info(HTMLParser):
    def __init__(self):
        super().__init__();self.scripts=[];self.links=[];self.title_text="";self._title=False
    def handle_starttag(self,tag,attrs):
        d=dict(attrs)
        if tag=="title":self._title=True
        if tag=="script" and d.get("src"):self.scripts.append(d["src"])
        if tag=="a" and d.get("href"):self.links.append(d["href"])
    def handle_endtag(self,tag):
        if tag=="title":self._title=False
    def handle_data(self,data):
        if self._title:self.title_text+=data

def fetch(url,limit=950_000):
    req=urllib.request.Request(url,headers={"User-Agent":"Mozilla/5.0 (compatible; XS-TV-PublicAPI-Assessment/1.0)","Accept":"text/html,application/json,*/*;q=0.7"})
    with urllib.request.urlopen(req,timeout=14) as resp:
        data=resp.read(limit)
        return resp.status,resp.geturl(),resp.headers.get("Content-Type",""),data

for domain in ("etwatch.cn","www.etwatch.cn"):
    try:
        ips={a[4][0] for a in socket.getaddrinfo(domain,None)}
        print("DNS",domain,"resolves",len(ips),"hosts")
    except Exception as e:print("DNS",domain,"FAIL",type(e).__name__)

for url in ("https://etwatch.cn/html/index.html","https://www.etwatch.cn/html/index.html","http://etwatch.cn/html/index.html"):
    try:
        code,final,ct,data=fetch(url)
        print("LANDING",url,"HTTP",code,"final_origin",urllib.parse.urlsplit(final).netloc,
              "type",ct.split(";")[0],"bytes",len(data))
        parser=Info()
        if "html" in ct or data[:250].lower().find(b"<html")>=0:
            body=data.decode("utf-8","replace")
            parser.feed(body)
            print("PAGE_TITLE",html.unescape(parser.title_text)[:150])
            print("SCRIPTS",json.dumps(parser.scripts[:30],ensure_ascii=False))
            print("LINKS",json.dumps(parser.links[:25],ensure_ascii=False))
            print("INLINE_REFERENCES",{
                "fetch":len(re.findall(r"\bfetch\s*\(",body)),
                "axios":len(re.findall(r"\baxios\b",body)),
                "api_path":len(re.findall(r"['\"]\/api\/",body)),
                "m3u8_literal":bool(re.search(r"\bm3u8\b",body,re.I)),
                "api_docs_literal":bool(re.search(r"swagger|openapi|api.docs|api文档",body,re.I))
            })
            for script in parser.scripts[:12]:
                target=urllib.parse.urljoin(final,script)
                if urllib.parse.urlsplit(target).hostname not in ("etwatch.cn","www.etwatch.cn"):
                    continue
                try:
                    code,_,mime,blob=fetch(target,220_000)
                    js=blob.decode("utf-8","replace")
                    # Only list literal, non-secret endpoint path examples.
                    paths=sorted(set(re.findall(r"(?<!\w)/(?:api|v1|v2|movie|tv|vod|search|series)/[A-Za-z0-9_/\-]{1,70}",js)))
                    print("PUBLIC_SCRIPT",urllib.parse.urlsplit(target).path,"HTTP",code,
                          "bytes",len(blob),"sample_path_templates",json.dumps(paths[:20]),
                          "looks_like_api_client",("fetch(" in js or "axios" in js))
                except Exception as e:print("PUBLIC_SCRIPT",urllib.parse.urlsplit(target).path,"FAIL",type(e).__name__)
        elif "json" in ct:
            payload=json.loads(data)
            print("JSON_TYPE",type(payload).__name__,
                  "fields",list(payload)[:25] if isinstance(payload,dict) else "array")
        # The first successful entry is sufficient; avoid requesting duplicates
        break
    except urllib.error.HTTPError as e:print("LANDING",url,"HTTP",e.code)
    except Exception as e:print("LANDING",url,"FAIL",type(e).__name__)
print("PUBLIC_INSPECTION_DONE")
