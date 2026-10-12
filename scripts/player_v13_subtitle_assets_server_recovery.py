from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V13: only show real discovered servers. AUTO belongs to quality, not the server list.
old_servers = '''    @Published var servers: [XSServerOption] = [
        .init(id: "auto", name: "Auto", quality: "AUTO", provider: "auto", selected: true)
    ]
'''
if old_servers in text:
    text = text.replace(old_servers, '    @Published var servers: [XSServerOption] = []\n', 1)

# Do not optimistically mark a server active. The bridge must confirm Connected first.
old_select_server = '''    func selectServer(_ server: XSServerOption) {
        activeServerName = server.name
        if !server.quality.isEmpty { activeQuality = server.quality }
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
'''
new_select_server = '''    func selectServer(_ server: XSServerOption) {
        captionText = ""
        subtitleOptions = []
        selectedSubtitleID = nil
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
'''
if old_select_server not in text:
    raise SystemExit('V13 selectServer marker not found')
text = text.replace(old_select_server, new_select_server, 1)

# Prefer an actionable subtitle asset or a direct HTML textTrack over DOM/network metadata.
old_priority = '''        func priority(_ source: String) -> Int {
            switch source.lowercased() {
            case "dom": return 40
            case "texttrack": return 30
            case "tracktag": return 25
            case "network": return 10
            default: return 0
            }
        }
'''
new_priority = '''        func priority(_ source: String) -> Int {
            switch source.lowercased() {
            case "networkasset": return 70
            case "texttrack": return 60
            case "tracktag": return 55
            case "dom": return 40
            case "network": return 10
            default: return 0
            }
        }
'''
if old_priority not in text:
    raise SystemExit('V13 subtitle priority marker not found')
text = text.replace(old_priority, new_priority, 1)

# Keep the actual subtitle asset URL discovered from FrameXTV metadata in JS memory.
start = text.find('      function pushNetworkSubtitle(')
end = text.find('\n      function inspectSubtitlePayload', start)
if start == -1 or end == -1:
    raise SystemExit('V13 pushNetworkSubtitle bounds not found')
new_push = r'''      function pushNetworkSubtitle(label, language, index, source, assetURL) {
        let l = normalizeSubtitleLabel(label);
        let lang = String(language || '').trim();
        let asset = String(assetURL || '').trim();
        if (!l && lang) l = languageName(lang);
        if (!l && !lang) return;
        if (/^(subtitles?|captions?|closed captions?|cc|off|none|default|auto|settings?|back|close|done)$/i.test(l)) return;
        if (l.length > 90) return;
        const key = (l + '|' + lang + '|' + asset).toLowerCase();
        if (networkSubtitleSeen.has(key)) return;
        networkSubtitleSeen.add(key);
        networkSubtitleItems.push({
          id:'network-'+networkSubtitleItems.length,
          index:index,
          label:l,
          language:lang,
          source:asset ? 'networkAsset' : (source || 'network'),
          assetURL:asset
        });
      }
'''
text = text[:start] + new_push + text[end:]

# Attach file/src/url metadata to each network subtitle option instead of trusting its array index.
old_obj_call = "              if (hasSubtitleShape && (label || lang)) pushNetworkSubtitle(label, lang, i, 'network');"
new_obj_call = "              if (hasSubtitleShape && (label || lang)) { const asset = item.url || item.src || item.file || item.path || item.uri || item.subtitleUrl || item.subtitle_url || item.download || ''; pushNetworkSubtitle(label, lang, i, 'network', asset); }"
if old_obj_call not in text:
    raise SystemExit('V13 network object subtitle call not found')
text = text.replace(old_obj_call, new_obj_call, 1)
text = text.replace("              pushNetworkSubtitle(item, '', i, 'network');", "              pushNetworkSubtitle(item, '', i, 'network', '');", 1)

