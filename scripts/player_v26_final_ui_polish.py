from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

# ---------------------------------------------------------------------------
# 1) Hide FrameXTV's own subtitle utility strip (the tortoise/Aa/translate/x
#    bar visible in V25). We keep the real CC language popup intact because
#    V24 uses it for the working source-owned subtitle selection.
# ---------------------------------------------------------------------------
hide_anchor = '      function hidePanels() {'
hide_replacement = r'''      function hideSubtitleUtilityDock() {
        try {
          const all = Array.from(doc.querySelectorAll('button'));
          const markCompactGroup = button => {
            let node = button && button.parentElement;
            for (let depth = 0; node && node !== doc.body && depth < 4; depth++, node = node.parentElement) {
              const btns = Array.from(node.querySelectorAll('button'));
              if (btns.length >= 2 && btns.length <= 7 && !node.querySelector('video,iframe')) {
                node.setAttribute('data-xs-source-panel', '1');
                return;
              }
            }
          };
          for (const button of all) {
            const visible = text(button).replace(/\s+/g, '');
            const meta = [button.getAttribute('title') || '', button.getAttribute('aria-label') || '',
              button.getAttribute('data-testid') || '', button.className || '', text(button)].join(' ').toLowerCase();
            // FrameXTV's subtitle tools include an Aa control. The extra meta match
            // covers timing/style/translate variants without hiding the actual CC menu.
            if (/^aa$/i.test(visible) || /subtitle.{0,12}(appearance|style|timing|delay|position|color|background)|caption.{0,12}(appearance|style|timing|delay)|subtitle sync|translate|translation/.test(meta)) {
              markCompactGroup(button);
            }
          }
        } catch (_) {}
      }
      function hidePanels() {
        hideSubtitleUtilityDock();'''
if hide_anchor not in s:
    raise SystemExit('V26 could not find source hidePanels hook; refusing to alter working V24 bridge')
s = s.replace(hide_anchor, hide_replacement, 1)

# ---------------------------------------------------------------------------
# 2) Add a clean native subtitle tools dock in the requested left-side area.
#    V8 intentionally removed the old Swift bottom clusters, so V26 inserts a
#    new zero-height floating row just above the timeline without shifting it.
# ---------------------------------------------------------------------------
timeline_anchor = '''                HStack(spacing: 12) {
                    Text(formatTime(isScrubbing ? scrubValue : player.currentTime))'''
quick_dock = '''                // V26 subtitle tools: presentation only. CC language selection remains source-owned by V24.
                HStack(spacing: 0) {
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
                    .background(.black.opacity(0.54), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.44), radius: 12, y: 6)

                    Spacer()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .frame(height: 0)
                .offset(y: -max(104, min(170, proxy.size.height * 0.20)))

'''
if timeline_anchor not in s:
    raise SystemExit('V26 could not find timeline anchor for floating subtitle tools')
s = s.replace(timeline_anchor, quick_dock + timeline_anchor, 1)

# ---------------------------------------------------------------------------
# 3) Keep all player panels on a clean fade. V25 already removed the vertical
#    movement from subtitle cues; this removes the remaining panel slide.
# ---------------------------------------------------------------------------
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
print('Applied V26 final player UI polish: native floating subtitle tools + hidden source utility strip + fade-only panels')
