// Read the site's public, rendered catalogue into native metadata. No streams,
// tokens, cookies, subtitle files or media files are copied into this snapshot.
const { chromium } = require('playwright');
const fs = require('node:fs');
(async () => {
  const browser = await chromium.launch({headless:true});
  try {
    const page = await browser.newPage({ viewport:{width:1280,height:900} });
    await page.goto('https://www.etwatch.net/home', {waitUntil:'domcontentloaded',timeout:45000});
    await page.waitForFunction(() => document.querySelectorAll('a[href^="/movie/"]').length > 100,
                               null, {timeout:45000});
    await page.waitForFunction(() => Array.from(document.querySelectorAll('h2'))
      .some(h => h.textContent.includes('Based on a True Story')), null, {timeout:30000});
    const data = await page.evaluate(() => {
      const items = new Map();
      const shelves = [];
      function parse(a) {
        const path = a.getAttribute('href');
        const match = path && path.match(/^\/(movie|series)\/(\d+)-/);
        const image = a.querySelector('img');
        const title = (a.getAttribute('aria-label') || image?.alt || '').trim();
        if (!match || !title || !image?.src) return null;
        const kind = match[1];
        const id = 'etwatch:' + kind + ':' + match[2];
        const values = Array.from(a.querySelectorAll('span')).map(s => s.textContent.trim());
        const rating = values.find(v => /^\d\.\d$/.test(v));
        return { id, title, kind, poster:image.src, backdrop:null, summary:'',
          year:path.match(/-(\d{4})$/)?.[1] || '', rating:Number(rating)||0,
          playableURL:null, sourceURL:new URL(path,location.origin).href,
          licenseURL:null, imdbID:null, episodes:[] };
      }
      for (const heading of document.querySelectorAll('h2')) {
        let container = heading.parentElement;
        for (let depth=0;container && depth<5;depth++,container=container.parentElement) {
          const anchors=container.querySelectorAll('a[href^="/movie/"],a[href^="/series/"]');
          if (!anchors.length) continue;
          if (container.querySelectorAll('h2').length !== 1) break;
          let title=heading.textContent.trim();
          if (/ on$/i.test(title)) title += ' ' + (heading.parentElement.querySelector('button')?.textContent.trim() || '');
          const selected=[];
          for(const a of anchors) { const item=parse(a); if(item){items.set(item.id,item);selected.push(item.id);} }
          if(selected.length) shelves.push({id:'etwatch:'+shelves.length,title,itemIDs:[...new Set(selected)]});
          break;
        }
      }
      for(const a of document.querySelectorAll('a[href^="/movie/"],a[href^="/series/"]')) {
        const item=parse(a);if(item&&!items.has(item.id))items.set(item.id,item);
      }
      for(const image of document.images) {
        if(!image.closest('a')&&image.alt&&image.src.includes('/w1280/')) {
          const item=[...items.values()].find(m=>m.title===image.alt);
          if(item)item.backdrop=image.src;
        }
      }
      return {generated:new Date().toISOString(),items:[...items.values()],shelves};
    });
    if(data.items.length<120 || data.shelves.length<8)throw Error('Incomplete public source catalogue');
    fs.mkdirSync('FrameNative/Resources',{recursive:true});
    fs.writeFileSync('FrameNative/Resources/etwatch-catalog.json',JSON.stringify(data));
    console.log(JSON.stringify({source:'ETWatch public catalogue',titles:data.items.length,
      movies:data.items.filter(x=>x.kind==='movie').length,series:data.items.filter(x=>x.kind==='series').length,
      shelves:data.shelves.length}));
  } finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exit(1)});
