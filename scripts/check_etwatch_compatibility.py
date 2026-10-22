"""Read-only check for an expressly user-supplied website.

Checks DNS, robots, and landing HTML only. Never accesses video segments,
streaming tokens, login bypasses or player internals.
"""
import socket,urllib.request,urllib.error,urllib.parse,re,html
from html.parser import HTMLParser

sites=["www.etwatch.net","etwatch.net"]
for host in sites:
    try:
        addresses=sorted({item[4][0] for item in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)})
        print("dns:",host,"resolves",len(addresses),"addresses",
              "ipv4:",sum("." in a for a in addresses))
    except Exception as e:
        print("dns:",host,"failed",type(e).__name__)

class Page(HTMLParser):
    def __init__(self): super().__init__();self.links=[];self.title=False;self.title_content=""
    def handle_starttag(self,tag,attrs):
        attrs=dict(attrs)
        if tag=="title":self.title=True
        if tag=="a" and attrs.get("href"):self.links.append(attrs["href"])
    def handle_endtag(self,tag):
        if tag=="title":self.title=False
    def handle_data(self,data):
        if self.title:self.title_content+=data

for base in ("https://www.etwatch.net","https://etwatch.net"):
    for endpoint in ("/robots.txt","/"):
        url=base+endpoint
        try:
            req=urllib.request.Request(url,headers={"User-Agent":"XS-TV-Compatibility-Check/1.0",
                    "Accept":"text/html,text/plain;q=0.8"})
            with urllib.request.urlopen(req,timeout=12) as rsp:
                ctype=rsp.headers.get("content-type","").split(";")[0]
                data=rsp.read(240_000)
                status=rsp.status
                final=urllib.parse.urlparse(rsp.url)
                xframe=rsp.headers.get("X-Frame-Options","none")
                csp=rsp.headers.get("Content-Security-Policy","")
            print("status:",base,endpoint,status,"type:",ctype,
                  "bytes:",len(data),"redirected_to_host:",final.hostname,
                  "x_frame:",xframe,
                  "frame_ancestors_present:","frame-ancestors" in csp.lower())
            if endpoint=="/robots.txt":
                rules=data.decode("utf-8","replace")
                print("robots presence: allow",bool(re.search(r"(?im)^Allow:",rules)),
                      "disallow",bool(re.search(r"(?im)^Disallow:",rules)))
                print("robots user agent rules:",repr(rules[:300]))
            elif "html" in ctype:
                p=Page();p.feed(data.decode("utf-8","replace"))
                print("page: title",repr(html.unescape(p.title_content[:120])))
                print("navigation: movie_hits",sum(bool(re.search(r"movie|film|افلام|أفلام",x,re.I)) for x in p.links),
                      "series_hits",sum(bool(re.search(r"tv|series|مسلسل",x,re.I)) for x in p.links),
                      "html_anchors",len(p.links))
                print("navigation hrefs",repr([u[:100] for u in p.links[:25]]))
        except urllib.error.HTTPError as e:
            print("status:",base,endpoint,"HTTP",e.code)
        except Exception as e:
            print("status:",base,endpoint,"failed",type(e).__name__)
print("Probe complete. No video traffic requested.")
