from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

def rep(old: str, new: str, label: str, required=True):
    global s
    if old not in s:
        if required:
            raise SystemExit(f'V29 marker missing: {label}')
        return False
    s = s.replace(old, new, 1)
    return True

# V29: ultra-compact player chrome based on the supplied landscape reference.
# Presentation only. Preserve V24 subtitle/server ownership and V25/V27 styling logic.

# Top chrome: smaller controls and tighter margins.
rep('.font(.system(size: 15, weight: .bold))\n                .frame(width: 36, height: 36)',
    '.font(.system(size: 13, weight: .bold))\n                .frame(width: 32, height: 32)', 'close button')
rep('.frame(width: 28, height: 28)', '.frame(width: 24, height: 24)', 'airplay')
rep('.padding(.horizontal, 10)\n                    .frame(height: 36)', '.padding(.horizontal, 8)\n                    .frame(height: 32)', 'left top capsule')
rep('.font(.system(size: 16, weight: .medium))\n                        .lineLimit(1)', '.font(.system(size: 14, weight: .medium))\n                        .lineLimit(1)', 'title')
rep('HStack(spacing: 14) {', 'HStack(spacing: 11) {', 'top right spacing')
rep('.font(.system(size: 16, weight: .semibold))\n                    .padding(.horizontal, 13)\n                    .frame(height: 36)',
    '.font(.system(size: 14, weight: .semibold))\n                    .padding(.horizontal, 10)\n                    .frame(height: 32)', 'top right capsule')
rep('.padding(.horizontal, 18)\n                .padding(.top, max(proxy.safeAreaInsets.top, 10))',
    '.padding(.horizontal, 14)\n                .padding(.top, max(proxy.safeAreaInsets.top, 8))', 'top margins')

# Center transport controls: less dominant on landscape.
rep('HStack(spacing: 44) {', 'HStack(spacing: 36) {', 'transport spacing')
rep('Image(systemName: "gobackward.10").font(.system(size: 30, weight: .medium))',
    'Image(systemName: "gobackward.10").font(.system(size: 26, weight: .medium))', 'back 10')
rep('Image(systemName: "goforward.10").font(.system(size: 30, weight: .medium))',
    'Image(systemName: "goforward.10").font(.system(size: 26, weight: .medium))', 'forward 10')
rep('''                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .bold))
                            .frame(width: 68, height: 68)''',
    '''                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 29, weight: .bold))
                            .frame(width: 58, height: 58)''', 'center play')

# Subtitle quick tools: 32pt and almost attached to the timeline.
rep('.font(.system(size: 16, weight: .semibold, design: .rounded))\n                                .frame(width: 36, height: 36)',
    '.font(.system(size: 14, weight: .semibold, design: .rounded))\n                                .frame(width: 32, height: 32)', 'subtitle style quick button')
rep('.font(.system(size: 15, weight: .semibold))\n                                .frame(width: 36, height: 36)',
    '.font(.system(size: 13, weight: .semibold))\n                                .frame(width: 32, height: 32)', 'subtitle timing quick button')
rep('.padding(3)\n                    .background(.black.opacity(0.54), in: Capsule())',
    '.padding(2)\n                    .background(.black.opacity(0.50), in: Capsule())', 'subtitle dock padding')
rep('.padding(.horizontal, 22)\n                .frame(height: 0)\n                .offset(y: -52)',
    '.padding(.horizontal, 18)\n                .frame(height: 0)\n                .offset(y: -34)', 'subtitle dock position')

# Timeline: thinner and tighter.
rep('.font(.caption2.monospacedDigit())\n                        .frame(width: 56, alignment: .leading)',
    '.font(.system(size: 11, design: .monospaced))\n                        .frame(width: 50, alignment: .leading)', 'elapsed time')
rep('.font(.caption2.monospacedDigit())\n                        .frame(width: 60, alignment: .trailing)',
    '.font(.system(size: 11, design: .monospaced))\n                        .frame(width: 54, alignment: .trailing)', 'remaining time')
rep('''                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
                .padding(.horizontal, 22)''',
    '''                .padding(.horizontal, 18)
                .frame(height: 40)
                .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10)))
                .padding(.horizontal, 18)''', 'timeline')

