from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

def rep(old: str, new: str, label: str, required=True):
    global s
    if old not in s:
        if required:
            raise SystemExit(f'V28 marker missing: {label}')
        return False
    s = s.replace(old, new, 1)
    return True

# ---------------------------------------------------------------------------
# V28: proportionally smaller, reference-style player chrome.
# Presentation only: do not alter V24 subtitle/server bridge or V25/V27 logic.
# ---------------------------------------------------------------------------

# Top-left close button.
rep(
'''            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)''',
'''            Image(systemName: systemName)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 36, height: 36)''',
'roundButton size'
)

# Top-left PiP / AirPlay capsule.
rep('.frame(width: 35, height: 35)', '.frame(width: 28, height: 28)', 'AirPlay size')
rep('.padding(.horizontal, 13)\n                    .frame(height: 44)', '.padding(.horizontal, 10)\n                    .frame(height: 36)', 'left top capsule size')

# Title and top-right controls.
rep('.font(.headline.weight(.medium))\n                        .lineLimit(1)', '.font(.system(size: 16, weight: .medium))\n                        .lineLimit(1)', 'playback title size')
rep('HStack(spacing: 17) {', 'HStack(spacing: 14) {', 'top right spacing')
rep('.font(.system(size: 19, weight: .semibold))\n                    .padding(.horizontal, 16)\n                    .frame(height: 44)', '.font(.system(size: 16, weight: .semibold))\n                    .padding(.horizontal, 13)\n                    .frame(height: 36)', 'top right capsule')
rep('.padding(.horizontal, 22)\n                .padding(.top, max(proxy.safeAreaInsets.top, 14))', '.padding(.horizontal, 18)\n                .padding(.top, max(proxy.safeAreaInsets.top, 10))', 'top bar margins')

# Center transport controls: smaller and balanced like the supplied reference.
rep('HStack(spacing: 52) {', 'HStack(spacing: 44) {', 'transport spacing')
rep('Image(systemName: "gobackward.10").font(.system(size: 38, weight: .medium))', 'Image(systemName: "gobackward.10").font(.system(size: 30, weight: .medium))', 'back 10 size')
rep('Image(systemName: "goforward.10").font(.system(size: 38, weight: .medium))', 'Image(systemName: "goforward.10").font(.system(size: 30, weight: .medium))', 'forward 10 size')
rep('''                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44, weight: .bold))
                            .frame(width: 88, height: 88)''',
'''                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 34, weight: .bold))
                            .frame(width: 68, height: 68)''',
'center play size'
)

# Bottom utility areas differ slightly after V8/V26, so compact any remaining
# 48pt chrome rather than depending on one old exact block.
rep('''                    .padding(.horizontal, 18)
                    .frame(height: 48)''',
'''                    .padding(.horizontal, 14)
                    .frame(height: 40)''',
'bottom utility capsule', required=False
)
s = s.replace('.frame(height: 48)', '.frame(height: 40)')
rep('.padding(.horizontal, 28)\n                .padding(.bottom, 12)', '.padding(.horizontal, 22)\n                .padding(.bottom, 8)', 'bottom utility margins', required=False)

# V26/V27 native subtitle tools dock: smaller and closer to timeline.
rep('.font(.system(size: 19, weight: .semibold, design: .rounded))\n                                .frame(width: 46, height: 46)', '.font(.system(size: 16, weight: .semibold, design: .rounded))\n                                .frame(width: 36, height: 36)', 'subtitle appearance quick button')
rep('.font(.system(size: 18, weight: .semibold))\n                                .frame(width: 46, height: 46)', '.font(.system(size: 15, weight: .semibold))\n                                .frame(width: 36, height: 36)', 'subtitle timing quick button')
rep('.padding(5)\n                    .background(.black.opacity(0.54), in: Capsule())', '.padding(3)\n                    .background(.black.opacity(0.54), in: Capsule())', 'subtitle dock padding')
rep('.padding(.horizontal, 28)\n                .frame(height: 0)\n                .offset(y: -64)', '.padding(.horizontal, 22)\n                .frame(height: 0)\n                .offset(y: -52)', 'subtitle dock timeline position')

# Timeline: compact height and margins matching the reference screenshots.
rep('.font(.caption.monospacedDigit())\n                        .frame(width: 64, alignment: .leading)', '.font(.caption2.monospacedDigit())\n                        .frame(width: 56, alignment: .leading)', 'elapsed time typography')
rep('.font(.caption.monospacedDigit())\n                        .frame(width: 68, alignment: .trailing)', '.font(.caption2.monospacedDigit())\n                        .frame(width: 60, alignment: .trailing)', 'remaining time typography')
rep('''                .padding(.horizontal, 28)
                .frame(height: 54)
                .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))
                .padding(.horizontal, 28)''',
'''                .padding(.horizontal, 22)
                .frame(height: 44)
                .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
                .padding(.horizontal, 22)''',
'timeline geometry'
)

# Compact subtitle panels further so they feel native and don't dominate playback.
rep('maxWidth: 820', 'maxWidth: 720', 'appearance panel max width')
rep('maxWidth: 680', 'maxWidth: 600', 'timing panel max width')
rep('.padding(16)\n            .frame(width: min(maxWidth, max(320, proxy.size.width - 40)))', '.padding(13)\n            .frame(width: min(maxWidth, max(300, proxy.size.width - 32)))', 'compact panel padding')
rep('.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))', '.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))', 'compact panel corner')
rep('.overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))', '.overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))', 'compact panel stroke')
rep('.padding(.bottom, max(proxy.safeAreaInsets.bottom + 76, 88))', '.padding(.bottom, max(proxy.safeAreaInsets.bottom + 58, 68))', 'compact panel bottom position')

# Smaller subtitle editor controls/chips.
s = s.replace('.font(.title3)', '.font(.system(size: 17, weight: .semibold))', 4)
s = s.replace('.frame(width: 30, height: 30)', '.frame(width: 26, height: 26)')
s = s.replace('.frame(height: 32)', '.frame(height: 30)')

# Marker for QA.
marker = '// V27_COMPACT_SUBTITLE_UI:'
if marker in s and 'V28_PROPORTIONAL_PLAYER_CHROME' not in s:
    s = s.replace(marker, '// V28_PROPORTIONAL_PLAYER_CHROME: reduced player/control sizes and tightened reference-style spacing.\n' + marker, 1)

p.write_text(s)
print('Applied V28: proportionally smaller player chrome, reference-style spacing, compact subtitle tools')
