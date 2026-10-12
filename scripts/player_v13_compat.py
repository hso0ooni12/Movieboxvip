from pathlib import Path

path = Path('FrameNative/FrameXTVPlayerV6.swift')
text = path.read_text()

# Normalize whatever earlier patches did to selectServer into the marker V13 replaces.
start = text.find('    func selectServer(_ server: XSServerOption) {')
end = text.find('\n    func selectQuality(', start)
if start == -1 or end == -1:
    raise SystemExit('V13 compat selectServer bounds not found')

marker = '''    func selectServer(_ server: XSServerOption) {
        activeServerName = server.name
        if !server.quality.isEmpty { activeQuality = server.quality }
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
'''
text = text[:start] + marker + text[end:]
path.write_text(text)
print('Applied V13 compatibility normalization')
