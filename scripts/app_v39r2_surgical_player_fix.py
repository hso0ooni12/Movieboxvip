from pathlib import Path
import re

path = Path("FrameNative/FrameXTVPlayerV6.swift")
s = path.read_text(encoding="utf-8")

MARKER = "V39R_SURGICAL_PLAYER_FIX"
if MARKER in s:
    print("V39R2 already applied")
    raise SystemExit(0)

# V39 recovery only. Do not import post-V39 player architecture.
# 1) isolate movie/series servers to the source's exact Select Server popup,
# 2) decorate those rows with source metadata / selected decoder height,
# 3) propagate subtitle background style + opacity without changing V24 selection.

# Swift safety boundary: a subtitle/caption-looking row is never a server.
server_case_start = s.find('        case "xs:servers":')
server_case_end = s.find('\n        case "xs:qualities":', server_case_start)
if server_case_start < 0 or server_case_end < 0:
    raise SystemExit("V39R2: Swift xs:servers block not found")
block = s[server_case_start:server_case_end]
needle = '                guard !name.isEmpty else { return nil }'
replacement = '''                let serverFolded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
                let subtitleLike = serverFolded.contains("subtitle") ||
                    serverFolded.contains("caption") || serverFolded.contains("closed caption") ||
                    serverFolded.hasPrefix("cc ") || serverFolded.contains(" • ")
                guard !name.isEmpty, !subtitleLike else { return nil }'''
if needle not in block:
    raise SystemExit("V39R2: server name guard not found")
block = block.replace(needle, replacement, 1)
s = s[:server_case_start] + block + s[server_case_end:]

# Dedicated server-menu command from Swift.
quality_method = '    func requestQualityMenu() { send(["action": "qualityMenu"]) }'
if quality_method not in s:
    raise SystemExit("V39R2: requestQualityMenu marker not found")
s = s.replace(quality_method, quality_method + '\n    func requestServerMenu() { send(["action": "serverMenu"]) }', 1)

# Opening Quality & Server must NEVER ask for subtitle metadata. Only open the
# real source server picker. Existing background quality telemetry remains intact.
on_appear = '''        .onAppear {
            player.requestQualityMenu()
            player.requestMetadata()
        }'''
if on_appear not in s:
    raise SystemExit("V39R2: quality panel onAppear marker not found")
s = s.replace(on_appear, '''        .onAppear {
            player.requestServerMenu()
        }''', 1)

# Replace only V39's scanServers. Identity is scoped to the exact Select Server
# popup. No body-wide button/div scan and no subtitle/network catalog reuse.
scan_match = re.search(r'      function scanServers\(\)\s*\{', s)
if not scan_match:
    raise SystemExit("V39R2: scanServers start not found")
scan_start = scan_match.start()
scan_end = s.find('\n      function reportCaption', scan_match.end())
if scan_end < 0:
    raise SystemExit("V39R2: scanServers end not found")

strict_scanner = r'''      const xsV39ServerQuality = new Map();

      function xsV39Quality(meta, height) {
        const raw = String(meta || '').replace(/\s+/g, ' ').toUpperCase();
        const h = Number(height || 0);
        if (/\b(4K|UHD|2160P?)\b/.test(raw) || h >= 2000) return '4K';
        if (/\b(FULL\s*HD|FULLHD|FHD|1080P?)\b/.test(raw) || h >= 1000) return 'Full HD';
        if (/\b(HD|720P?)\b/.test(raw) || h >= 650) return 'HD';
        return '';
      }

      function xsV39ServerPanel() {
        try {
          const labels = Array.from(document.querySelectorAll('span,div,p,h1,h2,h3'))
            .filter(el => /^Select Server$/i.test(cleanText(el)));
          for (const label of labels) {
            let root = label;
            for (let depth = 0; depth < 7 && root && root !== document.body; depth++, root = root.parentElement) {
              const rows = root.querySelectorAll('button,[role="button"],[role="menuitem"]');
              if (rows.length >= 1 && !root.querySelector('video,iframe')) return root;
            }
          }
        } catch (_) {}
        return null;
      }

      function xsV39ServerMeta(el) {
        if (!el || !el.getAttribute) return '';
        const attrs = [
          'data-quality','data-resolution','data-video-quality','data-max-quality',
          'data-name','data-server-name','data-provider-name','data-source-name',
          'data-provider','data-server','data-source','data-value','aria-label','title'
        ];
        const values = [];
        const read = node => {
          if (!node || !node.getAttribute) return;
          for (const key of attrs) {
            const value = String(node.getAttribute(key) || '').trim();
            if (value) values.push(value);
          }
        };
        read(el);
        try { Array.from(el.querySelectorAll('*')).slice(0, 24).forEach(read); } catch (_) {}
        return values.join(' ');
      }

      function scanServers() {
        const root = xsV39ServerPanel();
        if (!root) return;
        const out = [];
        const seen = new Set();
        const v = video || findVideo();
        try {
          Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"]')).forEach(el => {
            const text = cleanText(el).replace(/[✓✔]/g, ' ').replace(/\s+/g, ' ').trim();
            if (!text || text.length > 120) return;
            if (/subtitle|caption|closed\s*caption|\bcc\b/i.test(text)) return;

            const state = (text + ' ' + String(el.className || '') + ' ' +
              String(el.getAttribute('aria-selected') || '') + ' ' +
              String(el.getAttribute('aria-checked') || '') + ' ' +
              String(el.getAttribute('data-selected') || '')).toLowerCase();
            const selected = /connected|selected|active|current|playing|\btrue\b/.test(state);
            const provider = String(el.getAttribute('data-provider') || el.getAttribute('data-server') ||
              el.getAttribute('data-source') || el.getAttribute('data-value') || '').trim();
            const meta = (xsV39ServerMeta(el) + ' ' + text).trim();

            let name = String(el.getAttribute('data-server-name') || el.getAttribute('data-provider-name') ||
              el.getAttribute('data-source-name') || el.getAttribute('data-name') || '').trim();
            if (!name) {
              name = text
                .replace(/Connected|Available|Selected|Active|Current|Playing/ig, ' ')
                .replace(/Full\s*HD|FullHD|4K|UHD|FHD|2160p?|1080p?|720p?|HD/ig, ' ')
                .replace(/\s+/g, ' ').trim();
            }
            if (!name || name.length > 55) return;
            if (/subtitle|caption|closed\s*caption|\bcc\b/i.test(name)) return;

            const key = String(provider || name).toLowerCase();
            if (seen.has(key)) return;
            seen.add(key);

            let quality = xsV39Quality(meta, selected && v ? Number(v.videoHeight || 0) : 0);
            if (selected && v && Number(v.videoHeight || 0) > 0) {
              const measured = xsV39Quality('', Number(v.videoHeight || 0));
              if (measured) {
                quality = measured;
                xsV39ServerQuality.set(key, measured);
              }
            } else if (!quality && xsV39ServerQuality.has(key)) {
              quality = xsV39ServerQuality.get(key) || '';
            }
            out.push({name:name, quality:quality, provider:provider || null, selected:selected});
          });
        } catch (_) {}
        if (out.length) bridge({event:'xs:servers',items:out});
      }
'''
s = s[:scan_start] + strict_scanner + s[scan_end:]

