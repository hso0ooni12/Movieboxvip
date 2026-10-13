from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V19 principle: the XS subtitle list must be a mirror of FrameXTV's ORIGINAL
# subtitle menu. No network metadata language guesses, no invented aliases, no
# textTrack-derived list. We open the source menu, read its live rows verbatim,
# and later click that exact row text when the user chooses it.

# 1) Stop V11 network metadata from publishing subtitle options into XS UI.
old_publish = '''      function publishNetworkSubtitles() {
        if (networkSubtitleItems.length) bridge({event:'xs:subtitles',items:networkSubtitleItems,final:false});
      }
'''
new_publish = '''      function publishNetworkSubtitles() {
        // V19: network metadata is not authoritative for the user-facing list.
        // Only the live FrameXTV subtitle menu is allowed to populate XS subtitles.
      }
'''
if old_publish in text:
    text = text.replace(old_publish, new_publish, 1)

# 2) Replace subtitle discovery with a source-menu-only mirror.
start = text.find('      function scanSubtitles(')
end = text.find('\n      function parseServerRow', start)
if start == -1 or end == -1:
    raise SystemExit('V19 scanSubtitles bounds not found')

scanner = r'''      function xsRawLabel(el) {
        return String((el && (el.innerText || el.textContent || el.getAttribute('aria-label') || el.getAttribute('title'))) || '')
          .replace(/\s+/g,' ').trim();
      }

      function xsIsVisibleEnough(el) {
        try {
          const r = el.getBoundingClientRect();
          if (!r || r.width < 2 || r.height < 2) return false;
          const s = getComputedStyle(el);
          // FrameXTV panels may be made transparent by XS after scanning. Visibility
          // here is only used as a preference, not a hard requirement.
          return s.display !== 'none';
        } catch (_) { return true; }
      }

      function xsRestoreSubtitlePanels() {
        try {
          Array.from(document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="subtitle" i],[class*="caption" i],body *')).forEach(el => {
            const t = xsRawLabel(el).toLowerCase();
            if (!t || t.length > 140) return;
            if (/subtitles?|captions?|closed captions?/.test(t)) {
              let p = el;
              for (let i=0;i<5 && p;i++,p=p.parentElement) {
                try {
                  p.style.removeProperty('visibility');
                  p.style.removeProperty('pointer-events');
                  p.style.removeProperty('opacity');
                } catch (_) {}
              }
            }
          });
        } catch (_) {}
      }

      function xsSubtitleRoot() {
        const roots = [];
        try {
          document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="subtitle" i],[class*="caption" i]').forEach(el => roots.push(el));
        } catch (_) {}
        let best = null, bestScore = -1;
        for (const root of roots) {
          let score = 0;
          const body = xsRawLabel(root).toLowerCase();
          if (/subtitles?|captions?|closed captions?/.test(body)) score += 30;
          try {
            const rows = root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label,[data-language],[lang]');
            score += Math.min(rows.length, 30);
            for (const row of rows) {
              const raw = xsRawLabel(row);
              if (raw && raw.length <= 48) score += 1;
            }
          } catch (_) {}
          if (xsIsVisibleEnough(root)) score += 6;
          if (score > bestScore) { bestScore = score; best = root; }
        }
        return bestScore >= 8 ? best : null;
      }

      function xsOriginalSubtitleRows() {
        const root = xsSubtitleRoot();
        if (!root) return [];
        const rows = [];
        const seen = new Set();
        try {
          const nodes = Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label,[data-language],[lang]'));
          nodes.forEach((el,i) => {
            let raw = xsRawLabel(el);
            if (!raw || raw.length > 52) return;
            const low = raw.toLowerCase();
            if (/^(subtitles?|captions?|closed captions?|cc|settings?|back|close|done|cancel)$/i.test(low)) return;
            if (/^(off|none)$/i.test(low)) return; // XS already has an Off row.

            // Only mirror actual source menu rows. Never manufacture a language name.
            // A valid row can be a code (ara/eng), a language name, or whatever the
            // source player itself prints.
            const clickable = el.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || el;
            const key = raw.toLowerCase();
            if (seen.has(key)) return;
            seen.add(key);
            const selected = String(el.getAttribute('aria-selected') || '').toLowerCase() === 'true' ||
                             String(el.getAttribute('aria-checked') || '').toLowerCase() === 'true' ||
                             /selected|active|checked/i.test(String(el.className || ''));
            rows.push({id:'source-row-'+i,index:null,label:raw,language:'',source:'sourceMenu',selected:selected});
          });
        } catch (_) {}
        return rows;
      }

      function scanSubtitles(finalPass) {
        xsRestoreSubtitlePanels();
        const items = xsOriginalSubtitleRows();
        // Do not publish guessed/network/textTrack items. This list is an exact mirror
        // of what FrameXTV currently exposes for THIS content/server.
        if (items.length || finalPass) {
          bridge({event:'xs:subtitles',items:items,final:!!finalPass});
        }
      }
'''
text = text[:start] + scanner + text[end:]

