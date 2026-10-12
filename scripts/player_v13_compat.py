from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# V8 intentionally removed optimistic state updates. V13 replaces this function with
# a stricter version that also clears subtitle state, so normalize the function shape
# to the marker V13 expects without changing the final generated app behavior.
current = '''    func selectServer(_ server: XSServerOption) {
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
'''
marker = '''    func selectServer(_ server: XSServerOption) {
        activeServerName = server.name
        if !server.quality.isEmpty { activeQuality = server.quality }
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
'''
if current in text:
    text = text.replace(current, marker, 1)
elif marker not in text:
    raise SystemExit('V13 compat selectServer shape not found')

path.write_text(text)
print('Applied V13 compatibility normalization')
