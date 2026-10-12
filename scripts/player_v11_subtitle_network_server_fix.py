from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

text = text.replace(
    'WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)',
    'WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)',
    1
)

old = '''        case "xs:subtitles":
            subtitleScanFinished = true
            guard let rows = payload["items"] as? [[String: Any]] else { return }
'''
new = '''        case "xs:subtitles":
            if let final = payload["final"] as? Bool, final { subtitleScanFinished = true }
            guard let rows = payload["items"] as? [[String: Any]] else { return }
'''
if old not in text:
    raise SystemExit('subtitle receive marker not found')
text = text.replace(old, new, 1)

old = '''                    panelRow(title: server.name, detail: server.quality.isEmpty ? (server.selected ? "Connected" : "Available") : "\\(server.quality) · \\(server.selected ? "Connected" : "Available")") {
                        player.selectServer(server)
                        closePanel()
                    }
'''
new = '''                    panelRow(title: server.name, detail: server.quality.isEmpty ? (server.selected ? "Connected" : "Available") : "\\(server.quality) · \\(server.selected ? "Connected" : "Available")") {
                        player.selectServer(server)
                        holdControls()
                    }
'''
if old in text:
    text = text.replace(old, new, 1)

start = text.find('      function scanSubtitles() {')
end = text.find('\n      function parseServerRow', start)
if start == -1 or end == -1:
    raise SystemExit('scanSubtitles bounds not found')

scanner = r'''      let networkSubtitleItems = [];
      const networkSubtitleSeen = new Set();

      function normalizeSubtitleLabel(raw) {
        return String(raw || '').replace(/\s+/g,' ').replace(/^[-•·]+|[-•·]+$/g,'').trim();
      }

      function pushNetworkSubtitle(label, language, index, source) {
        let l = normalizeSubtitleLabel(label);
        let lang = String(language || '').trim();
        if (!l && lang) l = languageName(lang);
        if (!l && !lang) return;
        if (/^(subtitles?|captions?|closed captions?|cc|off|none|default|auto|settings?|back|close|done)$/i.test(l)) return;
        if (l.length > 90) return;
        const key = (l + '|' + lang + '|' + String(index)).toLowerCase();
        if (networkSubtitleSeen.has(key)) return;
        networkSubtitleSeen.add(key);
        networkSubtitleItems.push({id:'network-'+networkSubtitleItems.length,index:index,label:l,language:lang,source:source || 'network'});
      }

      function inspectSubtitlePayload(value, path, depth) {
        if (depth > 7 || value == null) return;
        const p = String(path || '').toLowerCase();
        if (Array.isArray(value)) {
          const subtitleContext = /sub|caption|track|language|translation/.test(p);
          value.forEach((item,i) => {
            if (item && typeof item === 'object') {
              const kind = String(item.kind || item.type || item.category || '').toLowerCase();
              const label = item.label || item.name || item.title || item.displayName || item.languageName || '';
              const lang = item.language || item.lang || item.srclang || item.code || item.locale || '';
              const hasSubtitleShape = subtitleContext || /sub|caption/.test(kind) || ('file' in item && (label || lang)) || ('src' in item && (label || lang)) || ('url' in item && (label || lang));
              if (hasSubtitleShape && (label || lang)) pushNetworkSubtitle(label, lang, i, 'network');
            } else if (subtitleContext && typeof item === 'string' && item.length < 80) {
              pushNetworkSubtitle(item, '', i, 'network');
            }
            inspectSubtitlePayload(item, p + '[' + i + ']', depth + 1);
          });
          return;
        }
        if (typeof value === 'object') {
          Object.keys(value).forEach(k => inspectSubtitlePayload(value[k], p ? p + '.' + k : k, depth + 1));
        }
      }

      function publishNetworkSubtitles() {
        if (networkSubtitleItems.length) bridge({event:'xs:subtitles',items:networkSubtitleItems,final:false});
      }

      function installSubtitleNetworkObserver() {
        try {
          if (!window.__xsFetchHook && typeof window.fetch === 'function') {
            window.__xsFetchHook = true;
            const originalFetch = window.fetch.bind(window);
            window.fetch = function() {
              return originalFetch.apply(window, arguments).then(resp => {
                try {
                  const clone = resp.clone();
                  const ct = String(clone.headers.get('content-type') || '').toLowerCase();
                  const url = String(resp.url || '').toLowerCase();
                  if (ct.includes('json') || /sub|caption|track|language/.test(url)) {
                    clone.text().then(raw => {
                      try {
                        const parsed = JSON.parse(raw);
                        inspectSubtitlePayload(parsed, url, 0);
                        publishNetworkSubtitles();
                      } catch (_) {}
                    }).catch(()=>{});
                  }
                } catch (_) {}
                return resp;
              });
            };
          }
        } catch (_) {}

        try {
          if (!window.__xsXHRHook && window.XMLHttpRequest) {
            window.__xsXHRHook = true;
            const originalOpen = XMLHttpRequest.prototype.open;
            const originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method,url) {
              try { this.__xsURL = String(url || ''); } catch (_) {}
              return originalOpen.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
              try {
                this.addEventListener('load', function() {
                  try {
                    const url = String(this.__xsURL || '').toLowerCase();
                    const ct = String(this.getResponseHeader('content-type') || '').toLowerCase();
                    if (ct.includes('json') || /sub|caption|track|language/.test(url)) {
                      const raw = typeof this.responseText === 'string' ? this.responseText : '';
                      if (raw) {
                        const parsed = JSON.parse(raw);
                        inspectSubtitlePayload(parsed, url, 0);
                        publishNetworkSubtitles();
                      }
                    }
                  } catch (_) {}
                });
              } catch (_) {}
              return originalSend.apply(this, arguments);
            };
          }
        } catch (_) {}
      }

      function scanSubtitles(finalPass) {
        const items = [];
        const seen = new Set();
        const v = video || findVideo();

        function add(id,index,label,language,source) {
          let l = normalizeSubtitleLabel(label);
          let lang = String(language || '').trim();
          if (!l && lang) l = languageName(lang);
          if (!l && !lang) return;
          if (/^(subtitles?|captions?|closed captions?|cc|off|none|default|auto|settings?|back|close|done)$/i.test(l)) return;
          if (l.length > 90) return;
          const key = (l + '|' + lang).toLowerCase();
          if (seen.has(key)) return;
          seen.add(key);
          items.push({id:String(id),index:index,label:l,language:lang,source:source});
        }

        networkSubtitleItems.forEach(it => add(it.id,it.index,it.label,it.language,it.source));

        try {
          if (v && v.textTracks) {
            for (let i=0;i<v.textTracks.length;i++) {
              const t = v.textTracks[i];
              add('track-'+i,i,t.label || '',t.language || '','textTrack');
            }
          }
        } catch (_) {}

        try {
          Array.from(document.querySelectorAll('track[kind="subtitles"],track[kind="captions"]')).forEach((t,i) => {
            add('tag-'+i,i,t.getAttribute('label') || '',t.getAttribute('srclang') || '','trackTag');
          });
        } catch (_) {}

        try {
          const roots = Array.from(document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="subtitle" i],[class*="caption" i],[data-subtitles],[data-captions]'));
          roots.forEach((root,ri) => {
            Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label,[data-language],[lang]')).forEach((el,i) => {
              const label = normalizeSubtitleLabel(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('data-language') || el.getAttribute('lang'));
              const lang = el.getAttribute('data-language') || el.getAttribute('lang') || '';
              if (label || lang) add('menu-'+ri+'-'+i,null,label,lang,'dom');
            });
          });
        } catch (_) {}

        bridge({event:'xs:subtitles',items:items,final:!!finalPass});
      }
'''
text = text[:start] + scanner + text[end:]

