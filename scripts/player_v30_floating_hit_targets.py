from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

# Keep the proven V24 subtitle/server engine untouched. V30 changes presentation and hit testing only.
# Replace individual Swift functions by matching braces, never a broad regex range. This preserves
# every helper function between trailingPanel/panelRow and the surrounding player code.

def replace_swift_function(source: str, signature: str, replacement: str) -> str:
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f'V30 function marker missing: {signature}')
    brace = source.find('{', start)
    if brace < 0:
        raise SystemExit(f'V30 opening brace missing: {signature}')

    depth = 0
    i = brace
    in_string = False
    escaped = False
    while i < len(source):
        ch = source[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == '{':
                depth += 1
            elif ch == '}':
                depth -= 1
                if depth == 0:
                    return source[:start] + replacement + source[i + 1:]
        i += 1
    raise SystemExit(f'V30 closing brace missing: {signature}')

trailing_replacement = '''    private func trailingPanel<Content: View>(width: CGFloat, title: String, @ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.14)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { closePanel() }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Button {
                        closePanel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(XSPlayerTapButtonStyle())
                }

                Divider().overlay(.white.opacity(0.08))
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(14)
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
            .shadow(color: .black.opacity(0.38), radius: 18, y: 7)
            .padding(.trailing, 14)
            .padding(.vertical, 18)
        }
        .transition(.opacity)
    }'''

s = replace_swift_function(
    s,
    '    private func trailingPanel<Content: View>(width: CGFloat, title: String, @ViewBuilder content: () -> Content) -> some View',
    trailing_replacement,
)

# Narrower floating cards leave more of the video visible. V29 supplies the compact starting widths.
s = s.replace('proxy.size.width * 0.40, 470', 'proxy.size.width * 0.36, 430')
s = s.replace('proxy.size.width * 0.36, 420', 'proxy.size.width * 0.33, 390')

row_replacement = '''    private func panelRow(title: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.36))
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(XSPlayerTapButtonStyle())
    }'''

s = replace_swift_function(
    s,
    '    private func panelRow(title: String, detail: String?, action: @escaping () -> Void) -> some View',
    row_replacement,
)

# More forgiving invisible touch area on the rest of the player buttons.
s = s.replace('.buttonStyle(.plain)', '.buttonStyle(XSPlayerTapButtonStyle())')

if 'private struct XSPlayerTapButtonStyle: ButtonStyle' not in s:
    s += '''\n\nprivate struct XSPlayerTapButtonStyle: ButtonStyle {\n    func makeBody(configuration: Configuration) -> some View {\n        configuration.label\n            .padding(7)\n            .contentShape(Rectangle())\n            .padding(-7)\n            .opacity(configuration.isPressed ? 0.74 : 1)\n            .scaleEffect(configuration.isPressed ? 0.975 : 1)\n            .animation(.easeOut(duration: 0.075), value: configuration.isPressed)\n    }\n}\n'''

if 'V30_FLOATING_HIT_TARGETS' not in s:
    s = '// V30_FLOATING_HIT_TARGETS: floating player menus + forgiving button hit areas.\n' + s

p.write_text(s)
print('Applied V30 floating menus and responsive hit targets safely')
