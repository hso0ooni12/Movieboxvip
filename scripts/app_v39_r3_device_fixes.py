"""R3: on-device fixes layered after the verified V39/R2 pipeline."""
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"V39 R3 fix: missing {label}")
    return text.replace(old, new, 1)


player_path = Path("FrameNative/FrameXTVPlayerV6.swift")
sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
player = player_path.read_text(encoding="utf-8")
sports = sports_path.read_text(encoding="utf-8")

# Carry the source label's quality through to the web bridge. This is an
# identifier, not an inferred quality: it is parsed directly from the source.
player = replace_once(
    player,
    'var payload: [String: Any] = ["action": "server", "name": server.name]\n        if let provider = server.provider { payload["provider"] = provider }',
    'var payload: [String: Any] = ["action": "server", "name": server.name]\n        if !server.quality.isEmpty { payload["quality"] = server.quality }\n        if let provider = server.provider { payload["provider"] = provider }',
    "server quality identity payload",
)

old_server_helpers = '''      function selectByText(text) {
        const wanted = String(text || '').trim().toLowerCase();
        if (!wanted) return false;
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div'));
          const candidates = nodes.filter(el => {
            const t = cleanText(el).toLowerCase();
            return t === wanted || t.startsWith(wanted + ' ') || wanted.startsWith(t + ' ');
          }).sort((a,b) => cleanText(a).length - cleanText(b).length);
          const found = candidates[0];
          if (found) {
            const clickable = found.closest('button,[role="button"],[role="menuitem"],li') || found;
            clickable.click();
            return true;
          }
        } catch (_) {}
        return false;
      }
'''
new_server_helpers = '''      function selectByText(text) {
        const wanted = String(text || '').trim().toLowerCase();
        if (!wanted) return false;
        try {
          const nodes = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div'));
          const candidates = nodes.filter(el => {
            const t = cleanText(el).toLowerCase();
            return t === wanted || t.startsWith(wanted + ' ') || wanted.startsWith(t + ' ');
          }).sort((a,b) => cleanText(a).length - cleanText(b).length);
          const found = candidates[0];
          if (found) {
            const clickable = found.closest('button,[role="button"],[role="menuitem"],li') || found;
            clickable.click();
            return true;
          }
        } catch (_) {}
        return false;
      }

      // Servers are source-owned controls. Match their parsed source label
      // exactly so a generic name such as "Backup" cannot click an unrelated
      // container or the first similarly-named row.
      function selectServerRow(name, quality) {
        const wantedName = String(name || '').trim().toLowerCase();
        const wantedQuality = sourceServerQuality(quality);
        if (!wantedName) return false;
        try {
          const candidates = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div'))
            .map(el => ({el,row:parseServerRow(cleanText(el))}))
            .filter(item => item.row && item.row.name.toLowerCase() === wantedName && (!wantedQuality || item.row.quality === wantedQuality))
            .sort((a,b) => {
              const score = item => item.el.matches('button,[role="button"],[role="menuitem"],li') ? 0 : 1;
              return score(a) - score(b) || cleanText(a.el).length - cleanText(b.el).length;
            });
          const found = candidates[0] && candidates[0].el;
          if (!found) return false;
          (found.closest('button,[role="button"],[role="menuitem"],li') || found).click();
          return true;
        } catch (_) { return false; }
      }

      function sourceServerIsSelected(name, quality) {
        const wantedName = String(name || '').trim().toLowerCase();
        const wantedQuality = sourceServerQuality(quality);
        try {
          return Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div')).some(el => {
            const row = parseServerRow(cleanText(el));
            return row && row.selected && row.name.toLowerCase() === wantedName && (!wantedQuality || row.quality === wantedQuality);
          });
        } catch (_) { return false; }
      }
'''
player = replace_once(player, old_server_helpers, new_server_helpers, "precise source server selector")
player = replace_once(
    player,
    "const key = row.name.toLowerCase();",
    "const key = row.name.toLowerCase() + '|' + row.quality;",
    "source server uniqueness",
)

