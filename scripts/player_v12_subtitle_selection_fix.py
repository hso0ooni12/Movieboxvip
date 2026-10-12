from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# Prefer actionable subtitle sources over metadata-only duplicates.
start = text.find('    private func dedupeSubtitles(_ input: [XSSubtitleOption]) -> [XSSubtitleOption] {')
end = text.find('\n    private func send(_ payload:', start)
if start == -1 or end == -1:
    raise SystemExit('dedupeSubtitles bounds not found')

new_dedupe = r'''    private func dedupeSubtitles(_ input: [XSSubtitleOption]) -> [XSSubtitleOption] {
        func canonicalLanguage(_ item: XSSubtitleOption) -> String {
            let raw = (item.language.isEmpty ? item.displayName : item.language)
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let map: [String: String] = [
                "ar":"arabic","ara":"arabic","arabic":"arabic","العربية":"arabic","عربي":"arabic",
                "en":"english","eng":"english","english":"english",
                "fi":"finnish","fin":"finnish","finnish":"finnish",
                "es":"spanish","spa":"spanish","spanish":"spanish","español":"spanish",
                "fr":"french","fra":"french","french":"french","français":"french",
                "de":"german","deu":"german","german":"german","deutsch":"german",
                "it":"italian","ita":"italian","italian":"italian","italiano":"italian",
                "pt":"portuguese","por":"portuguese","portuguese":"portuguese","português":"portuguese",
                "tr":"turkish","tur":"turkish","turkish":"turkish","türkçe":"turkish",
                "ru":"russian","rus":"russian","russian":"russian","русский":"russian",
                "ja":"japanese","jpn":"japanese","japanese":"japanese","日本語":"japanese",
                "ko":"korean","kor":"korean","korean":"korean","한국어":"korean",
                "zh":"chinese","zho":"chinese","chinese":"chinese","中文":"chinese"
            ]
            if let hit = map[raw] { return hit }
            for (k,v) in map where raw.contains(k) && k.count > 2 { return v }
            return raw.replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
        }

        func priority(_ source: String) -> Int {
            switch source.lowercased() {
            case "dom": return 40
            case "texttrack": return 30
            case "tracktag": return 25
            case "network": return 10
            default: return 0
            }
        }

        var best: [String: XSSubtitleOption] = [:]
        var order: [String] = []
        for item in input {
            let key = canonicalLanguage(item).isEmpty ? item.displayName.lowercased() : canonicalLanguage(item)
            if let existing = best[key] {
                if priority(item.source) > priority(existing.source) { best[key] = item }
            } else {
                best[key] = item
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }
'''
text = text[:start] + new_dedupe + text[end:]

# Merge successive discoveries so a later DOM/textTrack source can replace a metadata-only row.
old = '            if !parsed.isEmpty { subtitleOptions = dedupeSubtitles(parsed) }\n'
new = '            if !parsed.isEmpty { subtitleOptions = dedupeSubtitles(subtitleOptions + parsed) }\n'
if old not in text:
    raise SystemExit('subtitle parsed assignment not found')
text = text.replace(old, new, 1)

# Replace the subtitle command block wholesale. Metadata indices are not trusted.
start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('subtitle command bounds not found')

subtitle_block = r'''          else if (action === 'subtitle') {
            const source = String(payload.source || '').toLowerCase();
            const label = String(payload.label || '').trim();
            const language = String(payload.language || '').trim();
            const idx = Number(payload.index);

            function disableCustomTracks() {
              subtitleIndex = -1;
              selectedDomSubtitle = '';
              lastCaption = '';
              try {
                if (v && v.textTracks) {
                  for (let i=0;i<v.textTracks.length;i++) v.textTracks[i].mode='disabled';
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
                clickable.click();
                return true;
              }
              return false;
            }

            // Always clear both rendering paths first. This prevents two subtitle languages at once.
            disableCustomTracks();
            try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch (_) {}

            if (source === 'off' || String(payload.id || '') === 'off') {
              openSubtitleMenu();
              setTimeout(() => selectByText('Off'),120);
              bridge({event:'xs:subtitleSelected',id:'off'});
            }
            else if ((source === 'texttrack' || source === 'tracktag') && Number.isFinite(idx) && idx >= 0 && v && v.textTracks && idx < v.textTracks.length) {
              // Direct HTML text track: keep FrameXTV subtitles OFF and render exactly one hidden track through XS.
              subtitleIndex = idx;
              for (let i=0;i<v.textTracks.length;i++) {
                try { v.textTracks[i].mode = i === idx ? 'hidden' : 'disabled'; } catch (_) {}
              }
              bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
            }
            else {
              // Network/DOM metadata index is NOT authoritative. Match the real FrameXTV menu by language/name.
              openSubtitleMenu();
              setTimeout(() => {
                hideSourcePanels();
                let ok = chooseSourceSubtitle(label, language);
                if (!ok) {
                  // Open once more in case the menu animation/provider load was late.
                  openSubtitleMenu();
                  setTimeout(() => {
                    hideSourcePanels();
                    ok = chooseSourceSubtitle(label, language);
                    if (ok) bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
                    else bridge({event:'xs:subtitleSelectionFailed',id:String(payload.id || ''),label:label,language:language});
                  },260);
                } else {
                  bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
                }
              },180);
            }
          }
'''
text = text[:start] + subtitle_block + text[end:]

# Ensure source-rendered captions are not hidden by source-panel cleanup. Only hide large dialogs.
# Also never style source captions when XS custom track is inactive; this avoids touching provider subtitle layers.
old = '''          Array.from(document.querySelectorAll('[class*="subtitle" i],[class*="caption" i]')).forEach(el => {
            if (el.closest('button,[role="button"],[role="dialog"]')) return;
            el.style.setProperty('font-size',px+'px','important');
            el.style.setProperty('color',subtitleStyle.color,'important');
            el.style.setProperty('font-weight','700','important');
          });
'''
new = '''          if (subtitleIndex >= 0) {
            Array.from(document.querySelectorAll('[class*="subtitle" i],[class*="caption" i]')).forEach(el => {
              if (el.closest('button,[role="button"],[role="dialog"]')) return;
              el.style.setProperty('font-size',px+'px','important');
              el.style.setProperty('color',subtitleStyle.color,'important');
              el.style.setProperty('font-weight','700','important');
            });
          }
'''
if old in text:
    text = text.replace(old, new, 1)

path.write_text(text)
print('Applied XS Player V12 deterministic subtitle selection fix')
