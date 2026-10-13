from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

def replace(old, new, label):
    global s
    if old not in s:
        raise SystemExit(f'V27 marker missing: {label}')
    s = s.replace(old, new, 1)

def section(start, end, new, label):
    global s
    a = s.find(start)
    if a < 0:
        raise SystemExit(f'V27 start marker missing: {label}')
    b = s.find(end, a)
    if b < 0:
        raise SystemExit(f'V27 end marker missing: {label}')
    s = s[:a] + new + s[b:]

# ---------------------------------------------------------------------------
# 1) Put subtitle tools close to the timeline instead of floating mid-screen.
# ---------------------------------------------------------------------------
replace(
'''                .frame(height: 0)
                .offset(y: -max(104, min(170, proxy.size.height * 0.20)))''',
'''                .frame(height: 0)
                .offset(y: -64)''',
'V26 subtitle tools position'
)

# ---------------------------------------------------------------------------
# 2) Use compact, self-contained subtitle panels. No horizontal scrolling.
# ---------------------------------------------------------------------------
replace(
'''        case .subtitleStyle:
            bottomPanel { subtitleStylePanel }
        case .subtitleDelay:
            bottomPanel { subtitleDelayPanel }''',
'''        case .subtitleStyle:
            compactSubtitlePanel(proxy, maxWidth: 820, title: "Subtitle Appearance", systemImage: "captions.bubble.fill") {
                subtitleStylePanel
            }
        case .subtitleDelay:
            compactSubtitlePanel(proxy, maxWidth: 680, title: "Subtitle Timing", systemImage: "timer") {
                subtitleDelayPanel
            }''',
'compact panel routing'
)

quality_marker = '''    private var qualityPanel: some View {'''
compact_panel = r'''    private func compactSubtitlePanel<Content: View>(
        _ proxy: GeometryProxy,
        maxWidth: CGFloat,
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { closePanel() }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Button { closePanel() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close subtitle tools")
                }

                Divider().overlay(.white.opacity(0.08))
                content()
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(width: min(maxWidth, max(320, proxy.size.width - 40)))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 22, y: 10)
            .padding(.horizontal, 20)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom + 76, 88))
        }
        .ignoresSafeArea()
    }

'''
if quality_marker not in s:
    raise SystemExit('V27 quality marker missing for compact panel insertion')
s = s.replace(quality_marker, compact_panel + quality_marker, 1)

section(
'    private var subtitleStylePanel: some View {',
'\n    private var subtitleDelayPanel: some View {',
r'''    private var subtitleStylePanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Size · \(Int(subtitleScale * 100))%")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button { subtitleScale = max(0.7, subtitleScale - 0.1) } label: {
                            Image(systemName: "minus.circle.fill").font(.title3)
                        }
                        Slider(value: $subtitleScale, in: 0.7...1.8, step: 0.05)
                            .tint(.white)
                        Button { subtitleScale = min(1.8, subtitleScale + 0.1) } label: {
                            Image(systemName: "plus.circle.fill").font(.title3)
                        }
                    }
                }

                Divider().frame(height: 54)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Position")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button { subtitleBottom = max(32, subtitleBottom - 12) } label: {
                            Image(systemName: "arrow.down.circle.fill").font(.title3)
                        }
                        Slider(value: $subtitleBottom, in: 32...220, step: 4)
                            .tint(.white)
                        Button { subtitleBottom = min(220, subtitleBottom + 12) } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title3)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Text Color").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 7) {
                        colorButton("#FFFFFF", .white)
                        colorButton("#FFD60A", .yellow)
                        colorButton("#00D4FF", .cyan)
                        colorButton("#34C759", .green)
                        colorButton("#FF9F0A", .orange)
                        colorButton("#FF453A", .red)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Background").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        backgroundButton("None", style: "none", preview: .clear)
                        backgroundButton("Black", style: "black", preview: .black)
                        backgroundButton("Gray", style: "gray", preview: Color(white: 0.28))
                        backgroundButton("White", style: "white", preview: .white)
                    }
                }
            }

            if subtitleBackgroundStyle != "none" {
                HStack(spacing: 10) {
                    Text("Background Opacity")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Slider(value: $subtitleBackgroundOpacity, in: 0.0...1.0, step: 0.05)
                        .tint(.white)
                    Text("\(Int(subtitleBackgroundOpacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 42, alignment: .trailing)
                }
            }

            HStack {
                Spacer()
                Button {
                    subtitleScale = 1.0
                    subtitleColor = "#FFFFFF"
                    subtitleBackground = true
                    subtitleBackgroundStyle = "black"
                    subtitleBackgroundOpacity = 0.68
                    subtitleBottom = 76
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .foregroundStyle(.white)
    }
''',
'compact subtitle appearance panel'
)

