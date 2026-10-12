from pathlib import Path
import re

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# Never fake server/subtitle state before the hidden source player confirms the action.
old = '''    func selectSubtitle(_ option: XSSubtitleOption?) {
        selectedSubtitleID = option?.id
        if let option {
            send([
                "action": "subtitle",
                "id": option.id,
                "index": option.sourceIndex ?? -1,
                "label": option.label,
                "language": option.language,
                "source": option.source
            ])
        } else {
            send(["action": "subtitle", "id": "off", "index": -1, "source": "off"])
        }
    }

    func selectServer(_ server: XSServerOption) {
        activeServerName = server.name
        if !server.quality.isEmpty { activeQuality = server.quality }
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
'''
new = '''    func selectSubtitle(_ option: XSSubtitleOption?) {
        if let option {
            send([
                "action": "subtitle",
                "id": option.id,
                "index": option.sourceIndex ?? -1,
                "label": option.label,
                "language": option.language,
                "source": option.source
            ])
        } else {
            selectedSubtitleID = nil
            captionText = ""
            send(["action": "subtitle", "id": "off", "index": -1, "source": "off"])
        }
    }

    func selectServer(_ server: XSServerOption) {
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
'''
if old not in text:
    raise SystemExit('Swift selection block not found')
text = text.replace(old, new, 1)

needle = '''        case "xs:caption":
            captionText = payload["text"] as? String ?? ""

        case "xs:subtitles":
'''
repl = '''        case "xs:caption":
            captionText = payload["text"] as? String ?? ""

        case "xs:subtitleSelected":
            selectedSubtitleID = payload["id"] as? String
            errorMessage = nil

        case "xs:subtitles":
'''
if needle not in text:
    raise SystemExit('Swift receive insertion not found')
text = text.replace(needle, repl, 1)

# Audio button is hidden unless the source really exposes multiple audio tracks.
audio = '''                        Button { openPanel(.audio) } label: {
                            Image(systemName: "waveform")
                        }
'''
if audio in text:
    text = text.replace(audio, '''                        if player.audioOptions.count > 1 {
                            Button { openPanel(.audio) } label: {
                                Image(systemName: "waveform")
                            }
                        }
''', 1)

# Remove the redundant bottom clusters. Their useful functions already live in CC/Settings.
pat = re.compile(r'''                HStack\(alignment: \.bottom\) \{\n                    HStack\(spacing: 20\) \{.*?\n                \.padding\(\.bottom, 12\)\n\n''', re.S)
text, n = pat.subn('', text, count=1)
if n != 1:
    raise SystemExit('Bottom control cluster not found')

# Only show subtitle styling/timing when actual tracks have been discovered.
old_extra = '''                Divider().padding(.vertical, 6)
                Button {
                    panel = .subtitleStyle
                } label: {
                    Label("Subtitle Appearance", systemImage: "textformat.size")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    panel = .subtitleDelay
                } label: {
                    Label("Subtitle Timing", systemImage: "timer")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
'''
if old_extra in text:
    text = text.replace(old_extra, '''                if !player.subtitleOptions.isEmpty {
                    Divider().padding(.vertical, 6)
                    Button {
                        panel = .subtitleStyle
                    } label: {
                        Label("Subtitle Appearance", systemImage: "textformat.size")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        panel = .subtitleDelay
                    } label: {
                        Label("Subtitle Timing", systemImage: "timer")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
''', 1)

# Source menu discovery must inspect icon markup too, not only visible text.
text = text.replace("const meta = (String(el.getAttribute('aria-label') || '') + ' ' + String(el.getAttribute('title') || '') + ' ' + cleanText(el)).toLowerCase();", "const meta = (String(el.getAttribute('aria-label') || '') + ' ' + String(el.getAttribute('title') || '') + ' ' + String(el.getAttribute('class') || '') + ' ' + String(el.innerHTML || '') + ' ' + cleanText(el)).toLowerCase();")

# Do not toggle an already-open hidden server menu closed when scanning.
old_scan_servers = '''      function openAndScanServers() {
        openServerMenu();
        setTimeout(scanServers,120);
        setTimeout(scanServers,350);
        setTimeout(scanServers,700);
      }
'''
new_scan_servers = '''      function openAndScanServers() {
        let alreadyOpen = false;
        try {
          alreadyOpen = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div')).some(el => !!parseServerRow(cleanText(el)));
        } catch (_) {}
        if (!alreadyOpen) openServerMenu();
        setTimeout(scanServers,120);
        setTimeout(scanServers,350);
        setTimeout(scanServers,700);
      }
'''
if old_scan_servers not in text:
    raise SystemExit('openAndScanServers block not found')
