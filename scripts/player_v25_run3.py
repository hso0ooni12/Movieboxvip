from pathlib import Path

path = Path('scripts/player_v25_subtitle_appearance.py')
code = path.read_text()

old_replace = '''def replace(old, new):
    global s
    if old not in s:
        raise SystemExit('V25 expected source marker missing: ' + old[:120])
    s = s.replace(old, new, 1)
'''
new_replace = '''def _flex_match(needle, start=0):
    import re
    lines = needle.splitlines()
    parts = []
    for line in lines:
        stripped = line.lstrip(' \\t')
        parts.append(r'[ \\t]*' + re.escape(stripped))
    pattern = re.compile(r'\\n'.join(parts))
    return pattern.search(s, start)

def replace(old, new):
    global s
    m = _flex_match(old)
    if not m:
        raise SystemExit('V25 expected source marker missing: ' + old[:120])
    s = s[:m.start()] + new + s[m.end():]
'''

old_section = '''def section(start, end, new):
    global s
    a = s.find(start)
    if a < 0:
        raise SystemExit('V25 start marker missing: ' + start[:120])
    b = s.find(end, a)
    if b < 0:
        raise SystemExit('V25 end marker missing: ' + end[:120])
    s = s[:a] + new + s[b:]
'''
new_section = '''def section(start, end, new):
    global s
    a_match = _flex_match(start)
    if not a_match:
        raise SystemExit('V25 start marker missing: ' + start[:120])
    b_match = _flex_match(end, a_match.end())
    if not b_match:
        raise SystemExit('V25 end marker missing: ' + end[:120])
    s = s[:a_match.start()] + new + s[b_match.start():]
'''

if old_replace not in code or old_section not in code:
    raise SystemExit('V25 R3 could not replace compatibility helpers')
code = code.replace(old_replace, new_replace, 1).replace(old_section, new_section, 1)
exec(compile(code, str(path), 'exec'), {'__name__': '__main__'})
