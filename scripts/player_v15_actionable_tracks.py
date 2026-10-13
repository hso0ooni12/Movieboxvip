from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V15: stop exposing decorative subtitle/server rows. Every row now points to a concrete
# live control in the owning FrameXTV frame, or to a captured subtitle asset that XS can
# actually mount. Native selection state changes only after the source confirms success.

# Swift: don't optimistically select subtitles.
start = text.find('    func selectSubtitle(_ option: XSSubtitleOption?) {')
end = text.find('\n    func selectServer(', start)
if start == -1 or end == -1:
    raise SystemExit('V15 Swift selectSubtitle bounds not found')
text = text[:start] + '''    func selectSubtitle(_ option: XSSubtitleOption?) {
        if let option {
            send([
                "action": "subtitle",
                "id": option.id,
                "index": option.sourceIndex ?? -1,
                "label": option.label,
                "language": option.language,
                "source": option.source
            ])
        } else {
            send(["action": "subtitle", "id": "off", "index": -1, "source": "off"])
        }
    }
''' + text[end:]

# Swift: send exact server id so JS can target the live row, not search by name.
start = text.find('    func selectServer(_ server: XSServerOption) {')
end = text.find('\n    func selectQuality(', start)
if start == -1 or end == -1:
    raise SystemExit('V15 Swift selectServer bounds not found')
text = text[:start] + '''    func selectServer(_ server: XSServerOption) {
        if activeServerName.caseInsensitiveCompare(server.name) == .orderedSame { return }
        captionText = ""
        subtitleOptions = []
        selectedSubtitleID = nil
        var payload: [String: Any] = ["action": "server", "id": server.id, "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
''' + text[end:]

# Swift: honor confirmed subtitle activation only.
default_marker = '        default:\n            break\n'
if default_marker not in text:
    raise SystemExit('V15 receive default marker not found')
if 'case "xs:subtitleSelected":' not in text:
    cases = '''        case "xs:subtitleSelected":
            selectedSubtitleID = payload["id"] as? String
            errorMessage = nil

        case "xs:subtitleSelectionFailed":
            errorMessage = "That subtitle could not be activated on this server."

'''
    text = text.replace(default_marker, cases + default_marker, 1)

# JS helper: clickable controls registry scoped to this exact injected frame.
anchor = "      let selectedDomSubtitle = '';\n"
registry = "      let selectedDomSubtitle = '';\n      const xsLiveSubtitleRows = new Map();\n      const xsLiveServerRows = new Map();\n      let xsRowCounter = 0;\n      function xsNextKey(prefix){ xsRowCounter += 1; return xsFrameId+'::'+prefix+'-'+xsRowCounter; }\n"
if anchor not in text:
    raise SystemExit('V15 JS registry anchor not found')
text = text.replace(anchor, registry, 1)

# Replace scanSubtitles with an actionable-only scanner.
start = text.find('      function scanSubtitles(')
end = text.find('\n      function parseServerRow', start)
if start == -1 or end == -1:
    raise SystemExit('V15 scanSubtitles bounds not found')