# Dedicated command to open only the source server popup.
server_action_markers = ["          else if (action === 'server') {", "          else if(a==='server'){" ]
server_marker = next((m for m in server_action_markers if m in s), None)
if not server_marker:
    raise SystemExit("V39R2: server command marker not found")
menu_command = '''          else if (action === 'serverMenu') {
            openServerMenu();
            setTimeout(scanServers, 120);
            setTimeout(scanServers, 320);
            setTimeout(scanServers, 700);
          }
'''
if "action === 'serverMenu'" not in s:
    s = s.replace(server_marker, menu_command + server_marker, 1)

# Re-scan the selected server when the real video dimensions settle.
install_anchor = "        bridge({event:'xs:ready'});reportState();scanSubtitles();scanServers();"
if install_anchor in s:
    s = s.replace(
        install_anchor,
        install_anchor + "\n        try{v.addEventListener('loadedmetadata',scanServers,{passive:true});v.addEventListener('resize',scanServers,{passive:true});v.addEventListener('canplay',scanServers,{passive:true})}catch(_){ }",
        1,
    )

# Subtitle appearance root fix: V39 already has Black/Gray/White/None and an
# opacity slider in Swift, but the legacy JS command can discard those fields.
# Observe the same source-owned command envelope and apply the complete style
# to the V24 source adapter on the next run-loop tick, after legacy handlers.
source_anchor = "      const sourceSubtitles = createXSSourceSubtitles({document, window, findVideo, emit: bridge});"
if source_anchor not in s:
    raise SystemExit("V39R2: V24 sourceSubtitles anchor not found")
appearance_bridge = r'''
      window.addEventListener('message', function(event) {
        try {
          const p = event && event.data && event.data.__xsCommand;
          if (!p || p.action !== 'subtitleStyle') return;
          const completeStyle = {
            size: Number(p.size || 1),
            color: String(p.color || '#ffffff'),
            background: p.background !== false,
            backgroundStyle: String(p.backgroundStyle || (p.background === false ? 'none' : 'black')),
            backgroundOpacity: Math.max(0, Math.min(1, Number(p.backgroundOpacity == null ? 0.68 : p.backgroundOpacity))),
            bottom: Number(p.bottom || 76)
          };
          window.setTimeout(() => sourceSubtitles.setStyle(completeStyle), 0);
        } catch (_) {}
      }, true);
'''
s = s.replace(source_anchor, source_anchor + appearance_bridge, 1)

# Harden V27's actual caption paint path against provider background layers.
apply_start = s.find('      function applyStyle() {')
apply_end = s.find('\n      function installCaptionObserver() {', apply_start)
if apply_start < 0 or apply_end < 0:
    raise SystemExit("V39R2: V27 applyStyle block not found")
apply_block = s[apply_start:apply_end]
if "-webkit-box-decoration-break" not in apply_block:
    raise SystemExit("V39R2: nested caption painter missing")
if "background-image', 'none'" not in apply_block:
    apply_block = apply_block.replace(
        "node.style.setProperty('background-color', bg, 'important');",
        "node.style.setProperty('background-color', bg, 'important');\n"
        "            node.style.setProperty('background-image', 'none', 'important');\n"
        "            node.style.setProperty('box-shadow', 'none', 'important');",
    )
s = s[:apply_start] + apply_block + s[apply_end:]

# Native WebVTT renderer path should use the same exact RGBA value.
cue_old = "'video::cue{font-size:' + Math.round(22 * style.size) + 'px!important;color:' + style.color + '!important;background:' + subtitleBackgroundCSS() + '!important}'"
cue_new = "'video::cue{font-size:' + Math.round(22 * style.size) + 'px!important;color:' + style.color + '!important;background:' + subtitleBackgroundCSS() + '!important;background-color:' + subtitleBackgroundCSS() + '!important}'"
if cue_old in s:
    s = s.replace(cue_old, cue_new, 1)

s = f"// {MARKER}: V39 baseline + exact server popup isolation + real subtitle background/opacity.\n" + s
path.write_text(s, encoding="utf-8")
print("Applied V39R2: V39 server/subtitle isolation + source quality + subtitle background propagation")
