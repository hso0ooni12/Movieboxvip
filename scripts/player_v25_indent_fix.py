from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()
marker = 'private static let bridgeScript = #"""\n'
start = s.find(marker)
if start < 0:
    raise SystemExit('V25 bridgeScript start not found')
body_start = start + len(marker)
end_marker = '    """#'
end = s.find(end_marker, body_start)
if end < 0:
    raise SystemExit('V25 bridgeScript end not found')
body = s[body_start:end]
lines = body.splitlines(keepends=True)
fixed = []
for line in lines:
    if line.strip() and not line.startswith('    '):
        line = '    ' + line
    fixed.append(line)
s = s[:body_start] + ''.join(fixed) + s[end:]
p.write_text(s)
print('Applied V25 Swift raw-string indentation fix')
