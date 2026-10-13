from pathlib import Path

path = Path("FrameNative/FrameXTVPlayerV6.swift")
s = path.read_text(encoding="utf-8")

old = '''        .onAppear {
            player.requestServerMenu()
            player.requestQualityMenu()
            player.requestMetadata()
        }'''
new = '''        .onAppear {
            // Quality and servers are intentionally isolated from subtitle metadata.
            // Opening this panel must never open/scan the CC language catalog.
            player.requestQualityMenu()
            player.requestServerMenu()
        }'''
if old not in s:
    raise SystemExit("V39R isolation: patched quality panel onAppear not found")
s = s.replace(old, new, 1)

path.write_text(s, encoding="utf-8")
print("Applied V39R Quality & Server panel isolation from subtitle metadata")