# Replace subtitle selection with one-renderer-only logic. Direct subtitle assets are mounted as one HTML track.
start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V13 subtitle command bounds not found')
subtitle_block = r'''          else if (action === 'subtitle') {
            const source = String(payload.source || '').toLowerCase();
            const label = String(payload.label || '').trim();
            const language = String(payload.language || '').trim();
            const idx = Number(payload.index);
            const wantedID = String(payload.id || '');

            function clearManagedSubtitle() {
              subtitleIndex = -1;
              selectedDomSubtitle = '';
              lastCaption = '';
              try {
                const old = document.getElementById('xs-managed-subtitle');
                if (old) old.remove();
                if (window.__xsSubtitleBlobURL) {
                  try { URL.revokeObjectURL(window.__xsSubtitleBlobURL); } catch (_) {}
                  window.__xsSubtitleBlobURL = null;
                }
                if (v && v.textTracks) {
                  for (let i=0;i<v.textTracks.length;i++) {
                    try { v.textTracks[i].mode='disabled'; } catch (_) {}
                  }
                }
              } catch (_) {}
              bridge({event:'xs:caption',text:''});
            }

            function langAliases(value) {
              const r = String(value || '').toLowerCase().trim();
              const groups = [
                ['ar','ara','arabic','العربية','عربي'],['en','eng','english'],['fi','fin','finnish'],
                ['es','spa','spanish','español'],['fr','fra','french','français'],['de','deu','german','deutsch'],
                ['it','ita','italian','italiano'],['pt','por','portuguese','português'],['tr','tur','turkish','türkçe'],
                ['ru','rus','russian','русский'],['ja','jpn','japanese','日本語'],['ko','kor','korean','한국어'],
                ['zh','zho','chinese','中文']
              ];
              for (const g of groups) if (g.some(x => r === x || (x.length > 2 && r.includes(x)))) return g;
              return r ? [r] : [];
            }

            function chooseSourceSubtitle(wantedLabel,wantedLanguage) {
              const labelNorm = normalizeSubtitleLabel(wantedLabel).toLowerCase();
              const aliases = Array.from(new Set([...langAliases(wantedLanguage), ...langAliases(wantedLabel)]));
              const nodes = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label'));
              let best = null, bestScore = -1;
              for (const el of nodes) {
                const t = normalizeSubtitleLabel(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title')).toLowerCase();
                if (!t || /^(off|none|subtitles?|captions?|cc|settings?|back|close|done)$/i.test(t)) continue;
                let score = 0;
                if (labelNorm && t === labelNorm) score = 100;
                else if (labelNorm && (t.includes(labelNorm) || labelNorm.includes(t))) score = 85;
                for (const a of aliases) {
                  if (!a) continue;
                  if (t === a) score = Math.max(score,98);
                  else if (a.length > 1 && (t.includes(a) || a.includes(t))) score = Math.max(score,90);
                }
                if (score > bestScore) { bestScore=score; best=el; }
              }
              if (best && bestScore >= 80) {
                const clickable = best.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || best;
                try {
                  ['pointerdown','mousedown','pointerup','mouseup'].forEach(type => clickable.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:window})));
                } catch (_) {}
                clickable.click();
                return true;
              }
              return false;
            }

            function toWebVTT(raw) {
              let body = String(raw || '').replace(/\r/g,'').trim();
              if (!body) return '';
              if (/^WEBVTT/i.test(body)) return body;
              if (!body.includes('-->')) return '';
              body = body.replace(/(\d{1,2}:\d{2}:\d{2}),(\d{3})/g,'$1.$2');
              return 'WEBVTT\n\n' + body;
            }

            async function mountNetworkSubtitle(item) {
              if (!item || !item.assetURL || !v) return false;
              try {
                const resolved = new URL(String(item.assetURL), document.baseURI || location.href).href;
                const response = await fetch(resolved,{credentials:'include'});
                if (!response.ok) return false;
                const raw = await response.text();
                const vtt = toWebVTT(raw);
                if (!vtt) return false;

                clearManagedSubtitle();
                try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch (_) {}

                const blob = new Blob([vtt],{type:'text/vtt;charset=utf-8'});
                const blobURL = URL.createObjectURL(blob);
                window.__xsSubtitleBlobURL = blobURL;
                const track = document.createElement('track');
                track.id = 'xs-managed-subtitle';
                track.kind = 'subtitles';
                track.label = item.label || label || 'Subtitle';
                track.srclang = item.language || language || 'und';
                track.src = blobURL;
                track.default = true;
                v.appendChild(track);

                const enable = () => {
                  try {
                    if (v.textTracks) {
                      for (let i=0;i<v.textTracks.length;i++) v.textTracks[i].mode='disabled';
                    }
                    if (track.track) track.track.mode='showing';
                  } catch (_) {}
                  applySubtitleStyle();
                  bridge({event:'xs:subtitleSelected',id:wantedID});
                };
                track.addEventListener('load', enable, {once:true});
                setTimeout(enable,500);
                return true;
              } catch (_) { return false; }
            }

            // There must be exactly one subtitle renderer at a time.
            clearManagedSubtitle();
            try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch (_) {}

            if (source === 'off' || wantedID === 'off') {
              openSubtitleMenu();
              setTimeout(() => selectByText('Off'),120);
              bridge({event:'xs:subtitleSelected',id:'off'});
            }
            else {
              const networkItem = (typeof networkSubtitleItems !== 'undefined') ? networkSubtitleItems.find(x => String(x.id) === wantedID) : null;
              if (networkItem && networkItem.assetURL) {
                mountNetworkSubtitle(networkItem).then(ok => {
                  if (ok) return;
                  openSubtitleMenu();
                  setTimeout(() => {
                    hideSourcePanels();
                    if (chooseSourceSubtitle(label,language)) bridge({event:'xs:subtitleSelected',id:wantedID});
                    else bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:label,language:language});
                  },220);
                });
              }
              else if ((source === 'texttrack' || source === 'tracktag') && Number.isFinite(idx) && idx >= 0 && v && v.textTracks && idx < v.textTracks.length) {
                subtitleIndex = idx;
                try {
                  for (let i=0;i<v.textTracks.length;i++) v.textTracks[i].mode = i === idx ? 'showing' : 'disabled';
                } catch (_) {}
                bridge({event:'xs:subtitleSelected',id:wantedID});
              }
              else {
                openSubtitleMenu();
                setTimeout(() => {
                  hideSourcePanels();
                  let ok = chooseSourceSubtitle(label,language);
                  if (!ok) {
                    openSubtitleMenu();
                    setTimeout(() => {
                      hideSourcePanels();
                      ok = chooseSourceSubtitle(label,language);
                      if (ok) bridge({event:'xs:subtitleSelected',id:wantedID});
                      else bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:label,language:language});
                    },300);
                  } else bridge({event:'xs:subtitleSelected',id:wantedID});
                },220);
              }
            }
          }
'''
text = text[:start] + subtitle_block + text[end:]

