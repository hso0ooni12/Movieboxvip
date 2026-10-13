from pathlib import Path

p = Path('FrameNative/Views/Components.swift')
s = p.read_text()

replacements = [
    ('AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.28)))',
     'AsyncImage(url: url, transaction: Transaction(animation: nil))'),
    ('.shadow(color: .black.opacity(0.32), radius: 13, y: 7)',
     '.shadow(color: .black.opacity(0.24), radius: 6, y: 3)'),
    ('withAnimation(.easeInOut(duration: 0.5)) {',
     'withAnimation(.easeInOut(duration: 0.28)) {'),
    ('.animation(.easeInOut(duration: 0.25), value: currentIndex)',
     '.animation(.easeInOut(duration: 0.16), value: currentIndex)'),
    ('.blendMode(.screen)', '.opacity(0.88)'),
    ('withAnimation(.easeOut(duration: 0.72)) { appeared = true }',
     'withAnimation(.easeOut(duration: 0.36)) { appeared = true }'),
]

for old, new in replacements:
    if old in s:
        s = s.replace(old, new)

if 'V29_SMOOTH_BROWSING' not in s:
    s = '// V29_SMOOTH_BROWSING: no image fade decode churn, lighter shadows/compositing, shorter UI animations.\n' + s

p.write_text(s)
print('Applied V29 smooth browsing optimizations')
