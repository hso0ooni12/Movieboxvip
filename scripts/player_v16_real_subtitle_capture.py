from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V16: capture REAL subtitle payloads (VTT/SRT) used by FrameXTV/provider and render
# them through XS Player. Do not expose DOM/network metadata-only subtitle rows.

# Prefer captured subtitle assets over every other source in Swift dedupe.
text = text.replace(
    '            case "networkasset": return 70\n',
    '            case "captured": return 100\n            case "networkasset": return 70\n',
    1
)

scan_start = text.find('      function scanSubtitles(')
scan_end = text.find('\n      function parseServerRow', scan_start)
if scan_start == -1 or scan_end == -1:
    raise SystemExit('V16 scanSubtitles bounds not found')

capture_engine = r'''      const xsCapturedSubtitles = new Map();
      const xsSubtitleMeta = new Map();
      const xsSubtitleFetchSeen = new Set();
      let xsActiveCapturedSubtitleID = null;
      let xsV16CaptureInstalled = false;

      function xsAbsoluteURL(value) {
        try { return new URL(String(value || ''), document.baseURI || location.href).href; }
        catch (_) { return String(value || ''); }
      }

      function xsTimeToSeconds(raw) {
        const s = String(raw || '').trim().replace(',', '.');
        const parts = s.split(':').map(Number);
        if (parts.some(x => !Number.isFinite(x))) return NaN;
        if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
        if (parts.length === 2) return parts[0] * 60 + parts[1];
        return Number(s);
      }

      function xsParseSubtitleText(raw) {
        let body = String(raw || '').replace(/\r/g, '').trim();
        if (!body || !body.includes('-->')) return [];
        body = body.replace(/^WEBVTT[^\n]*\n+/i, '');
        const blocks = body.split(/\n{2,}/);
        const cues = [];
        for (const block of blocks) {
          const lines = block.split('\n').filter(Boolean);
          const timingIndex = lines.findIndex(line => line.includes('-->'));
          if (timingIndex < 0) continue;
          const m = lines[timingIndex].match(/([^\s]+)\s*-->\s*([^\s]+)/);
          if (!m) continue;
          const start = xsTimeToSeconds(m[1]);
          const end = xsTimeToSeconds(m[2]);
          if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) continue;
          let cueText = lines.slice(timingIndex + 1).join('\n');
          cueText = cueText.replace(/<br\s*\/?>/gi, '\n').replace(/<[^>]+>/g, '').trim();
          if (!cueText) continue;
          cues.push({start:start,end:end,text:cueText});
        }
        cues.sort((a,b) => a.start - b.start);
        return cues;
      }

      function xsGuessLanguage(url, fallbackLabel, fallbackLang) {
        let lang = String(fallbackLang || '').trim();
        let label = normalizeSubtitleLabel(fallbackLabel || '');
        if (!lang) {
          const u = String(url || '').toLowerCase();
          const m = u.match(/(?:^|[._\-/])(ar|ara|en|eng|es|spa|fr|fra|de|deu|it|ita|pt|por|tr|tur|ru|rus|ja|jpn|ko|kor|zh|zho)(?:[._\-/]|$)/i);
          if (m) lang = m[1];
        }
        if (!label && lang) label = languageName(lang);
        if (!label) label = 'Subtitle';
        return {label:label,language:lang};
      }

      function xsPublishCaptured(finalPass) {
        const items = [];
        xsCapturedSubtitles.forEach(item => {
          items.push({
            id:item.id,
            index:null,
            label:item.label,
            language:item.language,
            source:'captured'
          });
        });
        bridge({event:'xs:subtitles',items:items,final:!!finalPass});
      }

      function xsCaptureSubtitleRaw(url, raw, label, language) {
        const cues = xsParseSubtitleText(raw);
        if (!cues.length) return false;
        const abs = xsAbsoluteURL(url);
        const meta = xsSubtitleMeta.get(abs) || {};
        const info = xsGuessLanguage(abs, label || meta.label, language || meta.language);
        const id = xsFrameId + '::captured-' + Array.from(xsCapturedSubtitles.keys()).length + '-' + Math.abs(abs.split('').reduce((a,c)=>((a<<5)-a)+c.charCodeAt(0),0));
        let existing = null;
        xsCapturedSubtitles.forEach(v => { if (v.url === abs) existing = v; });
        if (existing) {
          existing.label = info.label || existing.label;
          existing.language = info.language || existing.language;
          existing.cues = cues;
        } else {
          xsCapturedSubtitles.set(id,{id:id,url:abs,label:info.label,language:info.language,cues:cues});
        }
        xsPublishCaptured(false);
        return true;
      }

      function xsRememberSubtitleMeta(asset, label, language) {
        if (!asset) return;
        const abs = xsAbsoluteURL(asset);
        if (!abs) return;
        const info = xsGuessLanguage(abs,label,language);
        xsSubtitleMeta.set(abs,{label:info.label,language:info.language});
        if (xsSubtitleFetchSeen.has(abs)) return;
        xsSubtitleFetchSeen.add(abs);
        try {
          const rawFetch = window.__xsV16RawFetch;
          if (!rawFetch) return;
          rawFetch(abs,{credentials:'include'}).then(resp => {
            if (!resp || !resp.ok) return;
            return resp.text().then(raw => xsCaptureSubtitleRaw(abs,raw,info.label,info.language));
          }).catch(()=>{});
        } catch (_) {}
      }

      function xsInspectSubtitleMetadata(value, path, depth) {
        if (depth > 8 || value == null) return;
        const p = String(path || '').toLowerCase();
        if (Array.isArray(value)) {
          value.forEach((item,i) => xsInspectSubtitleMetadata(item,p+'['+i+']',depth+1));
          return;
        }
        if (typeof value !== 'object') return;
        try {
          const asset = value.url || value.src || value.file || value.path || value.uri || value.subtitleUrl || value.subtitle_url || value.vtt || value.srt || '';
          const label = value.label || value.name || value.title || value.displayName || value.languageName || '';
          const lang = value.language || value.lang || value.srclang || value.code || value.locale || '';
          const kind = String(value.kind || value.type || value.category || '').toLowerCase();
          if (asset && (/sub|caption|track|translation/.test(p) || /sub|caption/.test(kind) || label || lang)) {
            xsRememberSubtitleMeta(asset,label,lang);
          }
        } catch (_) {}
        Object.keys(value).forEach(k => xsInspectSubtitleMetadata(value[k],p ? p+'.'+k : k,depth+1));
      }

      function xsInspectNetworkBody(url, contentType, raw) {
        const abs = xsAbsoluteURL(url);
        const ct = String(contentType || '').toLowerCase();
        const body = String(raw || '');
        if (!body) return;
        if (body.includes('-->') && (body.length < 8000000)) {
          const meta = xsSubtitleMeta.get(abs) || {};
          if (xsCaptureSubtitleRaw(abs,body,meta.label,meta.language)) return;
        }
        if (ct.includes('json') || /^[\[{]/.test(body.trim())) {
          try { xsInspectSubtitleMetadata(JSON.parse(body),abs,0); } catch (_) {}
        }
      }

      function xsInstallRealSubtitleCapture() {
        if (xsV16CaptureInstalled) return;
        xsV16CaptureInstalled = true;
        try {
          if (typeof window.fetch === 'function') {
            const rawFetch = window.fetch.bind(window);
            window.__xsV16RawFetch = rawFetch;
            window.fetch = function() {
              const args = arguments;
              let requestURL = '';
              try { requestURL = typeof args[0] === 'string' ? args[0] : (args[0] && args[0].url) || ''; } catch (_) {}
              return rawFetch.apply(window,args).then(resp => {
                try {
                  const clone = resp.clone();
                  const url = resp.url || requestURL;
                  const ct = clone.headers ? clone.headers.get('content-type') : '';
                  clone.text().then(raw => xsInspectNetworkBody(url,ct,raw)).catch(()=>{});
                } catch (_) {}
                return resp;
              });
            };
          }
        } catch (_) {}

        try {
          if (window.XMLHttpRequest) {
            const originalOpen = XMLHttpRequest.prototype.open;
            const originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function(method,url) {
              try { this.__xsV16URL = String(url || ''); } catch (_) {}
              return originalOpen.apply(this,arguments);
            };
            XMLHttpRequest.prototype.send = function() {
              try {
                this.addEventListener('load',function(){
                  try {
                    const raw = typeof this.responseText === 'string' ? this.responseText : '';
                    const ct = String(this.getResponseHeader('content-type') || '');
                    xsInspectNetworkBody(this.responseURL || this.__xsV16URL,ct,raw);
                  } catch (_) {}
                });
              } catch (_) {}
              return originalSend.apply(this,arguments);
            };
          }
        } catch (_) {}
      }

      function scanSubtitles(finalPass) {
        const items = [];
        const seen = new Set();
        const v = video || findVideo();

        xsCapturedSubtitles.forEach(item => {
          const key = (String(item.label || '')+'|'+String(item.language || '')).toLowerCase();
          if (seen.has(key)) return;
          seen.add(key);
          items.push({id:item.id,index:null,label:item.label,language:item.language,source:'captured'});
        });

        try {
          if (v && v.textTracks) {
            for (let i=0;i<v.textTracks.length;i++) {
              const t = v.textTracks[i];
              const label = String(t.label || '').trim();
              const language = String(t.language || '').trim();
              if (!label && !language) continue;
              const key=(label+'|'+language).toLowerCase();
              if (seen.has(key)) continue;
              seen.add(key);
              items.push({id:xsFrameId+'::track-'+i,index:i,label:label || languageName(language),language:language,source:'textTrack'});
            }
          }
        } catch (_) {}

        bridge({event:'xs:subtitles',items:items,final:!!finalPass});
      }
'''
text = text[:scan_start] + capture_engine + text[scan_end:]

