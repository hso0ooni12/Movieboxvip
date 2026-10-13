from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V17 deliberately starts from the working V11 runtime and changes only subtitle
# activation. Do NOT apply V12+ patches before this script.

start = text.find("          else if (action === 'subtitle') {")
end = text.find("\n          else if (action === 'server') {", start)
if start == -1 or end == -1:
    raise SystemExit('V17 could not find V11 subtitle action block')

block = r'''          else if (action === 'subtitle') {
            const requestedLabel = String(payload.label || '').trim();
            const requestedLanguage = String(payload.language || '').trim();
            const requestedID = String(payload.id || '');

            function normalizeLangToken(raw) {
              return String(raw || '').toLowerCase().trim().replace(/[_-].*$/,'');
            }

            function aliases(raw) {
              const v = normalizeLangToken(raw);
              const groups = [
                ['ar','ara','arabic','العربية','عربي'],
                ['en','eng','english'],
                ['it','ita','italian','italiano'],
                ['es','spa','spanish','español'],
                ['fr','fra','french','français'],
                ['de','deu','ger','german','deutsch'],
                ['pt','por','portuguese','português'],
                ['tr','tur','turkish','türkçe'],
                ['ru','rus','russian','русский'],
                ['fi','fin','finnish','suomi'],
                ['nl','nld','dut','dutch','nederlands'],
                ['pl','pol','polish','polski'],
                ['sv','swe','swedish','svenska'],
                ['no','nor','norwegian','norsk'],
                ['da','dan','danish','dansk'],
                ['el','gre','ell','greek','ελληνικά'],
                ['he','heb','hebrew','עברית'],
                ['ja','jpn','japanese','日本語'],
                ['ko','kor','korean','한국어'],
                ['zh','zho','chi','chinese','中文'],
                ['hi','hin','hindi'],
                ['ur','urd','urdu']
              ];
              for (const g of groups) {
                if (g.some(x => v === x || (x.length > 2 && v.includes(x)))) return g;
              }
              return v ? [v] : [];
            }

            function stopEverySubtitle() {
              subtitleIndex = -1;
              selectedDomSubtitle = '';
              lastCaption = '';
              try {
                if (v && v.textTracks) {
                  for (let i=0;i<v.textTracks.length;i++) {
                    try { v.textTracks[i].mode = 'disabled'; } catch (_) {}
                  }
                }
              } catch (_) {}
              try { window.postMessage({action:'setSubtitle',index:-1},'*'); } catch (_) {}
              bridge({event:'xs:caption',text:''});
            }

            function scoreTrack(track, i) {
              const label = String((track && track.label) || '').toLowerCase().trim();
              const lang = normalizeLangToken((track && track.language) || '');
              const wantedLabel = requestedLabel.toLowerCase().trim();
              const wantedAliases = Array.from(new Set([
                ...aliases(requestedLanguage),
                ...aliases(requestedLabel)
              ]));
              let score = 0;
              if (wantedLabel && label === wantedLabel) score = 120;
              else if (wantedLabel && (label.includes(wantedLabel) || wantedLabel.includes(label))) score = 95;
              for (const a of wantedAliases) {
                if (!a) continue;
                if (lang === a) score = Math.max(score, 115);
                if (label === a) score = Math.max(score, 110);
                if (a.length > 2 && label.includes(a)) score = Math.max(score, 100);
              }
              // V11 network index is only a weak tie-breaker, never authoritative.
              const hinted = Number(payload.index);
              if (Number.isFinite(hinted) && hinted === i) score += 2;
              return score;
            }

            function activateNativeTextTrack() {
              if (!v || !v.textTracks || !v.textTracks.length) return false;
              let best = -1;
              let bestScore = -1;
              for (let i=0;i<v.textTracks.length;i++) {
                const s = scoreTrack(v.textTracks[i], i);
                if (s > bestScore) { bestScore = s; best = i; }
              }
              if (best < 0 || bestScore < 80) return false;
              stopEverySubtitle();
              subtitleIndex = best;
              try {
                for (let i=0;i<v.textTracks.length;i++) {
                  v.textTracks[i].mode = i === best ? 'hidden' : 'disabled';
                }
              } catch (_) {}
              try { window.postMessage({action:'setSubtitle',index:best},'*'); } catch (_) {}
              bridge({event:'xs:subtitleSelected',id:requestedID});
              return true;
            }

            function scoreDomNode(el) {
              const txt = normalizeSubtitleLabel(cleanText(el) || el.getAttribute('aria-label') || el.getAttribute('title') || el.getAttribute('data-language') || el.getAttribute('lang')).toLowerCase();
              if (!txt) return 0;
              if (/^(off|none|subtitles?|captions?|closed captions?|cc|settings?|back|close|done)$/i.test(txt)) return 0;
              const wantedLabel = requestedLabel.toLowerCase().trim();
              const wantedAliases = Array.from(new Set([
                ...aliases(requestedLanguage),
                ...aliases(requestedLabel)
              ]));
              let score = 0;
              if (wantedLabel && txt === wantedLabel) score = 120;
              else if (wantedLabel && (txt.includes(wantedLabel) || wantedLabel.includes(txt))) score = 95;
              for (const a of wantedAliases) {
                if (!a) continue;
                if (txt === a) score = Math.max(score,115);
                else if (a.length > 2 && txt.includes(a)) score = Math.max(score,105);
              }
              return score;
            }

            function clickExactLanguageFromSource() {
              try {
                const nodes = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],[role="option"],li,label,[data-language],[lang]'));
                let best = null;
                let bestScore = 0;
                for (const el of nodes) {
                  const s = scoreDomNode(el);
                  if (s > bestScore) { bestScore = s; best = el; }
                }
                if (!best || bestScore < 80) return false;
                stopEverySubtitle();
                const clickable = best.closest('button,[role="button"],[role="menuitem"],[role="option"],li') || best;
                try {
                  ['pointerdown','mousedown','pointerup','mouseup'].forEach(type => clickable.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,view:window})));
                } catch (_) {}
                clickable.click();
                bridge({event:'xs:subtitleSelected',id:requestedID});
                return true;
              } catch (_) { return false; }
            }

            if (requestedID === 'off' || String(payload.source || '').toLowerCase() === 'off') {
              stopEverySubtitle();
              openSubtitleMenu();
              setTimeout(() => { selectByText('Off'); hideSourcePanels(); },100);
              bridge({event:'xs:subtitleSelected',id:'off'});
            } else if (!activateNativeTextTrack()) {
              // This preserves the V11 path that actually produced subtitles on-device,
              // but selects by language/label instead of V11's unstable network index.
              openSubtitleMenu();
              setTimeout(() => {
                hideSourcePanels();
                if (clickExactLanguageFromSource()) return;
                openSubtitleMenu();
                setTimeout(() => {
                  hideSourcePanels();
                  if (!clickExactLanguageFromSource()) {
                    bridge({event:'xs:subtitleSelectionFailed',id:requestedID,label:requestedLabel,language:requestedLanguage});
                  }
                },260);
              },180);
            }
          }
'''

text = text[:start] + block + text[end:]

# Do not mark selection optimistically in Swift. Wait for xs:subtitleSelected from JS.
old = '''    func selectSubtitle(_ option: XSSubtitleOption) {
        selectedSubtitleID = option.id
        send(["action": "subtitle", "id": option.id, "index": option.index as Any, "label": option.label, "language": option.language, "source": option.source])
    }
'''
new = '''    func selectSubtitle(_ option: XSSubtitleOption) {
        captionText = ""
        send(["action": "subtitle", "id": option.id, "index": option.index as Any, "label": option.label, "language": option.language, "source": option.source])
    }
'''
if old in text:
    text = text.replace(old, new, 1)

# Ensure Swift accepts confirmation/failure from the V11 bridge.
anchor = '        default:\n            break\n'
if anchor in text and 'case "xs:subtitleSelected":' not in text:
    cases = '''        case "xs:subtitleSelected":
            if let id = payload["id"] as? String { selectedSubtitleID = id }
            errorMessage = nil

        case "xs:subtitleSelectionFailed":
            errorMessage = "That subtitle could not be activated."

'''
    text = text.replace(anchor, cases + anchor, 1)

path.write_text(text)
print('Applied V17 V11-based deterministic subtitle selection')
