from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

def replace(old, new):
    global s
    if old not in s:
        raise SystemExit('V25 expected source marker missing: ' + old[:120])
    s = s.replace(old, new, 1)

def section(start, end, new):
    global s
    a = s.find(start)
    if a < 0:
        raise SystemExit('V25 start marker missing: ' + start[:120])
    b = s.find(end, a)
    if b < 0:
        raise SystemExit('V25 end marker missing: ' + end[:120])
    s = s[:a] + new + s[b:]

# ---------------------------------------------------------------------------
# Source subtitle renderer: preserve V24 selection exactly; styling only.
# Eliminate the provider's bottom->up movement by restricting transitions to
# opacity and styling newly inserted cue nodes before the next paint.
# ---------------------------------------------------------------------------
replace(
"      let timingTrack = null;\n      let style = {size: 1, color: '#ffffff', background: true, bottom: 76};",
"      let timingTrack = null, captionObserver = null;\n      let style = {size: 1, color: '#ffffff', background: true, backgroundStyle: 'black', backgroundOpacity: 0.68, bottom: 76};"
)

replace(
"      function hidePanels() {",
r'''      function subtitleBackgroundCSS() {
        const mode = String(style.backgroundStyle || (style.background === false ? 'none' : 'black')).toLowerCase();
        if (mode === 'none' || style.background === false) return 'transparent';
        const alpha = Math.max(0, Math.min(1, Number(style.backgroundOpacity == null ? 0.68 : style.backgroundOpacity)));
        const rgb = mode === 'white' ? [255,255,255] : (mode === 'gray' ? [48,48,48] : [0,0,0]);
        return 'rgba(' + rgb[0] + ',' + rgb[1] + ',' + rgb[2] + ',' + alpha + ')';
      }
      function hidePanels() {'''
)

replace(
"'video::cue{font-size:' + Math.round(22 * style.size) + 'px!important;color:' + style.color + '!important;background:' + (style.background ? 'rgba(0,0,0,.68)' : 'transparent') + '!important}';",
"'video::cue{font-size:' + Math.round(22 * style.size) + 'px!important;color:' + style.color + '!important;background:' + subtitleBackgroundCSS() + '!important}';"
)

section(
"      function applyStyle() {",
"\n      function reportCaption() {",
r'''      function applyStyle() {
        hidePanels();
        const customTiming = delay !== 0 && active && trackFor(active);
        const bg = subtitleBackgroundCSS();
        for (const el of sourceCaptionNodes()) {
          // The source player animates its bottom offset when captions mount or
          // controls change. Keep only a tiny opacity fade; position is instant.
          el.style.setProperty('transition', 'opacity 120ms linear', 'important');
          el.style.setProperty('transition-property', 'opacity', 'important');
          el.style.setProperty('animation', 'none', 'important');
          el.style.setProperty('will-change', 'opacity', 'important');
          el.style.setProperty('font-size', Math.round(22 * style.size) + 'px', 'important');
          el.style.setProperty('color', style.color, 'important');
          el.style.setProperty('bottom', style.bottom + 'px', 'important');
          el.style.setProperty('background-color', bg, 'important');
          el.style.setProperty('border-radius', bg === 'transparent' ? '0' : '6px', 'important');
          el.style.setProperty('padding', bg === 'transparent' ? '0' : '4px 10px', 'important');
          if (customTiming) el.style.setProperty('opacity', '0', 'important');
          else el.style.removeProperty('opacity');
        }
      }
      function installCaptionObserver() {
        const begin = () => {
          if (!doc.documentElement || captionObserver || !win.MutationObserver) return;
          captionObserver = new win.MutationObserver(() => applyStyle());
          captionObserver.observe(doc.documentElement, {subtree:true, childList:true});
          applyStyle();
        };
        if (doc.documentElement) begin();
        else doc.addEventListener('DOMContentLoaded', begin, {once:true});
      }
'''
)