# Replace reportCaption so captured subtitle files are rendered by XS Player itself.
cap_start = text.find('      function reportCaption() {')
cap_end = text.find('\n      function applySubtitleStyle()', cap_start)
if cap_start == -1 or cap_end == -1:
    raise SystemExit('V16 reportCaption bounds not found')
report_caption = r'''      function reportCaption() {
        const v = video || findVideo();
        if (!v) return;
        const wanted = Number(v.currentTime || 0) + subtitleDelay;
        let textOut = '';

        if (xsActiveCapturedSubtitleID && xsCapturedSubtitles.has(xsActiveCapturedSubtitleID)) {
          const item = xsCapturedSubtitles.get(xsActiveCapturedSubtitleID);
          const cues = item.cues || [];
          let lo = 0, hi = cues.length - 1;
          while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            const cue = cues[mid];
            if (wanted < cue.start) hi = mid - 1;
            else if (wanted > cue.end) lo = mid + 1;
            else { textOut = cue.text || ''; break; }
          }
        } else if (v.textTracks && subtitleIndex >= 0 && subtitleIndex < v.textTracks.length) {
          const track = v.textTracks[subtitleIndex];
          try { track.mode='hidden'; } catch (_) {}
          try {
            const cues = track.cues || [];
            for (let i=0;i<cues.length;i++) {
              const cue = cues[i];
              if (cue.startTime <= wanted && cue.endTime >= wanted) { textOut = cue.text || ''; break; }
              if (cue.startTime > wanted) break;
            }
          } catch (_) {}
        }

        if (textOut !== lastCaption) {
          lastCaption = textOut;
          bridge({event:'xs:caption',text:textOut});
        }
      }
'''
text = text[:cap_start] + report_caption + text[cap_end:]