scan_sub = r'''      function xsSubtitleLooksSelected(el) {
        try {
          const meta = [el.getAttribute('aria-checked'),el.getAttribute('aria-selected'),el.getAttribute('data-selected'),el.getAttribute('data-active')].join(' ').toLowerCase();
          if (/true|selected|active|checked/.test(meta)) return true;
          const cls = String(el.className || '').toLowerCase();
          if (/selected|active|checked|current/.test(cls)) return true;
          const txt = cleanText(el);
          return /✓|✔|selected/i.test(txt);
        } catch (_) { return false; }
      }

      function scanSubtitles(finalPass) {
        const items = [];
        const seen = new Set();
        xsLiveSubtitleRows.clear();
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

        // 1) Direct HTML tracks are always actionable.
        try {
          if (v && v.textTracks) {
            for (let i=0;i<v.textTracks.length;i++) {
              const t = v.textTracks[i];
              add(xsFrameId+'::track-'+i,i,t.label || '',t.language || '','textTrack');
            }
          }
        } catch (_) {}

        // 2) Captured network assets are actionable only when we actually have a URL/body.
        try {
          networkSubtitleItems.forEach(it => {
            if (it && (it.assetURL || it.rawText)) add(it.id,it.index,it.label,it.language,'networkAsset');
          });
        } catch (_) {}

        // 3) Live source-menu rows. Store the exact clickable element behind a stable key.
        try {
          const roots = Array.from(document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="subtitle" i],[class*="caption" i],[data-subtitles],[data-captions]'));
          roots.forEach(root => {
            Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label')).forEach(el => {
              const label = normalizeSubtitleLabel(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('data-language') || el.getAttribute('lang'));
              const lang = el.getAttribute('data-language') || el.getAttribute('lang') || '';
              if (!label && !lang) return;
              if (/^(off|none|subtitles?|captions?|closed captions?|cc|settings?|back|close|done)$/i.test(label)) return;
              const key = xsNextKey('subrow');
              xsLiveSubtitleRows.set(key, el);
              add(key,null,label,lang,'liveDom');
            });
          });
        } catch (_) {}

        bridge({event:'xs:subtitles',items:items,final:!!finalPass});
      }
'''
text = text[:start] + scan_sub + text[end:]

# Improve network capture: preserve raw subtitle bodies when the actual subtitle file is fetched.
# Patch fetch observer's clone.text handler broadly.
needle = "                  if (ct.includes('json') || /sub|caption|track|language/.test(url)) {\n                    clone.text().then(raw => {\n                      try {\n                        const parsed = JSON.parse(raw);\n                        inspectSubtitlePayload(parsed, url, 0);\n                        publishNetworkSubtitles();\n                      } catch (_) {}\n                    }).catch(()=>{});\n                  }"
replacement = """                  if (ct.includes('json') || /sub|caption|track|language|\\.vtt|\\.srt|\\.ass/.test(url)) {\n                    clone.text().then(raw => {\n                      try {\n                        if (/WEBVTT|-->/.test(raw) || /\\.vtt|\\.srt/.test(url)) {\n                          const guessed = (url.split('/').pop() || 'Subtitle').split('?')[0];\n                          const item = {id:xsFrameId+'::raw-'+networkSubtitleItems.length,index:null,label:guessed,language:'',source:'networkAsset',assetURL:String(resp.url || ''),rawText:raw};\n                          networkSubtitleItems.push(item);\n                          publishNetworkSubtitles();\n                        } else {\n                          const parsed = JSON.parse(raw);\n                          inspectSubtitlePayload(parsed, url, 0);\n                          publishNetworkSubtitles();\n                        }\n                      } catch (_) {}\n                    }).catch(()=>{});\n                  }"""
if needle in text:
    text = text.replace(needle, replacement, 1)