section(
'    private var subtitleDelayPanel: some View {',
'\n    private func panelRow(',
r'''    private var subtitleDelayPanel: some View {
        VStack(spacing: 12) {
            HStack {
                Text("If subtitles are late, increase the value. If early, decrease it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%+.2f s", subtitleDelay))
                    .font(.title3.monospacedDigit().bold())
            }

            Slider(value: $subtitleDelay, in: -7.5...9.0, step: 0.25)
                .tint(.white)

            HStack {
                Text("−7.5 s").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button {
                    subtitleDelay = 0
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                Spacer()
                Text("+9.0 s").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }
''',
'timing panel with close inherited from compact container'
)

# Compact the chips/buttons so the full editor fits on a landscape iPhone without scrolling.
s = s.replace('.frame(width: 34, height: 34)', '.frame(width: 30, height: 30)')
s = s.replace('.padding(.horizontal, 10)\n            .frame(height: 34)', '.padding(.horizontal, 8)\n            .frame(height: 32)')

# ---------------------------------------------------------------------------
# 3) Make source-player background opacity affect the actual painted caption
#    surface, including providers that paint the box on a nested span/div.
# ---------------------------------------------------------------------------
section(
'      function applyStyle() {',
'\n      function installCaptionObserver() {',
r'''      function applyStyle() {
        hidePanels();
        const customTiming = delay !== 0 && active && trackFor(active);
        const bg = subtitleBackgroundCSS();
        for (const el of sourceCaptionNodes()) {
          // Keep caption position stable; fade only.
          el.style.setProperty('transition', 'opacity 120ms linear', 'important');
          el.style.setProperty('transition-property', 'opacity', 'important');
          el.style.setProperty('animation', 'none', 'important');
          el.style.setProperty('will-change', 'opacity', 'important');
          el.style.setProperty('font-size', Math.round(22 * style.size) + 'px', 'important');
          el.style.setProperty('color', style.color, 'important');
          el.style.setProperty('bottom', style.bottom + 'px', 'important');

          // Providers differ: some paint the subtitle box on the outer cue div,
          // others on a nested span/div. Clear every candidate first, then paint
          // only the deepest text-bearing nodes so opacity is visible immediately.
          const descendants = Array.from(el.querySelectorAll('span,div'));
          const deepest = descendants.filter(node => {
            const own = normal(text(node));
            if (!own) return false;
            return !Array.from(node.children || []).some(child => normal(text(child)));
          });
          const targets = deepest.length ? deepest : [el];
          for (const node of [el].concat(descendants)) {
            node.style.setProperty('background', 'transparent', 'important');
            node.style.setProperty('background-color', 'transparent', 'important');
          }
          for (const node of targets) {
            node.style.setProperty('background', bg, 'important');
            node.style.setProperty('background-color', bg, 'important');
            node.style.setProperty('border-radius', bg === 'transparent' ? '0' : '6px', 'important');
            node.style.setProperty('padding', bg === 'transparent' ? '0' : '4px 10px', 'important');
            node.style.setProperty('-webkit-box-decoration-break', 'clone', 'important');
            node.style.setProperty('box-decoration-break', 'clone', 'important');
            node.style.setProperty('font-size', Math.round(22 * style.size) + 'px', 'important');
            node.style.setProperty('color', style.color, 'important');
          }

          if (customTiming) el.style.setProperty('opacity', '0', 'important');
          else el.style.removeProperty('opacity');
        }
      }
''',
'source caption background opacity painting'
)

# Marker for QA. Prepend it so it cannot depend on a particular V26 comment layout.
if 'V27_COMPACT_SUBTITLE_UI' not in s:
    s = '// V27_COMPACT_SUBTITLE_UI: compact no-scroll editors, timeline-adjacent tools, live background opacity.\n' + s

p.write_text(s)
print('Applied V27: compact subtitle panels + timeline-adjacent tools + working background opacity')
