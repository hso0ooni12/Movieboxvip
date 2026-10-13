from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V18 deliberately keeps the V11 discovery/server engine because V11 is the last
# device-tested build that actually rendered subtitles. We only replace subtitle
# activation: select the real FrameXTV subtitle row (ara/eng/ita/etc.) first, and
# never run XS's custom caption renderer at the same time as the source renderer.

start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V18 subtitle command bounds not found')

block = r'''          else if (action === 'subtitle') {
            const wantedID = String(payload.id || '');
            const wantedLabel = normalizeSubtitleLabel(String(payload.label || selectedDomSubtitle || ''));
            const requestedIndex = Number(payload.index);

            function n(v) { return normalizeSubtitleLabel(String(v || '')).toLowerCase(); }

            function languageKeys(label) {
              const s = n(label);
              const groups = [
                ['ara','ar','arabic','العربية','عربي'],
                ['eng','en','english','الإنجليزية','انجليزي','إنجليزي'],
                ['ita','it','italian','italiano'],
                ['fin','fi','finnish','suomi'],
                ['bul','bg','bulgarian','български'],
                ['chi','zho','zh','chinese','中文'],
                ['cze','ces','cs','czech','čeština'],
                ['dan','da','danish','dansk'],
                ['ger','deu','de','german','deutsch'],
                ['spa','es','spanish','español'],
                ['fre','fra','fr','french','français'],
                ['por','pt','portuguese','português'],
                ['tur','tr','turkish','türkçe'],
                ['rus','ru','russian','русский'],
                ['jpn','ja','japanese','日本語'],
                ['kor','ko','korean','한국어'],
                ['dut','nld','nl','dutch','nederlands'],
                ['pol','pl','polish','polski'],
                ['swe','sv','swedish','svenska'],
                ['nor','no','norwegian','norsk'],
                ['gre','ell','el','greek','ελληνικά'],
                ['heb','he','hebrew','עברית'],
                ['ukr','uk','ukrainian','українська'],
                ['vie','vi','vietnamese','tiếng việt'],
                ['ind','id','indonesian','bahasa indonesia']
              ];
              for (const g of groups) {
                if (g.some(k => s === k || (k.length > 2 && s.includes(k)))) return g;
              }
              return s ? [s] : [];
            }

            function stopXSRenderer() {
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

            function restoreSubtitlePanel() {
              try {
                Array.from(document.querySelectorAll('body *')).forEach(el => {
                  const t = n(cleanText(el));
                  if (!t || t.length > 100) return;
                  if (t === 'subtitles' || t === 'captions' || t === 'select subtitle' || languageKeys(t).length) {
                    let p = el;
                    for (let i=0;i<5 && p;i++,p=p.parentElement) {
                      try {
                        if (p.style) {
                          p.style.removeProperty('visibility');
                          p.style.removeProperty('pointer-events');
                          p.style.removeProperty('opacity');
                        }
                      } catch (_) {}
                    }
                  }
                });
              } catch (_) {}
            }

            function findExactSourceRow(keys) {
              const nodes = Array.from(document.querySelectorAll(
                '[role="menuitem"],[role="option"],button,[role="button"],li,label,[data-language],[lang],div'
              ));
              let best = null, bestScore = -1;
              for (const el of nodes) {
                const txt = n(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title') || '');
                const lang = n(el.getAttribute('data-language') || el.getAttribute('lang') || '');
                if (!txt && !lang) continue;
                if (txt.length > 70) continue;
                if (/^(off|none|subtitles?|captions?|cc|settings?|back|close|done)$/i.test(txt)) continue;
                let score = 0;
                for (const k of keys) {
                  if (txt === k || lang === k) score = Math.max(score, 120);
                  else if (k.length > 2 && (txt.includes(k) || lang.includes(k))) score = Math.max(score, 105);
                  else if (txt === ('subtitles - ' + k) || txt === ('subtitle - ' + k)) score = Math.max(score, 115);
                }
                if (score > bestScore) { bestScore = score; best = el; }
              }
              if (!best || bestScore < 105) return null;
              return best.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || best;
            }

            function sourceSelect(label, completion) {
              const keys = languageKeys(label);
              restoreSubtitlePanel();
              openSubtitleMenu();
              setTimeout(() => {
                restoreSubtitlePanel();
                const row = findExactSourceRow(keys);
                if (!row) { completion(false); return; }
                try {
                  row.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true}));
                } catch (_) {}
                try { row.click(); } catch (_) { completion(false); return; }
                setTimeout(() => { try { hideSourcePanels(); } catch (_) {}; completion(true); }, 120);
              }, 140);
            }

            stopXSRenderer();

            if (wantedID === 'off' || n(wantedLabel) === 'off') {
              selectedDomSubtitle = '';
              restoreSubtitlePanel();
              openSubtitleMenu();
              setTimeout(() => {
                const nodes = Array.from(document.querySelectorAll('[role="menuitem"],[role="option"],button,[role="button"],li,label,div'));
                const off = nodes.find(el => /^(off|none)$/i.test(n(cleanText(el))));
                if (off) {
                  try { (off.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || off).click(); } catch (_) {}
                }
                try { hideSourcePanels(); } catch (_) {}
                bridge({event:'xs:subtitleSelected',id:'off'});
              },140);
            } else {
              selectedDomSubtitle = wantedLabel;
              sourceSelect(wantedLabel, ok => {
                if (ok) {
                  // Source player now owns subtitle rendering; keep XS renderer OFF.
                  bridge({event:'xs:subtitleSelected',id:wantedID});
                  return;
                }

                // V11 fallback: preserve the only path proven on-device to render subtitles.
                // Do not enable XS custom cues here, otherwise source + XS can render twice.
                if (Number.isFinite(requestedIndex) && requestedIndex >= 0) {
                  try { window.postMessage({action:'setSubtitle',index:requestedIndex},'*'); } catch (_) {}
                  setTimeout(() => bridge({event:'xs:subtitleSelected',id:wantedID}),120);
                } else {
                  bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:wantedLabel});
                }
              });
            }
          }
'''

text = text[:start] + block + text[end:]
path.write_text(text)
print('Applied V18: V11 source-row subtitle selection with single renderer')
