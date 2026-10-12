from pathlib import Path

path = Path("FrameNative/FrameXTVPlayerV6.swift")
text = path.read_text()

# Remove the fake provider fallback list. Real server rows are discovered from FrameXTV.
old_servers = '''    @Published var servers: [XSServerOption] = [
        .init(id: "auto", name: "Auto", quality: "AUTO", provider: "auto", selected: true),
        .init(id: "barbarian", name: "Barbarian", quality: "", provider: "barbarian", selected: false),
        .init(id: "archer", name: "Archer", quality: "", provider: "archer", selected: false),
        .init(id: "goblin", name: "Goblin", quality: "", provider: "goblin", selected: false)
    ]
'''
new_servers = '''    @Published var servers: [XSServerOption] = [
        .init(id: "auto", name: "Auto", quality: "AUTO", provider: "auto", selected: true)
    ]
'''
if old_servers in text:
    text = text.replace(old_servers, new_servers, 1)

start_marker = '    private static let bridgeScript = #"""\n'
end_marker = '    """#\n\n    final class Coordinator'
start = text.find(start_marker)
end = text.find(end_marker, start)
if start == -1 or end == -1:
    raise SystemExit("bridge script markers not found")

stable_bridge = r'''    private static let bridgeScript = #"""
    (function(){
      if (window.__xsStableV7) return;
      window.__xsStableV7 = true;

      let video = null;
      let subtitleIndex = -1;
      let subtitleDelay = 0;
      let lastCaption = '';
      let selectedDomSubtitle = '';
      let subtitleStyle = {size:1,color:'#ffffff',background:true,bottom:76};

      function bridge(payload) {
        try { window.webkit.messageHandlers.xsTelemetry.postMessage(payload); } catch (_) {}
      }

      function cleanText(el) {
        return String((el && (el.innerText || el.textContent)) || '').replace(/\s+/g,' ').trim();
      }

      function findVideo() {
        try {
          const videos = Array.from(document.querySelectorAll('video'));
          if (!videos.length) return null;
          return videos.sort((a,b) => (b.clientWidth*b.clientHeight) - (a.clientWidth*a.clientHeight))[0];
        } catch (_) { return null; }
      }

      function hideChrome() {
        const v = video || findVideo();
        if (!v) return;
        try { v.controls = false; v.setAttribute('playsinline',''); v.setAttribute('webkit-playsinline',''); } catch (_) {}
        try {
          Array.from(document.querySelectorAll('button,[role="button"],[role="dialog"],header,nav')).forEach(el => {
            el.style.setProperty('opacity','0','important');
            el.style.setProperty('pointer-events','none','important');
          });
        } catch (_) {}
      }

      function reportState() {
        const v = video || findVideo();
        if (!v) return;
        bridge({
          event:'xs:state',
          currentTime:Number(v.currentTime || 0),
          duration:Number(isFinite(v.duration) ? v.duration : 0),
          paused:!!v.paused,
          muted:!!v.muted,
          rate:Number(v.playbackRate || 1)
        });
      }

      function languageName(code) {
        const c = String(code || '').toLowerCase();
        const map = {ar:'Arabic',ara:'Arabic',en:'English',eng:'English',es:'Spanish',spa:'Spanish',fr:'French',fra:'French',de:'German',deu:'German',it:'Italian',ita:'Italian',pt:'Portuguese',por:'Portuguese',tr:'Turkish',tur:'Turkish',ru:'Russian',rus:'Russian',ja:'Japanese',jpn:'Japanese',ko:'Korean',kor:'Korean',zh:'Chinese',zho:'Chinese',hi:'Hindi',hin:'Hindi',ur:'Urdu',urd:'Urdu'};
        return map[c] || code || '';
      }

      function looksLikeLanguage(text) {
        return /arabic|english|spanish|french|german|italian|portuguese|turkish|russian|hindi|urdu|japanese|korean|chinese|thai|indonesian|malay|dutch|polish|swedish|norwegian|danish|finnish|greek|hebrew|العربية|عربي|انجليزي|إنجليزي|español|français|deutsch|italiano|português|türkçe|русский|日本語|한국어|中文/i.test(text);
      }

      function scanSubtitles() {
        const items = [];
        const seen = new Set();
        const v = video || findVideo();

        function add(id,index,label,language,source) {
          let l = String(label || '').trim();
          let lang = String(language || '').trim();
          if (!l && lang) l = languageName(lang);
          if (!l && !lang) return;
          const key = (l + '|' + lang).toLowerCase();
          if (seen.has(key)) return;
          seen.add(key);
          items.push({id:String(id),index:index,label:l,language:lang,source:source});
        }

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
          Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div')).forEach((el,i) => {
            const t = cleanText(el);
            if (!t || t.length > 48 || !looksLikeLanguage(t)) return;
            add('dom-'+i,null,t,'','dom');
          });
        } catch (_) {}

        bridge({event:'xs:subtitles',items:items});
      }

      function parseServerRow(text) {
        const clean = String(text || '').replace(/\s+/g,' ').trim();
        if (!clean || clean.length > 120) return null;
        if (!/(Connected|Available)/i.test(clean)) return null;
        const q = (clean.match(/(4K|UHD|FHD|1080p|720p|HD)/i) || [])[1] || '';
        let name = clean.replace(/Connected|Available|4K|UHD|FHD|1080p|720p|HD/ig,' ').replace(/\s+/g,' ').trim();
        if (!name || name.length > 55) return null;
        return {name:name,quality:q.toUpperCase(),selected:/Connected/i.test(clean)};
      }

      function scanServers() {
        const out = [];
        const seen = new Set();
        try {
          Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div')).forEach(el => {
            const row = parseServerRow(cleanText(el));
            if (!row) return;
            const key = row.name.toLowerCase();
            if (seen.has(key)) return;
            seen.add(key);
            out.push(row);
          });
        } catch (_) {}
        if (out.length) bridge({event:'xs:servers',items:out});
      }

      function openServerMenu() {
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"]'));
          let found = nodes.find(el => {
            const meta = (String(el.getAttribute('aria-label') || '') + ' ' + String(el.getAttribute('title') || '') + ' ' + cleanText(el)).toLowerCase();
            return /server|provider|source/.test(meta);
          });
          if (!found) {
            found = nodes.find(el => {
              const t = cleanText(el);
              return t.length > 2 && t.length < 42 && /\b[IVXLCDM]{1,8}\b/.test(t) && !/episode|season/i.test(t);
            });
          }
          if (found) { found.click(); return true; }
        } catch (_) {}
        return false;
      }

      function openSubtitleMenu() {
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"]'));
          const found = nodes.find(el => {
            const meta = (String(el.getAttribute('aria-label') || '') + ' ' + String(el.getAttribute('title') || '') + ' ' + cleanText(el)).toLowerCase();
            return /subtitle|caption|\bcc\b/.test(meta);
          });
          if (found) { found.click(); return true; }
        } catch (_) {}
        return false;
      }

      function selectByText(text) {
        const wanted = String(text || '').trim().toLowerCase();
        if (!wanted) return false;
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div'));
          const candidates = nodes.filter(el => {
            const t = cleanText(el).toLowerCase();
            return t === wanted || t.startsWith(wanted + ' ') || wanted.startsWith(t + ' ');
          }).sort((a,b) => cleanText(a).length - cleanText(b).length);
          const found = candidates[0];
          if (found) {
            const clickable = found.closest('button,[role="button"],[role="menuitem"],li') || found;
            clickable.click();
            return true;
          }
        } catch (_) {}
        return false;
      }

      function openAndScanServers() {
        openServerMenu();
        setTimeout(scanServers,120);
        setTimeout(scanServers,350);
        setTimeout(scanServers,700);
      }

      function openAndScanSubtitles() {
        openSubtitleMenu();
        setTimeout(scanSubtitles,120);
        setTimeout(scanSubtitles,350);
        setTimeout(scanSubtitles,700);
      }

      function reportCaption() {
        const v = video || findVideo();
        if (!v || !v.textTracks || subtitleIndex < 0 || subtitleIndex >= v.textTracks.length) {
          if (lastCaption !== '') { lastCaption=''; bridge({event:'xs:caption',text:''}); }
          return;
        }
        const track = v.textTracks[subtitleIndex];
        try { track.mode='hidden'; } catch (_) {}
        const wanted = Number(v.currentTime || 0) + subtitleDelay;
        let text = '';
        try {
          const cues = track.cues || [];
          for (let i=0;i<cues.length;i++) {
            const cue = cues[i];
            if (cue.startTime <= wanted && cue.endTime >= wanted) { text = cue.text || ''; break; }
            if (cue.startTime > wanted) break;
          }
        } catch (_) {}
        if (text !== lastCaption) { lastCaption=text; bridge({event:'xs:caption',text:text}); }
      }

      function applySubtitleStyle() {
        try {
          let style = document.getElementById('xs-cue-style');
          if (!style) { style=document.createElement('style'); style.id='xs-cue-style'; document.head.appendChild(style); }
          const bg = subtitleStyle.background ? 'rgba(0,0,0,.68)' : 'transparent';
          const px = Math.max(14,Math.round(22*Number(subtitleStyle.size || 1)));
          style.textContent = 'video::cue{font-size:'+px+'px!important;color:'+subtitleStyle.color+'!important;background:'+bg+'!important;font-family:-apple-system,BlinkMacSystemFont,Helvetica Neue,Arial,sans-serif!important;font-weight:700!important}';
          Array.from(document.querySelectorAll('[class*="subtitle" i],[class*="caption" i]')).forEach(el => {
            if (el.closest('button,[role="button"],[role="dialog"]')) return;
            el.style.setProperty('font-size',px+'px','important');
            el.style.setProperty('color',subtitleStyle.color,'important');
            el.style.setProperty('font-weight','700','important');
          });
        } catch (_) {}
      }

      function install(v) {
        if (!v || video === v) return;
        video = v;
        try { v.controls=false; } catch (_) {}
        ['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ratechange','ended','canplay'].forEach(name => {
          try { v.addEventListener(name,reportState,{passive:true}); } catch (_) {}
        });
        bridge({event:'xs:ready'});
        reportState();
        scanSubtitles();
        hideChrome();
      }

      function command(payload) {
        const v = video || findVideo();
        const action = payload && payload.action;
        try {
          if (action === 'play' && v) v.play();
          else if (action === 'pause' && v) v.pause();
          else if (action === 'seek' && v) v.currentTime = Math.max(0,Number(payload.time || 0));
          else if (action === 'seekBy' && v) v.currentTime = Math.max(0,Number(v.currentTime || 0) + Number(payload.seconds || 0));
          else if (action === 'mute' && v) v.muted = !!payload.muted;
          else if (action === 'rate' && v) v.playbackRate = Number(payload.rate || 1);
          else if (action === 'pip' && v) {
            if (typeof v.webkitSetPresentationMode === 'function') v.webkitSetPresentationMode('picture-in-picture');
            else if (v.requestPictureInPicture) v.requestPictureInPicture();
          }
          else if (action === 'aspect' && v) {
            const mode=String(payload.mode || 'adapt');
            v.style.objectFit = mode === 'stretch' ? 'fill' : (mode === 'fill' ? 'cover' : 'contain');
          }
          else if (action === 'subtitleDelay') subtitleDelay = Number(payload.seconds || 0);
          else if (action === 'subtitleStyle') {
            subtitleStyle={size:Number(payload.size||1),color:String(payload.color||'#ffffff'),background:!!payload.background,bottom:Number(payload.bottom||76)};
            applySubtitleStyle();
          }
          else if (action === 'subtitle') {
            const idx = Number(payload.index);
            subtitleIndex = Number.isFinite(idx) ? idx : -1;
            selectedDomSubtitle = String(payload.label || '');
            if (v && v.textTracks && subtitleIndex >= 0 && subtitleIndex < v.textTracks.length) {
              for (let i=0;i<v.textTracks.length;i++) {
                try { v.textTracks[i].mode = i === subtitleIndex ? 'hidden' : 'disabled'; } catch (_) {}
              }
            } else if (selectedDomSubtitle) {
              openSubtitleMenu();
              setTimeout(() => selectByText(selectedDomSubtitle),120);
            }
          }
          else if (action === 'server') {
            const name = String(payload.name || '');
            const provider = String(payload.provider || '');
            if (provider && provider !== 'auto' && /^(barbarian|archer|goblin)$/i.test(provider)) {
              window.postMessage({action:'setProvider',provider:provider},'*');
            } else if (name && name.toLowerCase() !== 'auto') {
              openServerMenu();
              setTimeout(() => selectByText(name),120);
            }
          }
          else if (action === 'metadata') {
            scanSubtitles();
            openAndScanServers();
          }
          else if (action === 'subtitleMenu') openAndScanSubtitles();
          else if (action === 'qualityMenu') openAndScanServers();
          else if (action === 'audioMenu') bridge({event:'xs:audio',items:[{name:'Original / Default',selected:true}]});
          else if (action === 'quality') {
            openServerMenu();
            setTimeout(() => selectByText(String(payload.name || '')),120);
          }
        } catch (_) {}
        reportState();
      }

      window.addEventListener('message', event => {
        try {
          if (event.data && event.data.__xsCommand) command(event.data.__xsCommand);
          const d = event.data;
          if (d && d.event === 'frameXTV:timeupdate') bridge(d);
        } catch (_) {}
      });

      new MutationObserver(() => {
        const v = findVideo();
        if (v) install(v);
        if (video) hideChrome();
      }).observe(document.documentElement || document.body,{subtree:true,childList:true});

      setInterval(() => {
        const v = findVideo();
        if (v) install(v);
        if (video) {
          hideChrome();
          reportState();
          reportCaption();
          applySubtitleStyle();
        }
      },400);

      setTimeout(() => {
        if (!findVideo()) bridge({event:'xs:error',message:'Waiting for playback engine…'});
      },12000);
    })();
    """#
'''

text = text[:start] + stable_bridge + text[end + len('    """#\n'):]
path.write_text(text)
print("XS Player v7 stable engine patch applied")
