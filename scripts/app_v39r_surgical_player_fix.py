from pathlib import Path
import re

path = Path("FrameNative/FrameXTVPlayerV6.swift")
s = path.read_text(encoding="utf-8")

MARKER = "V39R_SURGICAL_PLAYER_FIX"
if MARKER in s:
    print("V39R already applied")
    raise SystemExit(0)

# ---------------------------------------------------------------------------
# V39 recovery rule: do NOT replace the proven subtitle/server architecture.
# We only (1) keep server discovery inside the source's Select Server popup,
# (2) decorate those known rows with source/decoded quality, and
# (3) pass the already-existing subtitle background style/opacity values all
# the way through the command bridge. No broad document/network catalog scan.
# ---------------------------------------------------------------------------

# 1) Swift-side final safety boundary. Even if a provider emits a malformed
# xs:servers event, subtitle/caption rows can never become server options.
server_case_start = s.find('        case "xs:servers":')
server_case_end = s.find('\n        case "xs:qualities":', server_case_start)
if server_case_start < 0 or server_case_end < 0:
    raise SystemExit("V39R: Swift xs:servers block not found")
server_case = s[server_case_start:server_case_end]
needle = '                guard !name.isEmpty else { return nil }'
replacement = '''                let serverFolded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
                let subtitleLike = serverFolded.contains("subtitle") ||
                    serverFolded.contains("caption") || serverFolded.contains("closed caption") ||
                    serverFolded.hasPrefix("cc ") || serverFolded.contains(" • ")
                guard !name.isEmpty, !subtitleLike else { return nil }'''
if needle not in server_case:
    raise SystemExit("V39R: server name guard not found")
server_case = server_case.replace(needle, replacement, 1)
s = s[:server_case_start] + server_case + s[server_case_end:]

# 2) Explicit server-menu request. V39's Quality & Server panel previously
# relied on background metadata scans. Ask the source's actual server popup to
# open, then scan ONLY that popup. This is what prevents subtitle contamination.
request_quality = '    func requestQualityMenu() { send(["action": "qualityMenu"]) }'
if request_quality not in s:
    raise SystemExit("V39R: requestQualityMenu marker not found")
s = s.replace(
    request_quality,
    request_quality + '\n    func requestServerMenu() { send(["action": "serverMenu"]) }',
    1,
)

on_appear_quality = '''        .onAppear {
            player.requestQualityMenu()
            player.requestMetadata()
        }'''
if on_appear_quality not in s:
    raise SystemExit("V39R: quality panel onAppear marker not found")
s = s.replace(
    on_appear_quality,
    '''        .onAppear {
            player.requestServerMenu()
            player.requestQualityMenu()
            player.requestMetadata()
        }''',
    1,
)

# 3) Replace V39's server scan only. Server identity comes exclusively from the
# source popup headed "Select Server". Quality may come from that row's own
# text/data attributes; for the selected server we additionally confirm the
# actual decoded HTMLVideoElement height and cache that confirmed result.
scan_match = re.search(r'      function scanServers\(\)\s*\{', s)
if not scan_match:
    raise SystemExit("V39R: scanServers start not found")
scan_start = scan_match.start()
scan_end = s.find('\n      function reportCaption', scan_match.end())
if scan_end < 0:
    raise SystemExit("V39R: scanServers end not found")

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
              if (rows.length >= 2 && !root.querySelector('video,iframe')) return root;
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
        const out = [];
        const read = node => {
          if (!node || !node.getAttribute) return;
          for (const key of attrs) {
            const value = String(node.getAttribute(key) || '').trim();
            if (value) out.push(value);
          }
        };
        read(el);
        try { Array.from(el.querySelectorAll('*')).slice(0, 20).forEach(read); } catch (_) {}
        return out.join(' ');
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
            // Hard separation from the CC/subtitle catalog.
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
              if (measured) { quality = measured; xsV39ServerQuality.set(key, measured); }
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

# Add a dedicated command that opens the site's server picker. Do not reuse the
# subtitle menu and do not scan generic dialogs.
server_action_marker = "          else if (action === 'server') {"
if server_action_marker not in s:
    # Older compact formatting before V11.
    server_action_marker = "          else if(a==='server'){"
if server_action_marker not in s:
    raise SystemExit("V39R: server command marker not found")
server_menu_command = '''          else if (action === 'serverMenu') {
            openServerMenu();
            setTimeout(scanServers, 120);
            setTimeout(scanServers, 320);
            setTimeout(scanServers, 700);
          }
'''
if "action === 'serverMenu'" not in s:
    s = s.replace(server_action_marker, server_menu_command + server_action_marker, 1)

# The source menu may render asynchronously. Re-scan selected video dimensions
# when they become reliable, without any document-wide scan or stream reload.
install_marker = "        bridge({event:'xs:ready'});reportState();scanSubtitles();scanServers();"
if install_marker in s:
    s = s.replace(
        install_marker,
        "        bridge({event:'xs:ready'});reportState();scanSubtitles();scanServers();\n"
        "        try{v.addEventListener('loadedmetadata',scanServers,{passive:true});v.addEventListener('resize',scanServers,{passive:true});v.addEventListener('canplay',scanServers,{passive:true})}catch(_){ }",
        1,
    )