replace(
"      function dispose() { disposed = true; pending = null; for (const id of timers) win.clearTimeout(id); timers.clear(); }\n      return {frameID, scan, publish, select, reset, tick, hidePanels, dispose,",
"      function dispose() { disposed = true; pending = null; if (captionObserver) captionObserver.disconnect(); for (const id of timers) win.clearTimeout(id); timers.clear(); }\n      installCaptionObserver();\n      return {frameID, scan, publish, select, reset, tick, hidePanels, dispose,"
)

# ---------------------------------------------------------------------------
# Swift bridge: persistent subtitle appearance settings.
# ---------------------------------------------------------------------------
section(
"    func setSubtitleStyle(size: Double, color: String, background: Bool, bottom: Double) {",
"\n    func selectSubtitle(_ option: XSSubtitleOption?) {",
r'''    func setSubtitleStyle(size: Double, color: String, backgroundStyle: String, backgroundOpacity: Double, bottom: Double) {
        send([
            "action": "subtitleStyle",
            "size": size,
            "color": color,
            "background": backgroundStyle != "none",
            "backgroundStyle": backgroundStyle,
            "backgroundOpacity": backgroundOpacity,
            "bottom": bottom
        ])
    }
'''
)

replace(
'    @AppStorage("XSTV.subtitleBackground") private var subtitleBackground = true\n    @AppStorage("XSTV.subtitleColor") private var subtitleColor = "#FFFFFF"',
'''    @AppStorage("XSTV.subtitleBackground") private var subtitleBackground = true
    @AppStorage("XSTV.subtitleBackgroundStyle") private var subtitleBackgroundStyle = "black"
    @AppStorage("XSTV.subtitleBackgroundOpacity") private var subtitleBackgroundOpacity = 0.68
    @AppStorage("XSTV.subtitleColor") private var subtitleColor = "#FFFFFF"'''
)

replace(
'''        .onChange(of: subtitleBackground) { _ in pushSubtitleStyle() }
        .onChange(of: subtitleColor) { _ in pushSubtitleStyle() }''',
'''        .onChange(of: subtitleBackground) { _ in pushSubtitleStyle() }
        .onChange(of: subtitleBackgroundStyle) { _ in pushSubtitleStyle() }
        .onChange(of: subtitleBackgroundOpacity) { _ in pushSubtitleStyle() }
        .onChange(of: subtitleColor) { _ in pushSubtitleStyle() }'''
)

# Polished bottom appearance editor. It only changes rendering, never V24's
# subtitle catalog/selection/server logic.
section(
"    private var subtitleStylePanel: some View {",
"\n    private var subtitleDelayPanel: some View {",
r'''    private var subtitleStylePanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Label("Subtitle Appearance", systemImage: "captions.bubble.fill")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    subtitleScale = 1.0
                    subtitleColor = "#FFFFFF"
                    subtitleBackground = true
                    subtitleBackgroundStyle = "black"
                    subtitleBackgroundOpacity = 0.68
                    subtitleBottom = 76
                }
                .buttonStyle(.bordered)
                Button { closePanel() } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Size · \(Int(subtitleScale * 100))%")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button { subtitleScale = max(0.7, subtitleScale - 0.1) } label: {
                                Image(systemName: "minus.circle.fill").font(.title2)
                            }
                            Slider(value: $subtitleScale, in: 0.7...1.8, step: 0.05)
                                .frame(width: 150).tint(.white)
                            Button { subtitleScale = min(1.8, subtitleScale + 0.1) } label: {
                                Image(systemName: "plus.circle.fill").font(.title2)
                            }
                        }
                    }
                    .frame(width: 250, alignment: .leading)

                    Divider().frame(height: 82)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Text Color").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 9) {
                            colorButton("#FFFFFF", .white)
                            colorButton("#FFD60A", .yellow)
                            colorButton("#00D4FF", .cyan)
                            colorButton("#34C759", .green)
                            colorButton("#FF9F0A", .orange)
                            colorButton("#FF453A", .red)
                        }
                    }

                    Divider().frame(height: 82)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Background").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            backgroundButton("None", style: "none", preview: .clear)
                            backgroundButton("Black", style: "black", preview: .black)
                            backgroundButton("Gray", style: "gray", preview: Color(white: 0.28))
                            backgroundButton("White", style: "white", preview: .white)
                        }
                        if subtitleBackgroundStyle != "none" {
                            HStack(spacing: 8) {
                                Text("Opacity").font(.caption2).foregroundStyle(.secondary)
                                Slider(value: $subtitleBackgroundOpacity, in: 0.20...1.0, step: 0.05)
                                    .frame(width: 155).tint(.white)
                                Text("\(Int(subtitleBackgroundOpacity * 100))%")
                                    .font(.caption2.monospacedDigit()).frame(width: 38)
                            }
                        }
                    }
                    .frame(width: 340, alignment: .leading)

                    Divider().frame(height: 82)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Position · \(Int(subtitleBottom))")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            Button { subtitleBottom = max(32, subtitleBottom - 12) } label: {
                                Image(systemName: "arrow.down.circle.fill").font(.title2)
                            }
                            Slider(value: $subtitleBottom, in: 32...220, step: 4)
                                .frame(width: 150).tint(.white)
                            Button { subtitleBottom = min(220, subtitleBottom + 12) } label: {
                                Image(systemName: "arrow.up.circle.fill").font(.title2)
                            }
                        }
                    }
                    .frame(width: 250, alignment: .leading)
                }
            }
        }
        .foregroundStyle(.white)
    }
'''
)

