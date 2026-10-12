from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V14 fixes the architectural issue behind unreliable subtitle/server control:
# FrameXTV can host the actual provider player in nested iframes. Commands sent only
# to the top embed frame never reach those nested documents. Every injected frame now
# gets a stable frame id, commands are routed recursively, and subtitle options are
# scoped to the frame that discovered them so the wrong language/index cannot be used
# in a sibling frame.

# 1) Give every injected frame a stable id for this page lifetime.
marker = "      window.__xsStableV7 = true;\n"
insert = "      window.__xsStableV7 = true;\n      const xsFrameId = window.__xsFrameId || (window.__xsFrameId = 'f-' + Math.random().toString(36).slice(2) + '-' + Date.now().toString(36));\n"
if marker in text and 'const xsFrameId = window.__xsFrameId' not in text:
    text = text.replace(marker, insert, 1)

# 2) Scope network subtitle ids to the frame where the metadata was observed.
text = text.replace(
    "          id:'network-'+networkSubtitleItems.length,",
    "          id:xsFrameId+'::network-'+networkSubtitleItems.length,",
    1
)

# 3) Scope every subtitle row (DOM/textTrack/track tag/network) before it is sent to Swift.
old_push = "          items.push({id:String(id),index:index,label:l,language:lang,source:source});"
new_push = "          const rawID = String(id); const scopedID = rawID.startsWith(xsFrameId+'::') ? rawID : (xsFrameId+'::'+rawID); items.push({id:scopedID,index:index,label:l,language:lang,source:source});"
if old_push not in text:
    raise SystemExit('V14 subtitle item push marker not found')
text = text.replace(old_push, new_push, 1)

# 4) A subtitle choice must only execute in the frame that owns that option.
needle = "            const wantedID = String(payload.id || '');\n"
owned = "            const wantedID = String(payload.id || '');\n            const wantedFrame = wantedID.includes('::') ? wantedID.split('::')[0] : '';\n            if (wantedID !== 'off' && wantedFrame && wantedFrame !== xsFrameId) return;\n"
if needle not in text:
    raise SystemExit('V14 wantedID marker not found')
text = text.replace(needle, owned, 1)

# 5) Recursively route native commands through all nested provider iframes.
#    This is the key fix: server/subtitle controls can now reach whichever frame owns
#    the real FrameXTV/provider controls and video element.
old_listener = "          if (event.data && event.data.__xsCommand) command(event.data.__xsCommand);"
new_listener = r'''          if (event.data && event.data.__xsCommand) {
            const packet = event.data;
            const token = String(packet.__xsToken || ('cmd-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2)));
            if (!window.__xsSeenCommandTokens) window.__xsSeenCommandTokens = new Set();
            if (!window.__xsSeenCommandTokens.has(token)) {
              window.__xsSeenCommandTokens.add(token);
              if (window.__xsSeenCommandTokens.size > 256) window.__xsSeenCommandTokens.clear();
              command(packet.__xsCommand);
              try {
                Array.from(document.querySelectorAll('iframe')).forEach(frame => {
                  try {
                    if (frame.contentWindow) frame.contentWindow.postMessage({__xsCommand:packet.__xsCommand,__xsToken:token},'*');
                  } catch (_) {}
                });
              } catch (_) {}
            }
          }'''
if old_listener not in text:
    raise SystemExit('V14 command listener marker not found')
text = text.replace(old_listener, new_listener, 1)

# 6) Do not re-select the already connected server from Swift. This avoids the
#    'Default/current server hangs the same video' behaviour caused by needless reloads.
start = text.find('    func selectServer(_ server: XSServerOption) {')
end = text.find('\n    func selectQuality(', start)
if start == -1 or end == -1:
    raise SystemExit('V14 Swift selectServer bounds not found')
block = text[start:end]
if 'caseInsensitiveCompare(server.name)' not in block:
    block = block.replace(
        '    func selectServer(_ server: XSServerOption) {\n',
        '    func selectServer(_ server: XSServerOption) {\n        if activeServerName.caseInsensitiveCompare(server.name) == .orderedSame { return }\n',
        1
    )
    text = text[:start] + block + text[end:]

# 7) Surface actual bridge confirmations/failures and refresh subtitles only after a
#    confirmed server switch, rather than pretending the selection succeeded.
receive_anchor = '''        case "xs:audio":
            guard let rows = payload["items"] as? [[String: Any]] else { return }
            let parsed = rows.compactMap { row -> XSAudioOption? in
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return .init(id: name.lowercased(), name: name, selected: row["selected"] as? Bool ?? false)
            }
            if !parsed.isEmpty { audioOptions = parsed }

        default:
'''
receive_repl = '''        case "xs:audio":
            guard let rows = payload["items"] as? [[String: Any]] else { return }
            let parsed = rows.compactMap { row -> XSAudioOption? in
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return .init(id: name.lowercased(), name: name, selected: row["selected"] as? Bool ?? false)
            }
            if !parsed.isEmpty { audioOptions = parsed }

        case "xs:serverSwitchConfirmed":
            if let name = payload["name"] as? String, !name.isEmpty { activeServerName = name }
            errorMessage = nil
            subtitleOptions = []
            selectedSubtitleID = nil
            requestSubtitleMenu()

        case "xs:serverSwitchFailed":
            errorMessage = "Could not switch to that server."

        case "xs:subtitleSelectionFailed":
            errorMessage = "That subtitle track could not be activated on this server."

        default:
'''
if receive_anchor in text:
    text = text.replace(receive_anchor, receive_repl, 1)
else:
    # Older generated shapes may already have extra cases. Insert just before default.
    fallback = '        default:\n            break\n'
    if fallback not in text:
        raise SystemExit('V14 Swift receive default marker not found')
    cases = '''        case "xs:serverSwitchConfirmed":
            if let name = payload["name"] as? String, !name.isEmpty { activeServerName = name }
            errorMessage = nil
            subtitleOptions = []
            selectedSubtitleID = nil
            requestSubtitleMenu()

        case "xs:serverSwitchFailed":
            errorMessage = "Could not switch to that server."

        case "xs:subtitleSelectionFailed":
            errorMessage = "That subtitle track could not be activated on this server."

'''
    text = text.replace(fallback, cases + fallback, 1)

path.write_text(text)
print('Applied XS Player V14 recursive provider-frame bridge')