# Replace server switching with exact-row activation, confirmation, time preservation, retry and rollback.
start = text.find("          else if (action === 'server') {")
end = text.find("\n          else if (action === 'metadata') {", start)
if start == -1 or end == -1:
    raise SystemExit('V13 server command bounds not found')
server_block = r'''          else if (action === 'server') {
            const name = String(payload.name || '').trim();
            if (name) {
              const currentVideo = video || findVideo();
              const resumeTime = currentVideo ? Number(currentVideo.currentTime || 0) : 0;
              const shouldPlay = currentVideo ? !currentVideo.paused : true;

              function discoveredRows() {
                const out = [];
                const seen = new Set();
                const nodes = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div'));
                for (const el of nodes) {
                  const row = parseServerRow(cleanText(el));
                  if (!row) continue;
                  const key = row.name.toLowerCase();
                  if (seen.has(key)) continue;
                  seen.add(key);
                  out.push({row:row,el:el});
                }
                return out;
              }

              function connectedName() {
                const hit = discoveredRows().find(x => x.row.selected);
                return hit ? hit.row.name : '';
              }

              function activateServer(target) {
                const matches = discoveredRows().filter(x => x.row.name.toLowerCase() === target.toLowerCase());
                if (!matches.length) return false;
                matches.sort((a,b) => cleanText(a.el).length - cleanText(b.el).length);
                const raw = matches[0].el;
                const el = raw.closest('button,[role="button"],[role="menuitem"],li') || raw;
                try {
                  ['pointerdown','mousedown','pointerup','mouseup'].forEach(type => el.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:window})));
                } catch (_) {}
                try { el.click(); } catch (_) { return false; }
                return true;
              }

              function restorePlayback(attempt) {
                const nv = video || findVideo();
                if (nv && nv.readyState >= 2) {
                  try { if (resumeTime > 0 && Math.abs(Number(nv.currentTime || 0)-resumeTime) > 2) nv.currentTime = resumeTime; } catch (_) {}
                  if (shouldPlay) { try { nv.play(); } catch (_) {} }
                  return;
                }
                if (attempt < 12) setTimeout(() => restorePlayback(attempt+1),250);
              }

              const previous = connectedName();
              if (previous && previous.toLowerCase() === name.toLowerCase()) {
                scanServers();
                bridge({event:'xs:serverSwitchConfirmed',name:name});
              } else {
                let tries = 0;
                const trySwitch = () => {
                  tries += 1;
                  let clicked = activateServer(name);
                  if (!clicked) {
                    openServerMenu();
                    hideSourcePanels();
                    setTimeout(() => {
                      clicked = activateServer(name);
                      hideSourcePanels();
                    },180);
                  }

                  setTimeout(() => {
                    scanServers();
                    const connected = connectedName();
                    if (connected && connected.toLowerCase() === name.toLowerCase()) {
                      if (typeof networkSubtitleItems !== 'undefined') networkSubtitleItems.length = 0;
                      if (typeof networkSubtitleSeen !== 'undefined' && networkSubtitleSeen.clear) networkSubtitleSeen.clear();
                      clearManagedSubtitle && clearManagedSubtitle();
                      setTimeout(() => scanSubtitles(false),500);
                      setTimeout(() => scanSubtitles(true),1600);
                      restorePlayback(0);
                      bridge({event:'xs:serverSwitchConfirmed',name:name});
                    } else if (tries < 3) {
                      openServerMenu();
                      hideSourcePanels();
                      setTimeout(trySwitch,350);
                    } else {
                      if (previous && previous.toLowerCase() !== name.toLowerCase()) {
                        openServerMenu();
                        hideSourcePanels();
                        setTimeout(() => {
                          activateServer(previous);
                          setTimeout(() => { scanServers(); restorePlayback(0); },550);
                        },180);
                      }
                      bridge({event:'xs:serverSwitchFailed',name:name,previous:previous});
                    }
                  },700);
                };
                trySwitch();
              }
            }
          }
'''
# clearManagedSubtitle is declared inside subtitle command, so server block cannot call it. Use a safe local cleanup instead.
server_block = server_block.replace("                      clearManagedSubtitle && clearManagedSubtitle();\n", "                      subtitleIndex=-1; selectedDomSubtitle=''; lastCaption=''; try { const old=document.getElementById('xs-managed-subtitle'); if(old) old.remove(); if(window.__xsSubtitleBlobURL){URL.revokeObjectURL(window.__xsSubtitleBlobURL);window.__xsSubtitleBlobURL=null;} } catch(_) {}\n")
text = text[:start] + server_block + text[end:]

path.write_text(text)
print('Applied XS Player V13 subtitle assets + reliable server recovery')