# Replace subtitle command with exact actionable target activation + confirmation.
start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V15 subtitle command bounds not found')
subtitle_block = r'''          else if (action === 'subtitle') {
            const source = String(payload.source || '').toLowerCase();
            const wantedID = String(payload.id || '');
            const wantedFrame = wantedID.includes('::') ? wantedID.split('::')[0] : '';
            if (wantedID !== 'off' && wantedFrame && wantedFrame !== xsFrameId) return;
            const idx = Number(payload.index);
            const vNow = video || findVideo();

            function clearAllSubtitleRenderers() {
              subtitleIndex = -1; selectedDomSubtitle=''; lastCaption='';
              try {
                const old=document.getElementById('xs-managed-subtitle'); if(old) old.remove();
                if (window.__xsSubtitleBlobURL) { try{URL.revokeObjectURL(window.__xsSubtitleBlobURL)}catch(_){} window.__xsSubtitleBlobURL=null; }
                if(vNow && vNow.textTracks) for(let i=0;i<vNow.textTracks.length;i++) try{vNow.textTracks[i].mode='disabled'}catch(_){}
              } catch(_){}
              try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch(_){}
              bridge({event:'xs:caption',text:''});
            }

            function confirmLiveRow(el, id, attempts) {
              if (!el) { bridge({event:'xs:subtitleSelectionFailed',id:id}); return; }
              if (xsSubtitleLooksSelected(el)) { bridge({event:'xs:subtitleSelected',id:id}); return; }
              const vn = video || findVideo();
              try {
                if (vn && vn.textTracks) {
                  for(let i=0;i<vn.textTracks.length;i++) if(vn.textTracks[i].mode==='showing' || vn.textTracks[i].mode==='hidden') { bridge({event:'xs:subtitleSelected',id:id}); return; }
                }
              } catch(_){}
              if (attempts < 8) setTimeout(()=>confirmLiveRow(el,id,attempts+1),180);
              else bridge({event:'xs:subtitleSelectionFailed',id:id});
            }

            function toVTT(raw){
              let body=String(raw||'').replace(/\r/g,'').trim(); if(!body) return '';
              if(/^WEBVTT/i.test(body)) return body;
              if(!body.includes('-->')) return '';
              body=body.replace(/(\d{1,2}:\d{2}:\d{2}),(\d{3})/g,'$1.$2');
              return 'WEBVTT\n\n'+body;
            }

            async function mountAsset(item){
              if(!vNow || !item) return false;
              let raw=String(item.rawText||'');
              if(!raw && item.assetURL){
                try{ const r=await fetch(new URL(String(item.assetURL),document.baseURI||location.href).href,{credentials:'include'}); if(!r.ok) return false; raw=await r.text(); }catch(_){return false;}
              }
              const vtt=toVTT(raw); if(!vtt) return false;
              clearAllSubtitleRenderers();
              const blob=new Blob([vtt],{type:'text/vtt;charset=utf-8'}); const url=URL.createObjectURL(blob); window.__xsSubtitleBlobURL=url;
              const tr=document.createElement('track'); tr.id='xs-managed-subtitle'; tr.kind='subtitles'; tr.label=item.label||'Subtitle'; tr.srclang=item.language||'und'; tr.src=url; tr.default=true; vNow.appendChild(tr);
              await new Promise(resolve=>{let done=false; const f=()=>{if(done)return;done=true;resolve()}; tr.addEventListener('load',f,{once:true}); setTimeout(f,700)});
              try{ if(vNow.textTracks) for(let i=0;i<vNow.textTracks.length;i++) vNow.textTracks[i].mode='disabled'; if(tr.track) tr.track.mode='showing'; }catch(_){}
              return !!(tr.track && (tr.track.mode==='showing' || tr.track.cues));
            }

            if(source==='off' || wantedID==='off'){
              clearAllSubtitleRenderers();
              openSubtitleMenu(); setTimeout(()=>{selectByText('Off'); bridge({event:'xs:subtitleSelected',id:'off'})},120);
            }
            else if(source==='livedom'){
              const el=xsLiveSubtitleRows.get(wantedID);
              if(!el){bridge({event:'xs:subtitleSelectionFailed',id:wantedID});}
              else{
                clearAllSubtitleRenderers();
                try{ const click=el.closest('button,[role="button"],[role="menuitem"],[role="option"],li')||el; click.click(); }catch(_){bridge({event:'xs:subtitleSelectionFailed',id:wantedID}); return;}
                setTimeout(()=>confirmLiveRow(el,wantedID,0),120);
              }
            }
            else if(source==='networkasset'){
              const item=networkSubtitleItems.find(x=>String(x.id)===wantedID);
              mountAsset(item).then(ok=>bridge({event:ok?'xs:subtitleSelected':'xs:subtitleSelectionFailed',id:wantedID}));
            }
            else if((source==='texttrack' || source==='tracktag') && Number.isFinite(idx) && idx>=0 && vNow && vNow.textTracks && idx<vNow.textTracks.length){
              clearAllSubtitleRenderers(); subtitleIndex=idx;
              try{vNow.textTracks[idx].mode='showing'}catch(_){}
              setTimeout(()=>{const ok=vNow.textTracks[idx].mode==='showing'||vNow.textTracks[idx].mode==='hidden'; bridge({event:ok?'xs:subtitleSelected':'xs:subtitleSelectionFailed',id:wantedID})},120);
            }
            else bridge({event:'xs:subtitleSelectionFailed',id:wantedID});
          }
'''
text = text[:start] + subtitle_block + text[end:]