old_server_command = '''          else if (action === 'server') {
            sourceSubtitles.reset();
            const name = String(payload.name || '');
            if (name && name.toLowerCase() !== 'auto') {
              const trySelect = (attempt) => {
                let clicked = selectByText(name);
                if (!clicked) { openServerMenu(); hideSourcePanels(); }
                setTimeout(() => {
                  if (!clicked) clicked = selectByText(name);
                  hideSourcePanels();
                  setTimeout(() => {
                    scanServers();
                    const rows = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div'));
                    const confirmed = rows.some(el => {
                      const row = parseServerRow(cleanText(el));
                      return row && row.selected && row.name.toLowerCase() === name.toLowerCase();
                    });
                    if (!confirmed && attempt < 2) trySelect(attempt + 1);
                  },420);
                },180);
              };
              trySelect(0);
            }
          }
'''
new_server_command = '''          else if (action === 'server') {
            const name = String(payload.name || '');
            const quality = String(payload.quality || '');
            if (name && name.toLowerCase() !== 'auto') {
              let finished = false;
              const finishSelection = () => {
                if (finished) return;
                finished = true;
                // Keep the current subtitle catalog alive until the source
                // confirms its selected server. A failed source click must not
                // make valid captions disappear.
                sourceSubtitles.reset();
                setTimeout(openAndScanSubtitles, 260);
                setTimeout(openAndScanSubtitles, 760);
              };
              const trySelect = (attempt) => {
                let clicked = selectServerRow(name, quality);
                if (!clicked) openServerMenu();
                setTimeout(() => {
                  if (!clicked) clicked = selectServerRow(name, quality);
                  hideSourcePanels();
                  setTimeout(() => {
                    scanServers();
                    if (sourceServerIsSelected(name, quality)) {
                      finishSelection();
                    } else if (attempt < 3) {
                      openServerMenu();
                      setTimeout(() => trySelect(attempt + 1), 90);
                    }
                  }, 460);
                }, 190);
              };
              trySelect(0);
            }
          }
'''
player = replace_once(player, old_server_command, new_server_command, "confirmed source server handoff")
player_path.write_text(player, encoding="utf-8")

# The GeometryReader may retain the portrait proposal during an immediate
# full-screen rotation. Let SwiftUI offer the native full surface instead.
sports = replace_once(
    sports,
    '''            GeometryReader { proxy in
                XSVLCVideoSurface(
                    player: model.player,
                    onSurfaceReady: { model.surfaceDidBecomeReady() }
                )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .transaction { transaction in
                transaction.animation = nil
            }
''',
    '''            XSVLCVideoSurface(
                player: model.player,
                onSurfaceReady: { model.surfaceDidBecomeReady() }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .transaction { transaction in
                transaction.animation = nil
            }
''',
    "transient GeometryReader surface",
)

# A raw orientation event occurs before UIKit commits its final bounds. The
# surface coordinator handles the settled bounds and a final same-view rebind.
sports = replace_once(
    sports,
    '''        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            model.recoverAfterSurfaceChange()
            revealControls()
        }
''',
    '''        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Do not touch VLC during the temporary portrait/landscape bounds.
            // XSVLCVideoSurface rebinds only after its final layout pass.
            revealControls()
        }
''',
    "early orientation VLC reset",
)

sports = replace_once(sports, "private final class XSVLCStableSurfaceView: UIView {", "// V39_R3_DEVICE_FIXES\nprivate final class XSVLCStableSurfaceView: UIView {", "R3 marker")
sports = replace_once(
    sports,
    '''        videoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(videoView)
''',
    '''        videoView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(videoView)
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.topAnchor.constraint(equalTo: topAnchor),
            videoView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
''',
    "constraint-backed VLC surface",
)
sports = replace_once(
    sports,
    '''        UIView.performWithoutAnimation {
            videoView.transform = .identity
            videoView.frame = bounds
            videoView.layoutIfNeeded()
        }
''',
    '''        UIView.performWithoutAnimation {
            videoView.transform = .identity
            layoutIfNeeded()
        }
''',
    "manual VLC surface frame",
)
sports = replace_once(
    sports,
    "        func refreshGeometry() {",
    "        func refreshGeometry(forceDrawableRebind: Bool = false) {",
    "refresh function signature",
)
sports = replace_once(
    sports,
    '''            if drawableChanged {
                player.drawable = drawable
            }
''',
    '''            if drawableChanged || forceDrawableRebind {
                // Re-assign the same final drawable only after layout settles;
                // never detach to nil during an interactive rotation.
                player.drawable = drawable
            }
''',
    "settled drawable rebind",
)
sports = replace_once(
    sports,
    "            if drawableChanged || sizeChanged {",
    "            if drawableChanged || sizeChanged || forceDrawableRebind {",
    "rebound auto-fit",
)
sports = replace_once(
    sports,
    '''            for delay in [0.0, 0.06, 0.18, 0.40, 0.82] {
                let item = DispatchWorkItem { [weak self] in
                    self?.refreshGeometry()
                }
''',
    '''            let delays: [TimeInterval] = [0.0, 0.08, 0.22, 0.48, 0.92]
            for (index, delay) in delays.enumerated() {
                let item = DispatchWorkItem { [weak self] in
                    self?.refreshGeometry(forceDrawableRebind: index == delays.count - 1)
                }
''',
    "settled surface refresh sequence",
)
sports_path.write_text(sports, encoding="utf-8")
