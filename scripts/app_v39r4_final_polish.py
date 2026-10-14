from pathlib import Path

path = Path("FrameNative/FrameXTVPlayerV6.swift")
s = path.read_text(encoding="utf-8")
marker = "V39R4_FINAL_POLISH"
if marker in s:
    print("V39R4 already applied")
    raise SystemExit(0)
if "V39R3_PLAYER_SMOOTHNESS" not in s:
    raise SystemExit("V39R4: expected V39R3 source is missing")

old_style = "      let subtitleStyle = {size:1,color:'#ffffff',background:true,bottom:76};"
new_style = "      let subtitleStyle = {size:1,color:'#ffffff',background:true,backgroundStyle:'black',backgroundOpacity:0.68,bottom:76};"
if old_style not in s:
    raise SystemExit("V39R4: bridge subtitle style marker not found")
s = s.replace(old_style, new_style, 1)

old_panel = """        .onAppear {
            player.requestSubtitleMenu()
            player.requestMetadata()
        }
    }

    private var audioPanel"""
new_panel = """        .onAppear {
            player.requestSubtitleMenu()
        }
    }

    private var audioPanel"""
if old_panel not in s:
    raise SystemExit("V39R4: subtitle panel metadata request marker not found")
s = s.replace(old_panel, new_panel, 1)

s = s.replace(
    "// V39R3_PLAYER_SMOOTHNESS: fast source-owned server switching, bounded failover, de-duplicated panel scans.",
    "// V39R4_FINAL_POLISH: complete style defaults and single subtitle scan path.\n"
    "// V39R3_PLAYER_SMOOTHNESS: fast source-owned server switching, bounded failover, de-duplicated panel scans.",
    1,
)

old_loading = '            Text(player.errorMessage ?? "Loading video…")'
new_loading = '            Text(player.errorMessage ?? (player.serverSwitching ? "Switching server…" : "Loading video…"))'
if old_loading not in s:
    raise SystemExit("V39R4: loading overlay marker not found")
s = s.replace(old_loading, new_loading, 1)

path.write_text(s, encoding="utf-8")
print("V39R4 final polish applied")

