"""Presentation-only polish for the verified V39 baseline.

This runs after the V24/V35 player stack.  It deliberately leaves the source
subtitle adapter's selection path and the server selection command untouched.
"""
from pathlib import Path


player_path = Path("FrameNative/FrameXTVPlayerV6.swift")
source = player_path.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global source
    if old not in source:
        raise SystemExit(f"V39 native polish: missing {label}")
    source = source.replace(old, new, 1)


for required in (
    "func selectServer(_ server: XSServerOption)",
    'var payload: [String: Any] = ["action": "server", "name": server.name]',
    "sourceSubtitles.select(payload);",
    "function selectByText(text)",
):
    if required not in source:
        raise SystemExit(f"V39 native polish: protected playback marker missing: {required}")

# This is only a display normalization of resolution text already rendered by
# FrameXTV.  It does not inspect stream URLs, guess a resolution, or alter the
# server name/provider that the source owns.
old_parser = r'''      function parseServerRow(text) {
        const clean = String(text || '').replace(/\s+/g,' ').trim();
        if (!clean || clean.length > 120) return null;
        if (!/(Connected|Available)/i.test(clean)) return null;
        const q = (clean.match(/(4K|UHD|FHD|1080p|720p|HD)/i) || [])[1] || '';
        let name = clean.replace(/Connected|Available|4K|UHD|FHD|1080p|720p|HD/ig,' ').replace(/\s+/g,' ').trim();
        if (!name || name.length > 55) return null;
        return {name:name,quality:q.toUpperCase(),selected:/Connected/i.test(clean)};
      }
'''
new_parser = r'''      // V39_NATIVE_POLISH: normalize only quality labels the source already shows.
      function sourceServerQuality(raw) {
        const value = String(raw || '').toUpperCase().replace(/\s+/g,'');
        if (/(4K|UHD|2160P|2160)/.test(value)) return '4K';
        if (/(FULLHD|FHD|1080P|1080)/.test(value)) return 'Full HD';
        if (/(HD|720P|720)/.test(value)) return 'HD';
        return '';
      }

      function parseServerRow(text) {
        const clean = String(text || '').replace(/\s+/g,' ').trim();
        if (!clean || clean.length > 120) return null;
        if (!/(Connected|Available)/i.test(clean)) return null;
        const sourceQuality = (clean.match(/(4K|UHD|2160p|Full\s*HD|FHD|1080p|720p|HD)/i) || [])[1] || '';
        let name = clean.replace(/Connected|Available|4K|UHD|2160p|Full\s*HD|FHD|1080p|720p|HD/ig,' ').replace(/\s+/g,' ').trim();
        if (!name || name.length > 55) return null;
        return {name:name,quality:sourceServerQuality(sourceQuality),selected:/Connected/i.test(clean)};
      }
'''
replace_once(old_parser, new_parser, "source server-quality parser")

old_server_rows = '''                Text("SERVERS").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(player.servers) { server in
                    panelRow(title: server.name, detail: server.quality.isEmpty ? (server.selected ? "Connected" : "Available") : "\\(server.quality) · \\(server.selected ? "Connected" : "Available")") {
                        player.selectServer(server)
                        holdControls()
                    }
                }
'''
new_server_rows = '''                Text("SERVERS").font(.caption.bold()).foregroundStyle(.secondary)
                Text("Quality appears only when FrameXTV provides it")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(player.servers) { server in
                    nativeServerRow(server)
                }
'''
replace_once(old_server_rows, new_server_rows, "server panel rows")

server_row_helpers = '''
    // V39_NATIVE_POLISH: presentation only — native server selection remains
    // player.selectServer(server), which sends the original source command.
    private func nativeServerRow(_ server: XSServerOption) -> some View {
        Button {
            player.selectServer(server)
            holdControls()
        } label: {
            HStack(spacing: 11) {
                Image(systemName: server.selected ? "checkmark.circle.fill" : "server.rack")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(server.selected ? .green : .white.opacity(0.58))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(server.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(server.selected ? "Connected" : "Available")
                        .font(.caption)
                        .foregroundStyle(server.selected ? .green : .secondary)
                }

                Spacer(minLength: 8)

                if !server.quality.isEmpty {
                    Text(server.quality)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(serverQualityTint(server.quality).opacity(0.18), in: Capsule())
                        .overlay(Capsule().stroke(serverQualityTint(server.quality).opacity(0.35), lineWidth: 1))
                        .foregroundStyle(serverQualityTint(server.quality))
                }

                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.32))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(server.selected ? Color.white.opacity(0.075) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(server.selected ? Color.green.opacity(0.28) : Color.white.opacity(0.07), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(XSPlayerTapButtonStyle())
        .foregroundStyle(.white)
        .accessibilityLabel(server.quality.isEmpty ? "\\(server.name), \\(server.selected ? "Connected" : "Available")" : "\\(server.name), \\(server.quality), \\(server.selected ? "Connected" : "Available")")
    }

    private func serverQualityTint(_ quality: String) -> Color {
        switch quality {
        case "4K": return .purple
        case "Full HD": return .blue
        case "HD": return .cyan
        default: return .secondary
        }
    }

'''
anchor = "    private var subtitlesPanel: some View {"
if anchor not in source:
    raise SystemExit("V39 native polish: missing subtitle-panel anchor")
source = source.replace(anchor, server_row_helpers + anchor, 1)

player_path.write_text(source, encoding="utf-8")
print("Applied V39 native polish: source-only quality badges and presentation safeguards")
