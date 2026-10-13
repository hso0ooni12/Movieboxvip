from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V23 runs after V21. Tighten subtitle discovery so label/language and subtitle
# URL must belong to the same source object. Remove index fallback entirely.

start = text.find('      let networkSubtitleItems = [];')
end = text.find('\n      function parseServerRow', start)
if start == -1 or end == -1:
    raise SystemExit('V23 network subtitle section not found')

section = r'''      let networkSubtitleItems = [];
      const networkSubtitleSeen = new Set();
      const xsSubtitleBodies = new Map();

      function normalizeSubtitleLabel(raw) {
        return String(raw || '').replace(/\s+/g,' ').replace(/^[-•·]+|[-•·]+$/g,'').trim();
      }

      function xsAbsoluteURL(raw) {
        try { return new URL(String(raw || ''), location.href).href; } catch (_) { return String(raw || ''); }
      }

      function isSubtitleURL(raw) {
        const u = String(raw || '').toLowerCase();
        return !!u && (/\.vtt(?:$|\?)/.test(u) || /\.srt(?:$|\?)/.test(u) || /subtitle|caption|subtitles|captions/.test(u));
      }

      function pushBoundSubtitle(label, language, source, rawURL) {
        const l = normalizeSubtitleLabel(label);
        const lang = String(language || '').trim();
        const url = rawURL ? xsAbsoluteURL(rawURL) : '';
        if ((!l && !lang) || !url) return;
        if (!isSubtitleURL(url)) return;
        if (/^(subtitles?|captions?|closed captions?|cc|off|none|default|auto|settings?|back|close|done)$/i.test(l)) return;
        const key = (l + '|' + lang + '|' + url).toLowerCase();
        if (networkSubtitleSeen.has(key)) return;
        networkSubtitleSeen.add(key);
        networkSubtitleItems.push({
          id:'network-'+networkSubtitleItems.length,
          index:null,
          label:l || lang,
          language:lang,
          source:source || 'network-url',
          url:url
        });
      }

      function inspectSubtitlePayload(value, path, depth) {
        if (depth > 8 || value == null) return;
        const p = String(path || '').toLowerCase();

        if (Array.isArray(value)) {
          value.forEach((item,i) => {
            if (item && typeof item === 'object' && !Array.isArray(item)) {
              const label = item.label || item.name || item.title || item.displayName || item.languageName || '';
              const lang = item.language || item.lang || item.srclang || item.code || item.locale || '';
              const rawURL = item.file || item.src || item.url || item.path || item.subtitle || item.subtitleUrl || item.subtitle_url || item.vtt || item.srt || '';
              const kind = String(item.kind || item.type || item.category || '').toLowerCase();
              const inSubtitleContext = /sub|caption|track|translation/.test(p) || /sub|caption/.test(kind);

              // Important: only bind when label/lang and URL live on this SAME object.
              if (inSubtitleContext && rawURL && (label || lang)) {
                pushBoundSubtitle(label, lang, 'network-object', rawURL);
                return; // do not recursively pair this object's metadata with nested siblings
              }
            }
            inspectSubtitlePayload(item, p + '[' + i + ']', depth + 1);
          });
          return;
        }

        if (typeof value === 'object') {
          const label = value.label || value.name || value.title || value.displayName || value.languageName || '';
          const lang = value.language || value.lang || value.srclang || value.code || value.locale || '';
          const rawURL = value.file || value.src || value.url || value.path || value.subtitle || value.subtitleUrl || value.subtitle_url || value.vtt || value.srt || '';
          const kind = String(value.kind || value.type || value.category || '').toLowerCase();
          const inSubtitleContext = /sub|caption|track|translation/.test(p) || /sub|caption/.test(kind);

          if (inSubtitleContext && rawURL && (label || lang)) {
            pushBoundSubtitle(label, lang, 'network-object', rawURL);
            return;
          }

          // Also support maps like { ara: "...vtt", eng: "...vtt" }.
          Object.keys(value).forEach(k => {
            const child = value[k];
            if (typeof child === 'string' && isSubtitleURL(child) && /sub|caption|track|translation|language/.test(p)) {
              pushBoundSubtitle(k, k, 'network-map', child);
            } else {
              inspectSubtitlePayload(child, p ? p + '.' + k : k, depth + 1);
            }
          });
        }
      }

      function publishNetworkSubtitles(finalPass) {
        const items = [];
        const seen = new Set();
        const add = it => {
          const key = (String(it.label||'')+'|'+String(it.language||'')+'|'+String(it.url||'')).toLowerCase();
          if (seen.has(key)) return;
          seen.add(key);
          items.push(it);
        };

        // Only URL-backed source options plus real HTML textTracks.
        networkSubtitleItems.forEach(add);
        const v = video || findVideo();
        try {
          if (v && v.textTracks) {
            for (let i=0;i<v.textTracks.length;i++) {
              const t=v.textTracks[i];
              const label=normalizeSubtitleLabel(t.label || t.language || '');
              if (!label) continue;
              add({id:'track-'+i,index:i,label:label,language:String(t.language||''),source:'textTrack',url:''});
            }
          }
        } catch (_) {}
        bridge({event:'xs:subtitles',items:items,final:!!finalPass});
      }

      function rememberSubtitleBody(url, raw, contentType) {
        try {
          const u = xsAbsoluteURL(url);
          const body = String(raw || '');
          const ct = String(contentType || '').toLowerCase();
          if (!u || !body) return;
          if (/\.vtt(?:$|\?)/i.test(u) || /\.srt(?:$|\?)/i.test(u) || /text\/vtt|subrip/.test(ct) || /^WEBVTT/m.test(body) || /\d\d:\d\d:\d\d[,\.]\d{3}\s*-->/.test(body)) {
            xsSubtitleBodies.set(u, body);
          }
        } catch (_) {}
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
                  const url = String(resp.url || '');
                  const low = url.toLowerCase();
                  if (ct.includes('json') || /sub|caption|track|language/.test(low)) {
                    clone.text().then(raw => {
                      rememberSubtitleBody(url, raw, ct);
                      try {
                        inspectSubtitlePayload(JSON.parse(raw), low, 0);
                        publishNetworkSubtitles(false);
                      } catch (_) {}
                    }).catch(()=>{});
                  } else if (/\.vtt(?:$|\?)/i.test(low) || /\.srt(?:$|\?)/i.test(low) || /text\/vtt|subrip/.test(ct)) {
                    clone.text().then(raw => rememberSubtitleBody(url, raw, ct)).catch(()=>{});
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
                    const url = String(this.__xsURL || '');
                    const low = url.toLowerCase();
                    const ct = String(this.getResponseHeader('content-type') || '').toLowerCase();
                    const raw = typeof this.responseText === 'string' ? this.responseText : '';
                    if (raw) rememberSubtitleBody(url, raw, ct);
                    if (raw && (ct.includes('json') || /sub|caption|track|language/.test(low))) {
                      try {
                        inspectSubtitlePayload(JSON.parse(raw), low, 0);
                        publishNetworkSubtitles(false);
                      } catch (_) {}
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
        publishNetworkSubtitles(!!finalPass);
      }
'''
text = text[:start] + section + text[end:]

