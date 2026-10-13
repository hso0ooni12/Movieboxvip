from pathlib import Path

# V40 is deliberately a *targeted* patch on top of the proven V39 baseline.
# Do not change navigation, playback transport, sports VLC, subtitle catalog
# ownership, or general app architecture here. Only:
#   1) keep subtitle rows out of the server list + present server quality cleanly
#   2) make subtitle background/opacity deterministic by rendering selected cues
#      in the native SwiftUI overlay while the source track remains authoritative.

p = Path("FrameNative/FrameXTVPlayerV6.swift")
s = p.read_text(encoding="utf-8")


def replace_once(old: str, new: str, label: str) -> None:
    global s
    if old not in s:
        raise SystemExit(f"V40 marker missing ({label})")
    s = s.replace(old, new, 1)


# ---------------------------------------------------------------------------
# Server list isolation + quality presentation
# ---------------------------------------------------------------------------
replace_once(
'''private struct XSServerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let quality: String
    let provider: String?
    let selected: Bool
}''',
'''private struct XSServerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let quality: String
    let provider: String?
    let selected: Bool

    var displayQuality: String {
        let q = quality.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if q.contains("2160") || q.contains("4K") || q.contains("UHD") { return "4K" }
        if q.contains("1080") || q.contains("FHD") || q.contains("FULL HD") { return "Full HD" }
        if q.contains("720") || q == "HD" { return "HD" }
        if q.contains("480") || q.contains("360") || q == "SD" { return "SD" }
        return q.isEmpty ? "Auto" : quality
    }
}''',
"server display quality"
)

replace_once(
'''                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let quality = row["quality"] as? String ?? ""
                let provider = row["provider"] as? String
                let selected = row["selected"] as? Bool ?? false
                return .init(id: (provider ?? name) + quality, name: name, quality: quality, provider: provider, selected: selected)''',
'''                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }

                // A server payload must never be allowed to reuse subtitle-menu
                // labels. This is a final UI boundary even if the provider DOM
                // changes in the future.
                let lowered = name.lowercased()
                let subtitleContamination = lowered.hasPrefix("subtitle") ||
                    lowered.hasPrefix("captions") ||
                    lowered.hasPrefix("closed captions") ||
                    lowered.contains("subtitles •") ||
                    lowered.contains("captions •")
                guard !subtitleContamination else { return nil }

                let rawQuality = (row["quality"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let upper = rawQuality.uppercased()
                let quality: String
                if upper.contains("2160") || upper.contains("4K") || upper.contains("UHD") { quality = "4K" }
                else if upper.contains("1080") || upper.contains("FHD") || upper.contains("FULL HD") { quality = "Full HD" }
                else if upper.contains("720") || upper == "HD" { quality = "HD" }
                else if upper.contains("480") || upper.contains("360") || upper == "SD" { quality = "SD" }
                else { quality = rawQuality }

                let provider = row["provider"] as? String
                let selected = row["selected"] as? Bool ?? false
                return .init(id: (provider ?? name) + quality, name: name, quality: quality, provider: provider, selected: selected)''',
"server contamination guard"
)

# Keep V39's proven server discovery/selection path. Only change how rows are
# presented to the user. Unknown/automatic quality is labeled Auto rather than
# guessed as HD/FHD/4K.
replace_once(
'''                    panelRow(title: server.name, detail: server.quality.isEmpty ? (server.selected ? "Connected" : "Available") : "\\(server.quality) · \\(server.selected ? "Connected" : "Available")") {''',
'''                    panelRow(title: server.name, detail: "\\(server.displayQuality) · \\(server.selected ? "Connected" : "Available")") {''',
"server row detail"
)

# ---------------------------------------------------------------------------
# Native subtitle presentation ownership
# ---------------------------------------------------------------------------
# The source menu still owns which subtitle file/track is selected and loaded.
# Once loaded, SwiftUI owns only visual presentation. This removes provider CSS
# from the background/opacity equation and makes Black/Gray/None/Opacity exact.
replace_once(
"        const customTiming = delay !== 0 && active && trackFor(active);\n        const bg = subtitleBackgroundCSS();",
"        const nativeCaption = !!(active && trackFor(active));\n        const bg = subtitleBackgroundCSS();",
"native caption ownership flag"
)