# Replace server scan with exact live-row ids.
start = text.find('      function scanServers() {')
end = text.find('\n      function openServerMenu()', start)
if start == -1 or end == -1:
    raise SystemExit('V15 scanServers bounds not found')
server_scan = r'''      function scanServers() {
        const out=[]; const seen=new Set(); xsLiveServerRows.clear();
        try{
          const roots=Array.from(document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="server" i],[class*="source" i],[class*="provider" i]'));
          const nodes=roots.length ? roots.flatMap(r=>Array.from(r.querySelectorAll('button,[role="button"],[role="menuitem"],li'))) : Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li'));
          nodes.forEach(el=>{
            const row=parseServerRow(cleanText(el)); if(!row) return;
            const key=row.name.toLowerCase(); if(seen.has(key)) return; seen.add(key);
            const id=xsNextKey('server'); xsLiveServerRows.set(id,el);
            out.push({id:id,name:row.name,quality:row.quality,provider:null,selected:row.selected});
          });
        }catch(_){}
        if(out.length) bridge({event:'xs:servers',items:out});
      }
'''
text = text[:start] + server_scan + text[end:]

# Swift server parser should preserve id coming from JS.
old = '                return .init(id: (provider ?? name) + quality, name: name, quality: quality, provider: provider, selected: selected)\n'
new = '                let id = row["id"] as? String ?? ((provider ?? name) + quality)\n                return .init(id: id, name: name, quality: quality, provider: provider, selected: selected)\n'
if old not in text:
    raise SystemExit('V15 Swift server id marker not found')
text = text.replace(old, new, 1)

# Replace server command with exact live row activation + confirmed connected state.
start = text.find("          else if (action === 'server') {")
end = text.find("\n          else if (action === 'metadata') {", start)
if start == -1 or end == -1:
    raise SystemExit('V15 server command bounds not found')
server_block = r'''          else if (action === 'server') {
            const wantedID=String(payload.id||''); const name=String(payload.name||'').trim();
            const wantedFrame=wantedID.includes('::')?wantedID.split('::')[0]:'';
            if(wantedFrame && wantedFrame!==xsFrameId) return;
            const el=xsLiveServerRows.get(wantedID);
            if(!el){bridge({event:'xs:serverSwitchFailed',name:name}); return;}
            const currentVideo=video||findVideo(); const resume= currentVideo ? Number(currentVideo.currentTime||0):0; const shouldPlay=currentVideo ? !currentVideo.paused:true;
            try{const click=el.closest('button,[role="button"],[role="menuitem"],li')||el; click.click();}catch(_){bridge({event:'xs:serverSwitchFailed',name:name});return;}
            let tries=0;
            const verify=()=>{
              tries+=1; scanServers();
              const selected=Array.from(xsLiveServerRows.values()).some(node=>{const r=parseServerRow(cleanText(node));return r&&r.selected&&r.name.toLowerCase()===name.toLowerCase()});
              if(selected){
                setTimeout(()=>{const nv=video||findVideo(); if(nv&&nv.readyState>=2){try{if(resume>0&&Math.abs(Number(nv.currentTime||0)-resume)>2)nv.currentTime=resume}catch(_){} if(shouldPlay)try{nv.play()}catch(_){}}},250);
                if(typeof networkSubtitleItems!=='undefined') networkSubtitleItems.length=0; if(typeof networkSubtitleSeen!=='undefined'&&networkSubtitleSeen.clear) networkSubtitleSeen.clear();
                setTimeout(()=>openAndScanSubtitles(),450);
                bridge({event:'xs:serverSwitchConfirmed',name:name});
              } else if(tries<10) setTimeout(verify,220);
              else bridge({event:'xs:serverSwitchFailed',name:name});
            };
            setTimeout(verify,180);
          }
'''
text = text[:start] + server_block + text[end:]

path.write_text(text)
print('Applied XS Player V15 actionable subtitles and exact server rows')