start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V23 subtitle action block not found')

action = r'''          else if (action === 'subtitle') {
            const wantedID = String(payload.id || '');
            const v = video || findVideo();

            function clearAllSubtitleTracks() {
              selectedTrack = -1;
              selectedDomSubtitle = '';
              lastCaption = '';
              bridge({event:'xs:caption',text:''});
              // Turn off any provider subtitle previously enabled.
              try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch (_) {}
              try { window.postMessage({action:'subtitleOff'},'*'); } catch (_) {}
              try { document.querySelectorAll('track[data-xs-network-track="1"]').forEach(t => t.remove()); } catch (_) {}
              try {
                if (v && v.textTracks) {
                  for (let i=0;i<v.textTracks.length;i++) {
                    try { v.textTracks[i].mode='disabled'; } catch (_) {}
                  }
                }
              } catch (_) {}
            }

            function srtToVtt(raw) {
              let s = String(raw || '').replace(/^\uFEFF/, '');
              if (/^WEBVTT/m.test(s)) return s;
              s = s.replace(/(\d\d:\d\d:\d\d),(\d{3})/g,'$1.$2');
              return 'WEBVTT\n\n' + s;
            }

            function bindURLTrack(item) {
              if (!v || !item || !item.url) return false;
              try {
                let src = item.url;
                const remembered = xsSubtitleBodies.get(xsAbsoluteURL(item.url));
                if (remembered) {
                  const blob = new Blob([srtToVtt(remembered)], {type:'text/vtt'});
                  src = URL.createObjectURL(blob);
                }
                const track = document.createElement('track');
                track.setAttribute('data-xs-network-track','1');
                track.kind='subtitles';
                track.label=String(item.label || item.language || 'Subtitle');
                if (item.language) track.srclang=String(item.language);
                track.src=src;
                track.default=true;
                track.addEventListener('load',() => {
                  try {
                    for (let i=0;i<v.textTracks.length;i++) {
                      const tt=v.textTracks[i];
                      tt.mode = (tt === track.track) ? 'showing' : 'disabled';
                    }
                    track.track.mode='showing';
                  } catch (_) {}
                  bridge({event:'xs:subtitleSelected',id:wantedID});
                },{once:true});
                track.addEventListener('error',() => {
                  bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:String(item.label||'')});
                },{once:true});
                v.appendChild(track);
                setTimeout(() => { try { track.track.mode='showing'; } catch (_) {} }, 80);
                return true;
              } catch (_) { return false; }
            }

            clearAllSubtitleTracks();

            if (wantedID === 'off' || String(payload.source || '') === 'off') {
              bridge({event:'xs:subtitleSelected',id:'off'});
            } else if (wantedID.startsWith('track-')) {
              const idx = Number(payload.index);
              if (v && v.textTracks && Number.isFinite(idx) && idx >= 0 && idx < v.textTracks.length) {
                try {
                  for (let i=0;i<v.textTracks.length;i++) v.textTracks[i].mode = i===idx ? 'showing' : 'disabled';
                  bridge({event:'xs:subtitleSelected',id:wantedID});
                } catch (_) { bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:String(payload.label||'')}); }
              }
            } else {
              const item = networkSubtitleItems.find(it => String(it.id) === wantedID);
              if (item && item.url && bindURLTrack(item)) {
                // selection is confirmed only by the real track load event
              } else {
                // Never fall back to a guessed provider index: that is what caused wrong-language subtitles.
                bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:String(payload.label||'')});
              }
            }
          }
'''
text = text[:start] + action + text[end:]

path.write_text(text)
print('Applied V23 strict subtitle binding: same-object label+URL, no guessed index fallback')
