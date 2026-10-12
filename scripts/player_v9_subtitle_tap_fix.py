from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# Track whether a subtitle scan has actually completed. Never spin forever.
needle = '''    @Published var selectedSubtitleID: String? = nil\n'''
if needle not in text:
    raise SystemExit('selectedSubtitleID marker not found')
text = text.replace(needle, needle + '''    @Published var subtitleScanFinished = false\n''', 1)

old = '''    func requestSubtitleMenu() { send(["action": "subtitleMenu"]) }\n'''
new = '''    func requestSubtitleMenu() {\n        subtitleScanFinished = false\n        send(["action": "subtitleMenu"])\n    }\n'''
if old not in text:
    raise SystemExit('requestSubtitleMenu not found')
text = text.replace(old, new, 1)

# Reset subtitle scan state when switching servers.
old = '''    func selectServer(_ server: XSServerOption) {\n        var payload: [String: Any] = ["action": "server", "name": server.name]\n'''
new = '''    func selectServer(_ server: XSServerOption) {\n        subtitleOptions = []\n        selectedSubtitleID = nil\n        captionText = ""\n        subtitleScanFinished = false\n        var payload: [String: Any] = ["action": "server", "name": server.name]\n'''
if old not in text:
    raise SystemExit('selectServer v8 marker not found')
text = text.replace(old, new, 1)

# Mark completion even when the result is empty.
needle = '''        case "xs:subtitles":\n            guard let rows = payload["items"] as? [[String: Any]] else { return }\n'''
repl = '''        case "xs:subtitles":\n            subtitleScanFinished = true\n            guard let rows = payload["items"] as? [[String: Any]] else { return }\n'''
if needle not in text:
    raise SystemExit('xs:subtitles receive marker not found')
text = text.replace(needle, repl, 1)

# The transparent video tap is a real toggle: first tap shows, second tap hides immediately.
old = '''                    .onTapGesture { revealControls() }\n'''
new = '''                    .onTapGesture {\n                        if controlsVisible && panel == .none {\n                            hideTask?.cancel()\n                            withAnimation(.easeOut(duration: 0.16)) { controlsVisible = false }\n                        } else if panel == .none {\n                            revealControls()\n                        }\n                    }\n'''
if old not in text:
    raise SystemExit('screen tap marker not found')
text = text.replace(old, new, 1)

# Replace the endless subtitle spinner with a finite state.
old = '''                if player.subtitleOptions.isEmpty {\n                    VStack(alignment: .leading, spacing: 8) {\n                        ProgressView().tint(.white)\n                        Text("Looking for subtitle tracks on this server…")\n                            .font(.footnote)\n                            .foregroundStyle(.secondary)\n                        Button("Scan Again") {\n                            player.requestSubtitleMenu()\n                            player.requestMetadata()\n                        }\n                        .buttonStyle(.bordered)\n                    }\n                    .padding(.vertical, 10)\n                } else {\n'''
new = '''                if player.subtitleOptions.isEmpty {\n                    VStack(alignment: .leading, spacing: 10) {\n                        if player.subtitleScanFinished {\n                            Image(systemName: "captions.bubble")\n                                .font(.title2)\n                                .foregroundStyle(.secondary)\n                            Text("No subtitles available on this server")\n                                .font(.headline)\n                            Text("Try another server, or scan again after playback starts.")\n                                .font(.footnote)\n                                .foregroundStyle(.secondary)\n                        } else {\n                            ProgressView().tint(.white)\n                            Text("Checking subtitle tracks…")\n                                .font(.footnote)\n                                .foregroundStyle(.secondary)\n                        }\n                        Button(player.subtitleScanFinished ? "Scan Again" : "Refresh") {\n                            player.requestSubtitleMenu()\n                        }\n                        .buttonStyle(.bordered)\n                    }\n                    .padding(.vertical, 10)\n                } else {\n'''
if old not in text:
    raise SystemExit('subtitle empty UI block not found')
text = text.replace(old, new, 1)

# Broaden subtitle menu extraction. Once the hidden CC menu is open, collect real clickable rows
# even when FrameXTV uses flags, short codes, or labels not covered by our language regex.
start = text.find('      function scanSubtitles() {')
end = text.find('\n      function parseServerRow', start)
if start == -1 or end == -1:
    raise SystemExit('scanSubtitles function bounds not found')