# Right-side sheets: narrower, denser, less empty space.
rep('trailingPanel(width: min(proxy.size.width * 0.52, 620), title: "Quality & Server")',
    'trailingPanel(width: min(proxy.size.width * 0.40, 470), title: "Quality & Server")', 'quality sheet')
rep('trailingPanel(width: min(proxy.size.width * 0.52, 620), title: "Subtitles")',
    'trailingPanel(width: min(proxy.size.width * 0.40, 470), title: "Subtitles")', 'subtitle sheet')
rep('trailingPanel(width: min(proxy.size.width * 0.48, 560), title: "Audio")',
    'trailingPanel(width: min(proxy.size.width * 0.36, 420), title: "Audio")', 'audio sheet', required=False)
rep('trailingPanel(width: min(proxy.size.width * 0.50, 590), title: "Playback")',
    'trailingPanel(width: min(proxy.size.width * 0.40, 470), title: "Playback")', 'playback sheet')
rep('VStack(alignment: .leading, spacing: 18) {', 'VStack(alignment: .leading, spacing: 12) {', 'sheet spacing')
rep('Text(title).font(.title3.bold())', 'Text(title).font(.system(size: 17, weight: .bold))', 'sheet title')
# visibility_fix may split the width/maxHeight frame, so compact the first trailing-panel padding directly.
if '.padding(26)' in s:
    s = s.replace('.padding(26)', '.padding(18)', 1)
else:
    rep('.padding(26)\n            .frame(width: width, maxHeight: .infinity, alignment: .topLeading)',
        '.padding(18)\n            .frame(width: width, maxHeight: .infinity, alignment: .topLeading)', 'sheet padding', required=False)

# Rows/settings: tighter vertical rhythm.
s = s.replace('Text(title).font(.headline)', 'Text(title).font(.system(size: 16, weight: .semibold))')
s = s.replace('.padding(.vertical, 9)', '.padding(.vertical, 6)')
s = s.replace('VStack(alignment: .leading, spacing: 20) {', 'VStack(alignment: .leading, spacing: 14) {')
s = s.replace('.frame(height: 40)\n                .background(selected ? Color.blue', '.frame(height: 34)\n                .background(selected ? Color.blue')
s = s.replace('.font(.subheadline.weight(.medium))\n                .padding(.horizontal, 14)', '.font(.caption.weight(.semibold))\n                .padding(.horizontal, 11)')

# Subtitle appearance/timing popovers: much smaller and packed.
rep('maxWidth: 720', 'maxWidth: 560', 'appearance width')
rep('maxWidth: 600', 'maxWidth: 480', 'timing width')
rep('.padding(13)\n            .frame(width: min(maxWidth, max(300, proxy.size.width - 32)))',
    '.padding(10)\n            .frame(width: min(maxWidth, max(280, proxy.size.width - 24)))', 'compact panel padding')
rep('.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))',
    '.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))', 'compact panel corner')
rep('.overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))',
    '.overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.12), lineWidth: 1))', 'compact panel stroke')
rep('.padding(.bottom, max(proxy.safeAreaInsets.bottom + 58, 68))',
    '.padding(.bottom, max(proxy.safeAreaInsets.bottom + 46, 54))', 'compact panel bottom')

# Compact subtitle editor internal spacing and controls.
s = s.replace('VStack(spacing: 14) {', 'VStack(spacing: 10) {', 1)
s = s.replace('HStack(spacing: 18) {', 'HStack(spacing: 12) {', 1)
s = s.replace('Divider().frame(height: 54)', 'Divider().frame(height: 44)')
s = s.replace('HStack(alignment: .top, spacing: 22) {', 'HStack(alignment: .top, spacing: 14) {')
s = s.replace('.frame(width: 26, height: 26)', '.frame(width: 24, height: 24)')
s = s.replace('.frame(height: 30)', '.frame(height: 28)')

# Reduce panel shadow cost/visual bulk.
s = s.replace('.shadow(color: .black.opacity(0.45), radius: 22, y: 10)',
              '.shadow(color: .black.opacity(0.34), radius: 12, y: 6)')

if 'V29_ULTRA_COMPACT_CHROME' not in s:
    s = '// V29_ULTRA_COMPACT_CHROME: tighter player chrome, smaller sheets, timeline-adjacent subtitle tools.\n' + s

p.write_text(s)
print('Applied V29 ultra-compact player UI')