text = text.replace(old_scan_servers, new_scan_servers, 1)

# Same rule for subtitles: scan an already-open menu first, only toggle if no language rows exist.
old_scan_subs = '''      function openAndScanSubtitles() {
        openSubtitleMenu();
        setTimeout(scanSubtitles,120);
        setTimeout(scanSubtitles,350);
        setTimeout(scanSubtitles,700);
      }
'''
new_scan_subs = '''      function openAndScanSubtitles() {
        let alreadyOpen = false;
        try {
          alreadyOpen = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div')).some(el => looksLikeLanguage(cleanText(el)));
        } catch (_) {}
        if (!alreadyOpen) openSubtitleMenu();
        setTimeout(scanSubtitles,120);
        setTimeout(scanSubtitles,350);
        setTimeout(scanSubtitles,700);
      }
'''
if old_scan_subs not in text:
    raise SystemExit('openAndScanSubtitles block not found')
text = text.replace(old_scan_subs, new_scan_subs, 1)

# Real server selection: click an existing hidden row FIRST. Only open the menu if the row is absent.
old_server = '''          else if (action === 'server') {
            const name = String(payload.name || '');
            const provider = String(payload.provider || '');
            if (provider && provider !== 'auto' && /^(barbarian|archer|goblin)$/i.test(provider)) {
              window.postMessage({action:'setProvider',provider:provider},'*');
            } else if (name && name.toLowerCase() !== 'auto') {
              openServerMenu();
              setTimeout(() => selectByText(name),120);
            }
          }
'''
new_server = '''          else if (action === 'server') {
            const name = String(payload.name || '');
            if (name && name.toLowerCase() !== 'auto') {
              if (selectByText(name)) {
                setTimeout(scanServers,350);
                setTimeout(scanServers,900);
              } else {
                openServerMenu();
                setTimeout(() => {
                  selectByText(name);
                  setTimeout(scanServers,350);
                  setTimeout(scanServers,900);
                },180);
              }
            }
          }
'''
if old_server not in text:
    raise SystemExit('server command block not found')
text = text.replace(old_server, new_server, 1)

# Real subtitle selection: textTrack uses official index command; DOM tracks click the existing row first.
old_sub = '''          else if (action === 'subtitle') {
            const idx = Number(payload.index);
            subtitleIndex = Number.isFinite(idx) ? idx : -1;
            selectedDomSubtitle = String(payload.label || '');
            if (v && v.textTracks && subtitleIndex >= 0 && subtitleIndex < v.textTracks.length) {
              for (let i=0;i<v.textTracks.length;i++) {
                try { v.textTracks[i].mode = i === subtitleIndex ? 'hidden' : 'disabled'; } catch (_) {}
              }
            } else if (selectedDomSubtitle) {
              openSubtitleMenu();
              setTimeout(() => selectByText(selectedDomSubtitle),120);
            }
          }
'''
new_sub = '''          else if (action === 'subtitle') {
            const idx = Number(payload.index);
            subtitleIndex = Number.isFinite(idx) ? idx : -1;
            selectedDomSubtitle = String(payload.label || '');
            if (v && v.textTracks && subtitleIndex >= 0 && subtitleIndex < v.textTracks.length) {
              for (let i=0;i<v.textTracks.length;i++) {
                try { v.textTracks[i].mode = i === subtitleIndex ? 'hidden' : 'disabled'; } catch (_) {}
              }
              try { window.postMessage({action:'setSubtitle',index:subtitleIndex},'*'); } catch (_) {}
              bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
            } else if (selectedDomSubtitle) {
              if (selectByText(selectedDomSubtitle)) {
                bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
              } else {
                openSubtitleMenu();
                setTimeout(() => {
                  if (selectByText(selectedDomSubtitle)) {
                    bridge({event:'xs:subtitleSelected',id:String(payload.id || '')});
                  }
                },180);
              }
            }
          }
'''
if old_sub not in text:
    raise SystemExit('subtitle command block not found')
text = text.replace(old_sub, new_sub, 1)

path.write_text(text)
print('Applied XS Player V8 functional control fix')