replace_once(
'''          el.style.setProperty('background-color', bg, 'important');
          el.style.setProperty('border-radius', bg === 'transparent' ? '0' : '6px', 'important');
          el.style.setProperty('padding', bg === 'transparent' ? '0' : '4px 10px', 'important');
          if (customTiming) el.style.setProperty('opacity', '0', 'important');
          else el.style.removeProperty('opacity');''',
'''          // The native SwiftUI overlay renders the selected cue. Hide the
          // provider's visual cue while keeping its real TextTrack active.
          // Clear nested provider backgrounds too so no old black strip can
          // flash during cue changes.
          el.style.setProperty('background', 'transparent', 'important');
          el.style.setProperty('background-color', 'transparent', 'important');
          el.style.setProperty('border-radius', '0', 'important');
          el.style.setProperty('padding', '0', 'important');
          for (const child of el.querySelectorAll('*')) {
            child.style.setProperty('background', 'transparent', 'important');
            child.style.setProperty('background-color', 'transparent', 'important');
            child.style.setProperty('box-shadow', 'none', 'important');
          }
          if (nativeCaption) el.style.setProperty('opacity', '0', 'important');
          else el.style.removeProperty('opacity');''',
"hide provider caption renderer"
)

replace_once(
'''  function reportCaption() {
    const selectedTrack = delay && active ? trackFor(active) : null;
    if (timingTrack && timingTrack !== selectedTrack) {
      if (timingTrack.mode === 'hidden' && timingTrack.cues && timingTrack.cues.length) timingTrack.mode = 'showing';
      timingTrack = null;
    }
    if (selectedTrack && selectedTrack.mode === 'showing') {
      timingTrack = selectedTrack;
      selectedTrack.mode = 'hidden';
    }
    applyStyle();
    if (!delay || !active) { caption(''); return; }
    const track = selectedTrack, v = findVideo();
    if (!track || !v) { caption(''); return; }
    const at = Number(v.currentTime || 0) + delay;
    const lines = Array.from(track.cues).filter(c => c.startTime <= at && at < c.endTime).map(c => c.text || '');
    caption(lines.join('\\n'));
  }''',
'''  function reportCaption() {
    // Selection/loading stays source-owned. Rendering is native-owned for every
    // selected subtitle, even when delay == 0, so appearance controls are
    // deterministic and independent of provider CSS.
    const selectedTrack = active ? trackFor(active) : null;
    if (timingTrack && timingTrack !== selectedTrack) {
      if (timingTrack.mode === 'hidden' && timingTrack.cues && timingTrack.cues.length) timingTrack.mode = 'showing';
      timingTrack = null;
    }
    if (selectedTrack && selectedTrack.mode === 'showing') {
      timingTrack = selectedTrack;
      selectedTrack.mode = 'hidden';
    } else if (selectedTrack) {
      timingTrack = selectedTrack;
    }
    applyStyle();
    if (!active) { caption(''); return; }
    const track = selectedTrack, v = findVideo();
    if (!track || !v) { caption(''); return; }
    const at = Number(v.currentTime || 0) + delay;
    const cleanCueText = cue => String(cue && cue.text || '')
      .replace(/<br\\s*\\/?>(?=.)/gi, '\\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/gi, ' ')
      .trim();
    const lines = Array.from(track.cues)
      .filter(c => c.startTime <= at && at < c.endTime)
      .map(cleanCueText)
      .filter(Boolean);
    caption(lines.join('\\n'));
  }''',
"always-native subtitle rendering"
)

# Allow the opacity control to cover the full range and make Gray's actual
# render match its preview chip.
replace_once(
'''                                Slider(value: $subtitleBackgroundOpacity, in: 0.20...1.0, step: 0.05)''',
'''                                Slider(value: $subtitleBackgroundOpacity, in: 0.0...1.0, step: 0.05)''',
"opacity full range"
)
replace_once(
'''        case "gray": return Color(white: 0.19)''',
'''        case "gray": return Color(white: 0.28)''',
"gray render parity"
)

# Add a tiny marker near the app storage block for regression tests and future
# maintenance. It has no runtime cost.
replace_once(
'''    @AppStorage("XSTV.subtitleBackgroundOpacity") private var subtitleBackgroundOpacity = 0.68''',
'''    // V40_V39_TARGETED_RECOVERY: keep V39 behavior; native subtitle visuals only.
    @AppStorage("XSTV.subtitleBackgroundOpacity") private var subtitleBackgroundOpacity = 0.68''',
"V40 marker"
)

p.write_text(s, encoding="utf-8")
print("Applied V40 targeted recovery on V39: isolated server rows + native subtitle background/opacity")
