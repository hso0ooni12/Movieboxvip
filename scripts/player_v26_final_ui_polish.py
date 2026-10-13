from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

old = '''                    HStack(spacing: 20) {
                        Button { openPanel(.subtitleDelay) } label: { Image(systemName: "tortoise") }
                        Button { openPanel(.subtitleStyle) } label: { Text("Aa").font(.system(size: 20, weight: .medium)) }
                        Button { openPanel(.subtitles) } label: { Image(systemName: "character.bubble") }
                        Button { player.selectSubtitle(nil); revealControls() } label: { Image(systemName: "xmark") }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(.black.opacity(0.46), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16)))
'''

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

if old not in s:
    raise SystemExit('V26 subtitle toolbar marker not found; refusing to alter V24/V25 behavior')
s = s.replace(old, new, 1)

# Remove motion from the tool panels themselves as well. They should fade cleanly
# instead of sliding in from the edge/bottom while the user is watching video.
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
