from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

new = '''                    // V26: compact subtitle tools dock. Language/Off remain in the real CC menu;
                    // this dock is only for appearance and sync, so there are no duplicate controls.
                    HStack(spacing: 7) {
                        Button {
                            openPanel(.subtitleStyle)
                        } label: {
                            Text("Aa")
                                .font(.system(size: 19, weight: .semibold, design: .rounded))
                                .frame(width: 46, height: 46)
                                .background(panel == .subtitleStyle ? Color.white.opacity(0.16) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Subtitle appearance")

                        Button {
                            openPanel(.subtitleDelay)
                        } label: {
                            Image(systemName: "timer")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 46, height: 46)
                                .background(panel == .subtitleDelay ? Color.white.opacity(0.16) : Color.clear, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Subtitle timing")
                    }
                    .padding(5)
                    .background(.black.opacity(0.52), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.42), radius: 12, y: 6)
                    .offset(y: -max(72, min(110, proxy.size.height * 0.12)))
'''

# V8/V24/V25 may slightly change the original spacing/labels. Locate the actual
# subtitle quick-control cluster structurally instead of depending on one exact string.
needle = 'openPanel(.subtitleDelay)'
pos = s.find(needle)
if pos < 0:
    raise SystemExit('V26 could not find subtitle timing launcher; refusing to alter working playback')

start = s.rfind('                    HStack(', 0, pos)
if start < 0:
    raise SystemExit('V26 could not locate start of subtitle toolbar')

# The old toolbar is a capsule ending at the first matching overlay after the timing/style buttons.
end_marker = '                    .overlay(Capsule().stroke(.white.opacity(0.16)))'
end = s.find(end_marker, pos)
if end < 0:
    # Compatibility with minor lineWidth/style variants.
    end_marker = '                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))'
    end = s.find(end_marker, pos)
if end < 0:
    raise SystemExit('V26 could not locate end of subtitle toolbar')
end += len(end_marker)
while end < len(s) and s[end] in '\r\n':
    end += 1

cluster = s[start:end]
if 'openPanel(.subtitleStyle)' not in cluster:
    raise SystemExit('V26 candidate toolbar does not contain appearance launcher')

s = s[:start] + new + s[end:]

# Remove motion from player panels. Subtitle text itself was already made stationary in V25;
# V26 also keeps the settings panels to a clean fade so the whole player feels consistent.
old_transition = '''                if panel != .none {
                    panelOverlay(proxy)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
'''
new_transition = '''                if panel != .none {
                    panelOverlay(proxy)
                        .transition(.opacity)
                }
'''
if old_transition in s:
    s = s.replace(old_transition, new_transition, 1)

# Keep the working V24/V25 engine untouched; mark the generated source for QA.
marker = 'private struct FrameXTVPlayerScreen: View {'
if marker in s and 'V26_FINAL_PLAYER_UI' not in s:
    s = s.replace(marker, '// V26_FINAL_PLAYER_UI: V24 subtitle/server engine preserved; presentation-only polish.\n' + marker, 1)

p.write_text(s)
print('Applied V26 final player UI polish: floating subtitle tools + fade-only panels')