# Replace subtitle selection: only captured files or a direct HTML textTrack are actionable.
sub_start = text.find("          else if (action === 'subtitle') {")
sub_end = text.find("\n          else if (action === 'server') {", sub_start)
if sub_start == -1 or sub_end == -1:
    raise SystemExit('V16 subtitle command bounds not found')
subtitle_command = r'''          else if (action === 'subtitle') {
            const source = String(payload.source || '').toLowerCase();
            const wantedID = String(payload.id || '');
            const wantedFrame = wantedID.includes('::') ? wantedID.split('::')[0] : '';
            if (wantedID !== 'off' && wantedFrame && wantedFrame !== xsFrameId) return;
            const idx = Number(payload.index);

            xsActiveCapturedSubtitleID = null;
            subtitleIndex = -1;
            selectedDomSubtitle = '';
            lastCaption = '';
            try {
              if (v && v.textTracks) {
                for (let i=0;i<v.textTracks.length;i++) v.textTracks[i].mode='disabled';
              }
            } catch (_) {}
            try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch (_) {}
            bridge({event:'xs:caption',text:''});

            if (source === 'off' || wantedID === 'off') {
              bridge({event:'xs:subtitleSelected',id:'off'});
            }
            else if (source === 'captured' && xsCapturedSubtitles.has(wantedID)) {
              xsActiveCapturedSubtitleID = wantedID;
              reportCaption();
              bridge({event:'xs:subtitleSelected',id:wantedID});
            }
            else if (source === 'texttrack' && Number.isFinite(idx) && idx >= 0 && v && v.textTracks && idx < v.textTracks.length) {
              subtitleIndex = idx;
              try {
                for (let i=0;i<v.textTracks.length;i++) v.textTracks[i].mode = i === idx ? 'hidden' : 'disabled';
              } catch (_) {}
              reportCaption();
              bridge({event:'xs:subtitleSelected',id:wantedID});
            }
            else {
              bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:String(payload.label || ''),language:String(payload.language || '')});
            }
          }
'''
text = text[:sub_start] + subtitle_command + text[sub_end:]

# Install our capture hook before the older metadata observer so we see the original responses.
install_marker = '      installSubtitleNetworkObserver();\n'
if install_marker not in text:
    raise SystemExit('V16 network observer install marker not found')
text = text.replace(install_marker, '      xsInstallRealSubtitleCapture();\n      installSubtitleNetworkObserver();\n', 1)

# Clear captured subtitle files after a confirmed server change, then detect only the new server's files.
switch_marker = '''                      if (typeof networkSubtitleSeen !== 'undefined' && networkSubtitleSeen.clear) networkSubtitleSeen.clear();
                      clearManagedSubtitle && clearManagedSubtitle();
                      setTimeout(() => scanSubtitles(false),500);'''
switch_repl = '''                      if (typeof networkSubtitleSeen !== 'undefined' && networkSubtitleSeen.clear) networkSubtitleSeen.clear();
                      clearManagedSubtitle && clearManagedSubtitle();
                      xsCapturedSubtitles.clear(); xsSubtitleMeta.clear(); xsSubtitleFetchSeen.clear(); xsActiveCapturedSubtitleID = null;
                      setTimeout(() => scanSubtitles(false),500);'''
if switch_marker in text:
    text = text.replace(switch_marker, switch_repl, 1)

path.write_text(text)
print('Applied XS Player V16 real subtitle response capture')