# Replace helpers and caption overlay to use the selected background style.
section(
"    private func colorButton(_ hex: String, _ color: Color) -> some View {",
"\n    private var loadingOverlay: some View {",
r'''    private func colorButton(_ hex: String, _ color: Color) -> some View {
        Button { subtitleColor = hex } label: {
            RoundedRectangle(cornerRadius: 7)
                .fill(color)
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(subtitleColor == hex ? Color.blue : Color.white.opacity(0.28), lineWidth: subtitleColor == hex ? 3 : 1))
        }
        .buttonStyle(.plain)
    }

    private func backgroundButton(_ title: String, style: String, preview: Color) -> some View {
        Button {
            subtitleBackgroundStyle = style
            subtitleBackground = style != "none"
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(preview)
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.28)))
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(subtitleBackgroundStyle == style ? Color.blue.opacity(0.72) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var subtitleBackgroundColor: Color {
        switch subtitleBackgroundStyle {
        case "white": return .white
        case "gray": return Color(white: 0.19)
        default: return .black
        }
    }

    private func captionOverlay(width: CGFloat) -> some View {
        VStack {
            Spacer()
            Text(player.captionText)
                .font(.system(size: max(18, min(width * 0.028, 34)) * subtitleScale, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(colorFromHex(subtitleColor))
                .padding(.horizontal, 13)
                .padding(.vertical, subtitleBackgroundStyle == "none" ? 0 : 7)
                .background(subtitleBackgroundStyle == "none" ? Color.clear : subtitleBackgroundColor.opacity(subtitleBackgroundOpacity), in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: .black.opacity(0.9), radius: 2)
                .padding(.horizontal, width * 0.12)
                .padding(.bottom, subtitleBottom)
                .animation(nil, value: player.captionText)
        }
        .allowsHitTesting(false)
    }
'''
)

replace(
'''    private func pushSubtitleStyle() {
        player.setSubtitleStyle(size: subtitleScale, color: subtitleColor, background: subtitleBackground, bottom: subtitleBottom)
    }''',
'''    private func pushSubtitleStyle() {
        player.setSubtitleStyle(
            size: subtitleScale,
            color: subtitleColor,
            backgroundStyle: subtitleBackgroundStyle,
            backgroundOpacity: subtitleBackgroundOpacity,
            bottom: subtitleBottom
        )
    }'''
)

replace(
'''        case "#00D4FF": return .cyan
        default: return .white''',
'''        case "#00D4FF": return .cyan
        case "#34C759": return .green
        case "#FF9F0A": return .orange
        case "#FF453A": return .red
        default: return .white'''
)

p.write_text(s)
print('Applied V25: stable caption position + persistent size/color/background/position controls')