old_start = text.find('      function openSubtitleMenu() {')
old_end = text.find('\n      function selectByText', old_start)
if old_start == -1 or old_end == -1:
    raise SystemExit('openSubtitleMenu bounds not found')
open_sub = r'''      function openSubtitleMenu() {
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],[aria-label],[title]'));
          const found = nodes.find(el => {
            const meta = (String(el.getAttribute('aria-label') || '') + ' ' + String(el.getAttribute('title') || '') + ' ' + String(el.getAttribute('data-testid') || '') + ' ' + String(el.getAttribute('class') || '') + ' ' + String(el.innerHTML || '') + ' ' + cleanText(el)).toLowerCase();
            return /subtitle|caption|closed.?caption|\bcc\b|speech|message/.test(meta);
          });
          if (found) { found.click(); return true; }
        } catch (_) {}
        try {
          const x = Math.max(1, window.innerWidth * 0.82);
          const y = Math.max(1, window.innerHeight * 0.91);
          let el = document.elementFromPoint(x,y);
          if (el) {
            el = el.closest('button,[role="button"],a') || el;
            if (el && typeof el.click === 'function') { el.click(); return true; }
          }
        } catch (_) {}
        return false;
      }
'''
text = text[:old_start] + open_sub + text[old_end:]

pos = text.find('      function hideChrome() {')
if pos == -1:
    raise SystemExit('hideChrome marker not found')
helper = r'''      function hideSourcePanels() {
        try {
          Array.from(document.querySelectorAll('body *')).forEach(el => {
            const t = cleanText(el);
            if (!t || t.length > 120) return;
            if (/^SELECT SERVER$/i.test(t) || /^SELECT SUBTITLE/i.test(t) || /^SUBTITLES$/i.test(t) || /^CAPTIONS$/i.test(t)) {
              let p = el;
              for (let i=0;i<6 && p;i++,p=p.parentElement) {
                const r = p.getBoundingClientRect ? p.getBoundingClientRect() : null;
                if (r && r.width > window.innerWidth*0.25 && r.height > window.innerHeight*0.20) {
                  p.style.setProperty('opacity','0','important');
                  p.style.setProperty('pointer-events','none','important');
                  p.style.setProperty('visibility','hidden','important');
                  break;
                }
              }
            }
          });
        } catch (_) {}
      }

'''
text = text[:pos] + helper + text[pos:]

