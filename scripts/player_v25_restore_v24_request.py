from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

if 'private func clearSubtitleRequest()' not in s:
    marker = '    func selectSubtitle(_ option: XSSubtitleOption?) {'
    if marker not in s:
        raise SystemExit('V25 could not find selectSubtitle to restore V24 request state')
    helper = '''    private func clearSubtitleRequest() {
        subtitleTimeout?.cancel()
        subtitleRequestID = nil
        pendingSubtitleID = nil
        subtitleSelectionError = nil
    }

'''
    s = s.replace(marker, helper + marker, 1)
    p.write_text(s)
    print('Restored V24 clearSubtitleRequest helper after V25 styling patch')
else:
    print('V24 clearSubtitleRequest helper already present')
