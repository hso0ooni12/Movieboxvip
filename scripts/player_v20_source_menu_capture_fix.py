from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V20 fixes V19's race with V11 hideSourcePanels(): while opening/reading the
# ORIGINAL FrameXTV subtitle menu we temporarily suspend source-panel hiding.
# It also discovers generic menu containers instead of assuming subtitle-specific
# CSS classes/ARIA roles.

text = text.replace(
    '      function hideSourcePanels() {\n',
    '      function hideSourcePanels() {\n        try { if (window.__xsSubtitleCaptureLock) return; } catch (_) {}\n',
    1
)

start = text.find('      function xsSubtitleRoot() {')
end = text.find('\n      function xsOriginalSubtitleRows() {', start)
if start == -1 or end == -1:
    raise SystemExit('V20 xsSubtitleRoot bounds not found')

root_fn = r'''      function xsLooksLikeSubtitleRow(el) {
        const raw = xsRawLabel(el);
        if (!raw || raw.length > 52) return false;
        const low = raw.toLowerCase();
        if (/^(off|none|subtitles?|captions?|closed captions?|cc|settings?|back|close|done|cancel)$/i.test(low)) return false;
        // Source menus commonly use ISO language codes (ara/eng/ita) or language names.
        // We do NOT translate/invent these labels; this only helps identify the live menu.
        if (/^[a-z]{2,4}(?:[-_][a-z]{2,4})?$/i.test(raw)) return true;
        if (el.hasAttribute && (el.hasAttribute('data-language') || el.hasAttribute('lang'))) return true;
        return /^[A-Za-zÀ-ÿА-Яа-я一-龥ぁ-んァ-ン가-힣\u0600-\u06FF][^<>]{1,40}$/.test(raw);
      }

      function xsClickableRows(root) {
        if (!root) return [];
        try {
          return Array.from(root.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label,[data-language],[lang]'))
            .filter(xsLooksLikeSubtitleRow);
        } catch (_) { return []; }
      }

      function xsSubtitleRoot() {
        // First anchor on the source player's own Subtitles/Captions heading, then
        // climb to the smallest ancestor that contains multiple real option rows.
        try {
          const all = Array.from(document.querySelectorAll('body *'));
          const headers = all.filter(el => {
            const t = xsRawLabel(el).toLowerCase();
            return /^(subtitles?|captions?|closed captions?|select subtitle|select subtitles)$/.test(t);
          });
          for (const header of headers) {
            let p = header.parentElement;
            for (let depth=0; depth<8 && p; depth++, p=p.parentElement) {
              const rows = xsClickableRows(p);
              if (rows.length >= 2 && rows.length <= 80) return p;
            }
          }
        } catch (_) {}

        // Fallback: score any dialog/menu/listbox/popover plus generic containers.
        const candidates = [];
        try {
          document.querySelectorAll('[role="dialog"],[role="menu"],[role="listbox"],[class*="popover" i],[class*="menu" i],[class*="dropdown" i],[class*="subtitle" i],[class*="caption" i]').forEach(el => candidates.push(el));
        } catch (_) {}
        let best = null, bestScore = -1;
        for (const root of candidates) {
          const rows = xsClickableRows(root);
          if (rows.length < 2 || rows.length > 80) continue;
          let score = rows.length * 4;
          const body = xsRawLabel(root).toLowerCase();
          if (/subtitles?|captions?|closed captions?/.test(body)) score += 40;
          try {
            const r = root.getBoundingClientRect();
            if (r.width > 120 && r.height > 80) score += 5;
          } catch (_) {}
          if (score > bestScore) { bestScore = score; best = root; }
        }
        return best;
      }
'''
text = text[:start] + root_fn + text[end:]

start = text.find('      function openAndScanSubtitles() {')
end = text.find('\n      function reportCaption', start)
if start == -1 or end == -1:
    raise SystemExit('V20 openAndScanSubtitles bounds not found')

open_scan = r'''      function openAndScanSubtitles() {
        window.__xsSubtitleCaptureLock = true;
        xsRestoreSubtitlePanels();
        openSubtitleMenu();
        const passes = [120,280,520,850,1250,1750];
        passes.forEach((ms,idx) => setTimeout(() => {
          xsRestoreSubtitlePanels();
          scanSubtitles(idx === passes.length - 1);
          if (idx === passes.length - 1) {
            window.__xsSubtitleCaptureLock = false;
            try { hideSourcePanels(); } catch (_) {}
          }
        }, ms));
      }
'''
text = text[:start] + open_scan + text[end:]

# Replace V19 subtitle action with the same exact-row behavior, but keep the
# source menu visible internally until the row is actually clicked.
start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V20 subtitle action bounds not found')

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
            window.__xsSubtitleCaptureLock = true;
            xsRestoreSubtitlePanels();
            openSubtitleMenu();

            if (wantedID === 'off' || wantedLabel.toLowerCase() === 'off') {
              selectedDomSubtitle = '';
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
                window.__xsSubtitleCaptureLock = false;
                try { hideSourcePanels(); } catch (_) {}
                bridge({event:'xs:subtitleSelected',id:'off'});
              },220);
            } else {
              selectedDomSubtitle = wantedLabel;
              const attempt = (n) => {
                setTimeout(() => {
                  xsRestoreSubtitlePanels();
                  if (clickOriginalRowExact(wantedLabel)) {
                    window.__xsSubtitleCaptureLock = false;
                    try { hideSourcePanels(); } catch (_) {}
                    bridge({event:'xs:subtitleSelected',id:wantedID});
                    return;
                  }
                  if (n < 2) {
                    openSubtitleMenu();
                    attempt(n + 1);
                  } else {
                    window.__xsSubtitleCaptureLock = false;
                    try { hideSourcePanels(); } catch (_) {}
                    bridge({event:'xs:subtitleSelectionFailed',id:wantedID,label:wantedLabel});
                  }
                }, n === 0 ? 220 : 320);
              };
              attempt(0);
            }
          }
'''
text = text[:start] + action + text[end:]

path.write_text(text)
print('Applied V20: reliable capture/click of the original FrameXTV subtitle menu')