# Ensure hideChrome suppresses any source modal shell every pass.
hide_end = '''        } catch (_) {}\n      }\n\n      function reportState() {'''
if hide_end in text:
    text = text.replace(hide_end, '''        } catch (_) {}\n        hideSourcePanels();\n      }\n\n      function reportState() {''', 1)

old_start = text.find('      function openAndScanSubtitles() {')
old_end = text.find('\n      function reportCaption', old_start)
if old_start == -1 or old_end == -1:
    raise SystemExit('openAndScanSubtitles bounds not found')
open_scan = r'''      function openAndScanSubtitles() {
        installSubtitleNetworkObserver();
        scanSubtitles(false);
        openSubtitleMenu();
        setTimeout(() => { hideSourcePanels(); scanSubtitles(false); },250);
        setTimeout(() => { hideSourcePanels(); scanSubtitles(false); },700);
        setTimeout(() => { hideSourcePanels(); scanSubtitles(false); },1400);
        setTimeout(() => { hideSourcePanels(); scanSubtitles(false); },2300);
        setTimeout(() => { hideSourcePanels(); scanSubtitles(true); },3400);
      }
'''
text = text[:old_start] + open_scan + text[old_end:]

old_observer = '''      new MutationObserver(() => {
        const v = findVideo();
        if (v) install(v);
        if (video) hideChrome();
      }).observe(document.documentElement || document.body,{subtree:true,childList:true});
'''
new_observer = '''      installSubtitleNetworkObserver();
      new MutationObserver(() => {
        const v = findVideo();
        if (v) install(v);
        if (video) hideChrome();
        hideSourcePanels();
      }).observe(document.documentElement || document.body,{subtree:true,childList:true});
'''
if old_observer not in text:
    raise SystemExit('actual mutation observer marker not found')
text = text.replace(old_observer, new_observer, 1)

old_server = '''          else if (action === 'server') {
            const name = String(payload.name || '');
            if (name && name.toLowerCase() !== 'auto') {
              if (selectByText(name)) {
                setTimeout(scanServers,350);
                setTimeout(scanServers,900);
              } else {
                openServerMenu();
                setTimeout(() => {
                  selectByText(name);
                  setTimeout(scanServers,350);
                  setTimeout(scanServers,900);
                },180);
              }
            }
          }
'''
new_server = '''          else if (action === 'server') {
            const name = String(payload.name || '');
            if (name && name.toLowerCase() !== 'auto') {
              const trySelect = (attempt) => {
                let clicked = selectByText(name);
                if (!clicked) { openServerMenu(); hideSourcePanels(); }
                setTimeout(() => {
                  if (!clicked) clicked = selectByText(name);
                  hideSourcePanels();
                  setTimeout(() => {
                    scanServers();
                    const rows = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div'));
                    const confirmed = rows.some(el => {
                      const row = parseServerRow(cleanText(el));
                      return row && row.selected && row.name.toLowerCase() === name.toLowerCase();
                    });
                    if (!confirmed && attempt < 2) trySelect(attempt + 1);
                  },420);
                },180);
              };
              trySelect(0);
            }
          }
'''
if old_server not in text:
    raise SystemExit('server command block not found')
text = text.replace(old_server, new_server, 1)

old_sub = '''            if (v && v.textTracks && subtitleIndex >= 0 && subtitleIndex < v.textTracks.length) {
              for (let i=0;i<v.textTracks.length;i++) {
                try { v.textTracks[i].mode = i === subtitleIndex ? 'hidden' : 'disabled'; } catch (_) {}
              }
              try { window.postMessage({action:'setSubtitle',index:subtitleIndex},'*'); } catch (_) {}
              bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
            } else if (selectedDomSubtitle) {
'''
new_sub = '''            if (subtitleIndex >= 0) {
              if (v && v.textTracks && subtitleIndex < v.textTracks.length) {
                for (let i=0;i<v.textTracks.length;i++) {
                  try { v.textTracks[i].mode = i === subtitleIndex ? 'hidden' : 'disabled'; } catch (_) {}
                }
              }
              try { window.postMessage({action:'setSubtitle',index:subtitleIndex},'*'); } catch (_) {}
              bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
            } else if (selectedDomSubtitle) {
'''
if old_sub not in text:
    raise SystemExit('subtitle command block not found')
text = text.replace(old_sub, new_sub, 1)

path.write_text(text)
print('Applied XS Player V11 network subtitle + reliable server fix')
