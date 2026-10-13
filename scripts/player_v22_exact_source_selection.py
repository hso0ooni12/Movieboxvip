from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V22 keeps V21 discovery because it is device-proven to expose the actual
# language choices. It replaces ONLY activation: never bind an inferred URL.
# Re-open FrameXTV's own subtitle menu and click the exact source row label the
# user selected. This lets FrameXTV own the label -> subtitle asset mapping.

start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V22 subtitle action block not found')

action = r'''          else if (action === 'subtitle') {
            const wantedID = String(payload.id || '');
            const wantedLabel = String(payload.label || '').replace(/\s+/g,' ').trim();
            const v = video || findVideo();

            function normalizeExactText(s) {
              return String(s || '').replace(/\s+/g,' ').trim().toLowerCase();
            }

            function clearXSOnly() {
              // Remove only tracks inserted by XS. Do NOT disable all source tracks;
              // FrameXTV must remain free to activate its own selected subtitle.
              selectedTrack = -1;
              selectedDomSubtitle = '';
              lastCaption = '';
              bridge({event:'xs:caption',text:''});
              try {
                document.querySelectorAll('track[data-xs-network-track="1"]').forEach(t => t.remove());
              } catch (_) {}
            }

            function restoreExactRow(label) {
              const target = normalizeExactText(label);
              if (!target) return;
              try {
                Array.from(document.querySelectorAll('body *')).forEach(el => {
                  const txt = normalizeExactText(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title') || '');
                  if (txt !== target) return;
                  let p = el;
                  for (let i=0;i<6 && p;i++,p=p.parentElement) {
                    try {
                      if (p.style) {
                        p.style.removeProperty('display');
                        p.style.removeProperty('visibility');
                        p.style.removeProperty('opacity');
                        p.style.removeProperty('pointer-events');
                      }
                    } catch (_) {}
                  }
                });
              } catch (_) {}
            }

            function clickExactSourceSubtitle(label) {
              const target = normalizeExactText(label);
              if (!target) return false;
              restoreExactRow(label);
              try {
                const selector = 'button,[role="button"],[role="menuitem"],[role="option"],li,label,[data-language],[lang],div,span';
                const nodes = Array.from(document.querySelectorAll(selector));
                let candidates = nodes.filter(el => {
                  const txt = normalizeExactText(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title') || '');
                  return txt === target;
                });
                if (!candidates.length) return false;

                // Prefer the smallest matching element: this is normally the actual
                // menu row, not a large parent whose text happens to contain it.
                candidates.sort((a,b) => {
                  try {
                    const ra=a.getBoundingClientRect(), rb=b.getBoundingClientRect();
                    return (ra.width*ra.height) - (rb.width*rb.height);
                  } catch (_) { return 0; }
                });
                let row = candidates[0];
                row = row.closest('button,[role="button"],[role="menuitem"],[role="option"],li,label') || row;
                try {
                  row.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true}));
                } catch (_) {}
                try { row.click(); } catch (_) { return false; }
                return true;
              } catch (_) { return false; }
            }

            function openThenSelectExact(label, attempt) {
              try { openSubtitleMenu(); } catch (_) {}
              const delays = attempt === 0 ? [140, 320, 620] : [180, 420];
              let done = false;
              delays.forEach((delay, idx) => {
                setTimeout(() => {
                  if (done) return;
                  restoreExactRow(label);
                  if (clickExactSourceSubtitle(label)) {
                    done = true;
                    setTimeout(() => {
                      try { hideSourcePanels(); } catch (_) {}
                      bridge({event:'xs:subtitleSelected',id:wantedID});
                    }, 100);
                  } else if (idx === delays.length - 1) {
                    if (attempt < 1) openThenSelectExact(label, attempt + 1);
                    else bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:label});
                  }
                }, delay);
              });
            }

            clearXSOnly();

            if (wantedID === 'off' || String(payload.source || '') === 'off' || normalizeExactText(wantedLabel) === 'off') {
              try { openSubtitleMenu(); } catch (_) {}
              setTimeout(() => {
                const offLabels = ['off','none'];
                let clicked = false;
                for (const label of offLabels) {
                  if (clickExactSourceSubtitle(label)) { clicked = true; break; }
                }
                if (!clicked) {
                  // Fallback for players exposing Off through their message API.
                  try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch (_) {}
                }
                try { hideSourcePanels(); } catch (_) {}
                bridge({event:'xs:subtitleSelected',id:'off'});
              },180);
            } else {
              // Critical V22 rule: never use networkSubtitleItems[index/url] to
              // activate a subtitle. The source player itself owns the mapping.
              openThenSelectExact(wantedLabel, 0);
            }
          }
'''

text = text[:start] + action + text[end:]
path.write_text(text)
print('Applied V22: exact FrameXTV source-row subtitle activation')
