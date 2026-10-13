from pathlib import Path

path = Path('scripts/player_v25_subtitle_appearance.py')
code = path.read_text()
old_replace = '''def replace(old, new):
    global s
    if old not in s:
        raise SystemExit('V25 expected source marker missing: ' + old[:120])
    s = s.replace(old, new, 1)
'''
new_replace = '''def replace(old, new):
    global s
    candidate = old
    if candidate not in s and old.lstrip() in s:
        candidate = old.lstrip()
    if candidate not in s:
        raise SystemExit('V25 expected source marker missing: ' + old[:120])
    s = s.replace(candidate, new, 1)
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
    start_candidate = start if start in s else start.lstrip()
    a = s.find(start_candidate)
    if a < 0:
        raise SystemExit('V25 start marker missing: ' + start[:120])
    end_candidate = end if s.find(end, a) >= 0 else end.lstrip()
    b = s.find(end_candidate, a)
    if b < 0:
        raise SystemExit('V25 end marker missing: ' + end[:120])
    s = s[:a] + new + s[b:]
'''
if old_replace not in code or old_section not in code:
    raise SystemExit('V25 runner could not patch compatibility helpers')
code = code.replace(old_replace, new_replace, 1).replace(old_section, new_section, 1)
exec(compile(code, str(path), 'exec'), {'__name__': '__main__'})