new_scan = r'''      function scanSubtitles() {
        const items = [];
        const seen = new Set();
        const v = video || findVideo();

        function normalizedLabel(raw) {
          return String(raw || '').replace(/\s+/g,' ').replace(/^[-•·]+|[-•·]+$/g,'').trim();
        }

        function add(id,index,label,language,source) {
          let l = normalizedLabel(label);
          let lang = String(language || '').trim();
          if (!l && lang) l = languageName(lang);
          if (!l && !lang) return;
          if (/^(subtitles?|captions?|closed captions?|cc|off|none|default|auto|settings?|back|close|done)$/i.test(l)) return;
          if (l.length > 80) return;
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

        // Prefer rows inside an actual menu/dialog/listbox. This catches labels such as AR, EN,
        // flag-prefixed language names, provider labels, and other real source wording.
        try {
          const roots = Array.from(document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="subtitle" i],[class*="caption" i]'));
          roots.forEach((root,ri) => {
            Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label')).forEach((el,i) => {
              const text = normalizedLabel(cleanText(el));
              if (!text) return;
              add('menu-'+ri+'-'+i,null,text,'','dom');
            });
          });
        } catch (_) {}

        // Fallback: collect compact clickable rows while a subtitle menu is open.
        try {
          Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label')).forEach((el,i) => {
            const text = normalizedLabel(cleanText(el));
            if (!text || text.length > 60) return;
            const meta = (String(el.getAttribute('aria-label')||'')+' '+String(el.getAttribute('title')||'')+' '+String(el.className||'')+' '+text).toLowerCase();
            if (looksLikeLanguage(text) || /subtitle|caption|language|track|flag/.test(meta) || /^(ar|ara|en|eng|es|spa|fr|fra|de|it|pt|tr|ru|ja|ko|zh|hi|ur)$/i.test(text)) {
              add('row-'+i,null,text,'','dom');
            }
          });
        } catch (_) {}

        bridge({event:'xs:subtitles',items:items});
      }
'''
text = text[:start] + new_scan + text[end:]

# Make subtitle-menu discovery more tolerant of icon-only controls and CC SVG markup.
old = '''      function openSubtitleMenu() {\n        try {\n          const nodes = Array.from(document.querySelectorAll('button,[role="button"]'));\n          const found = nodes.find(el => {\n            const meta = (String(el.getAttribute('aria-label') || '') + ' ' + String(el.getAttribute('title') || '') + ' ' + String(el.getAttribute('class') || '') + ' ' + String(el.innerHTML || '') + ' ' + cleanText(el)).toLowerCase();\n            return /subtitle|caption|\\bcc\\b/.test(meta);\n          });\n          if (found) { found.click(); return true; }\n        } catch (_) {}\n        return false;\n      }\n'''
new = '''      function openSubtitleMenu() {\n        try {\n          const nodes = Array.from(document.querySelectorAll('button,[role="button"]'));\n          const found = nodes.find(el => {\n            const meta = (String(el.getAttribute('aria-label') || '') + ' ' + String(el.getAttribute('title') || '') + ' ' + String(el.getAttribute('data-testid') || '') + ' ' + String(el.getAttribute('class') || '') + ' ' + String(el.innerHTML || '') + ' ' + cleanText(el)).toLowerCase();\n            return /subtitle|caption|closed.?caption|\\bcc\\b|captions\.bubble|message|speech/.test(meta);\n          });\n          if (found) { found.click(); return true; }\n        } catch (_) {}\n        return false;\n      }\n'''
if old not in text:
    raise SystemExit('openSubtitleMenu v8 block not found')
text = text.replace(old, new, 1)

# Give the menu enough time to animate/open, then always emit a final scan result.
old = '''      function openAndScanSubtitles() {\n        let alreadyOpen = false;\n        try {\n          alreadyOpen = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div')).some(el => looksLikeLanguage(cleanText(el)));\n        } catch (_) {}\n        if (!alreadyOpen) openSubtitleMenu();\n        setTimeout(scanSubtitles,120);\n        setTimeout(scanSubtitles,350);\n        setTimeout(scanSubtitles,700);\n      }\n'''
new = '''      function openAndScanSubtitles() {\n        let alreadyOpen = false;\n        try {\n          alreadyOpen = Array.from(document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="subtitle" i],[class*="caption" i]')).length > 0;\n        } catch (_) {}\n        if (!alreadyOpen) openSubtitleMenu();\n        setTimeout(scanSubtitles,160);\n        setTimeout(scanSubtitles,450);\n        setTimeout(scanSubtitles,900);\n        setTimeout(scanSubtitles,1400);\n      }\n'''
if old not in text:
    raise SystemExit('openAndScanSubtitles v8 block not found')
text = text.replace(old, new, 1)

path.write_text(text)
print('Applied XS Player V9 subtitle discovery and tap toggle fix')