# 3) Ensure opening CC reads source rows after the real source menu is opened.
start = text.find('      function openAndScanSubtitles() {')
end = text.find('\n      function reportCaption', start)
if start == -1 or end == -1:
    raise SystemExit('V19 openAndScanSubtitles bounds not found')
open_scan = r'''      function openAndScanSubtitles() {
        xsRestoreSubtitlePanels();
        openSubtitleMenu();
        setTimeout(() => { xsRestoreSubtitlePanels(); scanSubtitles(false); },180);
        setTimeout(() => { xsRestoreSubtitlePanels(); scanSubtitles(false); },420);
        setTimeout(() => { xsRestoreSubtitlePanels(); scanSubtitles(false); },800);
        setTimeout(() => { xsRestoreSubtitlePanels(); scanSubtitles(true); try { hideSourcePanels(); } catch (_) {} },1250);
      }
'''
text = text[:start] + open_scan + text[end:]

# 4) Replace V18 activation with exact source-row activation. No alias table, no index.
start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V19 subtitle action bounds not found')

action = r'''          else if (action === 'subtitle') {
            const wantedID = String(payload.id || '');
            const wantedLabel = String(payload.label || '').replace(/\s+/g,' ').trim();

            function stopAllXSCaptions() {
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

            function clickOriginalRowExact(label) {
              xsRestoreSubtitlePanels();
              const root = xsSubtitleRoot();
              if (!root) return false;
              const target = String(label || '').replace(/\s+/g,' ').trim().toLowerCase();
              if (!target) return false;
              try {
                const nodes = Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label,[data-language],[lang]'));
                let row = nodes.find(el => xsRawLabel(el).replace(/\s+/g,' ').trim().toLowerCase() === target);
                if (!row) return false;
                row = row.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || row;
                try {
                  row.dispatchEvent(new PointerEvent('pointerdown',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new MouseEvent('mousedown',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new PointerEvent('pointerup',{bubbles:true,cancelable:true}));
                  row.dispatchEvent(new MouseEvent('mouseup',{bubbles:true,cancelable:true}));
                } catch (_) {}
                row.click();
                return true;
              } catch (_) { return false; }
            }

            stopAllXSCaptions();

            if (wantedID === 'off' || wantedLabel.toLowerCase() === 'off') {
              selectedDomSubtitle = '';
              xsRestoreSubtitlePanels();
              openSubtitleMenu();
              setTimeout(() => {
                xsRestoreSubtitlePanels();
                const root = xsSubtitleRoot() || document;
                try {
                  const nodes = Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label'));
                  let off = nodes.find(el => /^(off|none)$/i.test(xsRawLabel(el)));
                  if (off) {
                    off = off.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || off;
                    off.click();
                  }
                } catch (_) {}
                try { hideSourcePanels(); } catch (_) {}
                bridge({event:'xs:subtitleSelected',id:'off'});
              },180);
            } else {
              selectedDomSubtitle = wantedLabel;
              xsRestoreSubtitlePanels();
              openSubtitleMenu();
              setTimeout(() => {
                xsRestoreSubtitlePanels();
                if (clickOriginalRowExact(wantedLabel)) {
                  try { hideSourcePanels(); } catch (_) {}
                  bridge({event:'xs:subtitleSelected',id:wantedID});
                  return;
                }
                // One retry after reopening the original menu, because some providers
                // rebuild the menu DOM after the first click.
                openSubtitleMenu();
                setTimeout(() => {
                  xsRestoreSubtitlePanels();
                  if (clickOriginalRowExact(wantedLabel)) {
                    try { hideSourcePanels(); } catch (_) {}
                    bridge({event:'xs:subtitleSelected',id:wantedID});
                  } else {
                    bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:wantedLabel});
                  }
                },240);
              },180);
            }
          }
'''
text = text[:start] + action + text[end:]

path.write_text(text)
print('Applied V19: subtitle list and selection are owned entirely by FrameXTV source menu')
