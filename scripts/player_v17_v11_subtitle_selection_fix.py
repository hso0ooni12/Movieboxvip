from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V17 intentionally starts from V11 behavior. V11 is the last on-device version
# known to render subtitles, but it trusted network metadata array indexes and could
# activate the wrong language or two renderers at once. Fix only selection semantics.

start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V17 subtitle command bounds not found')

block = r'''          else if (action === 'subtitle') {
            const wantedID = String(payload.id || '');
            const wantedLabel = normalizeSubtitleLabel(String(payload.label || selectedDomSubtitle || ''));
            const wantedLanguage = String(payload.language || '').trim();
            const source = String(payload.source || '').toLowerCase();
            const requestedIndex = Number(payload.index);

            function norm(value) {
              return normalizeSubtitleLabel(String(value || '')).toLowerCase();
            }

            function aliases(label, language) {
              const raw = [norm(label), norm(language)].filter(Boolean);
              const groups = [
                ['ar','ara','arabic','العربية','عربي'],
                ['en','eng','english','الإنجليزية','انجليزي','إنجليزي'],
                ['it','ita','italian','italiano'],
                ['fi','fin','finnish','suomi'],
                ['es','spa','spanish','español'],
                ['fr','fra','french','français'],
                ['de','deu','ger','german','deutsch'],
                ['pt','por','portuguese','português'],
                ['tr','tur','turkish','türkçe'],
                ['ru','rus','russian','русский'],
                ['ja','jpn','japanese','日本語'],
                ['ko','kor','korean','한국어'],
                ['zh','zho','chi','chinese','中文'],
                ['nl','nld','dutch','nederlands'],
                ['pl','pol','polish','polski'],
                ['sv','swe','swedish','svenska'],
                ['no','nor','norwegian','norsk'],
                ['da','dan','danish','dansk'],
                ['el','gre','ell','greek','ελληνικά'],
                ['he','heb','hebrew','עברית']
              ];
              for (const g of groups) {
                if (raw.some(r => g.some(a => r === a || (a.length > 2 && r.includes(a))))) return g;
              }
              return raw;
            }

            function disableAllTracks() {
              subtitleIndex = -1;
              lastCaption = '';
              try {
                if (v && v.textTracks) {
                  for (let i=0;i<v.textTracks.length;i++) {
                    try { v.textTracks[i].mode = 'disabled'; } catch (_) {}
                  }
                }
              } catch (_) {}
              bridge({event:'xs:caption',text:''});
            }

            function exactTextTrackIndex() {
              if (!v || !v.textTracks) return -1;
              const wanted = aliases(wantedLabel,wantedLanguage);
              let best = -1;
              let bestScore = -1;
              for (let i=0;i<v.textTracks.length;i++) {
                const t = v.textTracks[i];
                const tl = norm(t.label || '');
                const lang = norm(t.language || '');
                let score = 0;
                if (norm(wantedLabel) && tl === norm(wantedLabel)) score = 100;
                if (norm(wantedLanguage) && lang === norm(wantedLanguage)) score = Math.max(score,100);
                for (const a of wanted) {
                  if (!a) continue;
                  if (tl === a || lang === a) score = Math.max(score,98);
                  else if (a.length > 2 && (tl.includes(a) || lang.includes(a))) score = Math.max(score,90);
                }
                if (score > bestScore) { bestScore=score; best=i; }
              }
              return bestScore >= 90 ? best : -1;
            }

            function clickExactSubtitleRow() {
              const wanted = aliases(wantedLabel,wantedLanguage);
              const nodes = Array.from(document.querySelectorAll(
                '[role="menuitem"],[role="option"],button,[role="button"],li,label,[data-language],[lang]'
              ));
              let best = null;
              let bestScore = -1;
              for (const el of nodes) {
                const text = norm(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title') || '');
                const lang = norm(el.getAttribute('data-language') || el.getAttribute('lang') || '');
                if (!text && !lang) continue;
                if (/^(off|none|subtitles?|captions?|cc|settings?|back|close|done)$/i.test(text)) continue;
                let score = 0;
                if (norm(wantedLabel) && text === norm(wantedLabel)) score = 100;
                if (norm(wantedLanguage) && lang === norm(wantedLanguage)) score = Math.max(score,100);
                for (const a of wanted) {
                  if (!a) continue;
                  if (text === a || lang === a) score = Math.max(score,99);
                  else if (a.length > 2 && (text.includes(a) || lang.includes(a))) score = Math.max(score,92);
                }
                if (score > bestScore) { bestScore=score; best=el; }
              }
              if (!best || bestScore < 92) return false;
              const clickable = best.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || best;
              try {
                clickable.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,cancelable:true}));
                clickable.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
                clickable.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,cancelable:true}));
                clickable.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true}));
              } catch (_) {}
              try { clickable.click(); } catch (_) { return false; }
              return true;
            }

            disableAllTracks();

            if (wantedID === 'off' || source === 'off') {
              selectedDomSubtitle = '';
              openSubtitleMenu();
              setTimeout(() => {
                const nodes = Array.from(document.querySelectorAll('[role="menuitem"],[role="option"],button,[role="button"],li,label'));
                const off = nodes.find(el => /^(off|none)$/i.test(norm(cleanText(el))));
                if (off) { try { (off.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || off).click(); } catch (_) {} }
              },120);
              bridge({event:'xs:subtitleSelected',id:'off'});
            } else {
              // First preference: a real HTML text track whose label/language matches the requested language.
              // V11's bug was trusting metadata index. Never use requestedIndex unless the track itself matches.
              const realIndex = exactTextTrackIndex();
              if (realIndex >= 0) {
                subtitleIndex = realIndex;
                selectedDomSubtitle = '';
                try {
                  for (let i=0;i<v.textTracks.length;i++) {
                    v.textTracks[i].mode = i === realIndex ? 'hidden' : 'disabled';
                  }
                } catch (_) {}
                reportCaption();
                bridge({event:'xs:subtitleSelected',id:wantedID});
              } else {
                // Network metadata tells us which languages exist, but its index is NOT authoritative.
                // Activate the exact language row in FrameXTV's own subtitle menu instead.
                selectedDomSubtitle = wantedLabel;
                openSubtitleMenu();
                setTimeout(() => {
                  hideSourcePanels();
                  let ok = clickExactSubtitleRow();
                  if (ok) {
                    bridge({event:'xs:subtitleSelected',id:wantedID});
                    return;
                  }
                  openSubtitleMenu();
                  setTimeout(() => {
                    hideSourcePanels();
                    ok = clickExactSubtitleRow();
                    if (ok) bridge({event:'xs:subtitleSelected',id:wantedID});
                    else bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:wantedLabel,language:wantedLanguage});
                  },260);
                },180);
              }
            }
          }
'''

text = text[:start] + block + text[end:]
path.write_text(text)
print('Applied V17: V11 subtitle engine with deterministic single-language selection')