# 4) Root-cause subtitle background fix. V25/V27 added backgroundStyle and
# backgroundOpacity state, but the JS command bridge rebuilt subtitleStyle with
# only the old Boolean `background`, silently discarding BOTH new values. That
# made Black/Gray look the same and made opacity appear to do nothing.
#
# V11 uses `command(payload)` + `action`; older baselines used `command(p)` +
# `a`. Do not depend on whitespace or one exact historical formatting. Locate
# the subtitleStyle branch *inside command()* and replace only that one branch.
command_match = re.search(r'      function command\((?P<payload>[A-Za-z_$][\w$]*)\)\s*\{', s)
if not command_match:
    raise SystemExit("V39R: command function not found")
command_start = command_match.start()
command_end = s.find("\n      window.addEventListener", command_match.end())
if command_end < 0:
    raise SystemExit("V39R: command function end not found")
command_block = s[command_start:command_end]

style_condition = re.search(
    r"else\s+if\s*\(\s*(?:action|a)\s*===\s*['\"]subtitleStyle['\"]\s*\)\s*\{",
    command_block,
)
if not style_condition:
    raise SystemExit("V39R: subtitleStyle command bridge not found")

# Find the balanced closing brace for just this else-if. The branch contains an
# object literal, so a one-line regex is intentionally avoided.
branch_start = style_condition.start()
brace_start = command_block.find("{", style_condition.start(), style_condition.end() + 1)
if brace_start < 0:
    raise SystemExit("V39R: subtitleStyle branch opening brace not found")

def balanced_js_block_end(text: str, opening: int) -> int:
    depth = 0
    quote = None
    escaped = False
    i = opening
    while i < len(text):
        ch = text[i]
        if quote is not None:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"', '`'):
            quote = ch
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return -1

branch_end = balanced_js_block_end(command_block, brace_start)
if branch_end < 0:
    raise SystemExit("V39R: subtitleStyle branch closing brace not found")

payload_name = command_match.group("payload")
# Final V39 (after V11/V24) exposes applySubtitleStyle(); retain fallback only
# for older generated baselines so this surgical patch remains reproducible.
call = "applySubtitleStyle()" if "applySubtitleStyle()" in s else "applyCueStyle()"
new_style_branch = f'''else if (action === 'subtitleStyle') {{
            subtitleStyle = {{
              size: Number({payload_name}.size || 1),
              color: String({payload_name}.color || '#ffffff'),
              background: !!{payload_name}.background,
              backgroundStyle: String({payload_name}.backgroundStyle || ({payload_name}.background === false ? 'none' : 'black')),
              backgroundOpacity: Math.max(0, Math.min(1, Number({payload_name}.backgroundOpacity == null ? 0.68 : {payload_name}.backgroundOpacity))),
              bottom: Number({payload_name}.bottom || 76)
            }};
            {call};
          }}'''
command_block = command_block[:branch_start] + new_style_branch + command_block[branch_end:]
s = s[:command_start] + command_block + s[command_end:]

# Strengthen actual source caption painting. V27 already targets descendants;
# this adds the two properties WebKit caption renderers most consistently obey.
apply_start = s.find('      function applyStyle() {')
apply_end = s.find('\n      function installCaptionObserver() {', apply_start)
if apply_start < 0 or apply_end < 0:
    raise SystemExit("V39R: V27 applyStyle block not found")
apply_block = s[apply_start:apply_end]
if "-webkit-box-decoration-break" not in apply_block:
    raise SystemExit("V39R: expected V27 nested-caption painter missing")
apply_block = apply_block.replace(
    "node.style.setProperty('background-color', bg, 'important');",
    "node.style.setProperty('background-color', bg, 'important');\n"
    "            node.style.setProperty('background-image', 'none', 'important');\n"
    "            node.style.setProperty('box-shadow', 'none', 'important');",
)
s = s[:apply_start] + apply_block + s[apply_end:]

# Ensure ::cue uses background-color as well as background. This covers native
# WebVTT rendering when the provider does not create a DOM caption node.
cue_old = "'video::cue{font-size:' + Math.round(22 * style.size) + 'px!important;color:' + style.color + '!important;background:' + subtitleBackgroundCSS() + '!important}'"
cue_new = "'video::cue{font-size:' + Math.round(22 * style.size) + 'px!important;color:' + style.color + '!important;background:' + subtitleBackgroundCSS() + '!important;background-color:' + subtitleBackgroundCSS() + '!important}'"
if cue_old in s:
    s = s.replace(cue_old, cue_new, 1)

s = f"// {MARKER}: V39 baseline + isolated server quality + real subtitle background/opacity propagation.\n" + s
path.write_text(s, encoding="utf-8")
print("Applied V39R surgical player fix: isolated server list/quality + subtitle background propagation")
