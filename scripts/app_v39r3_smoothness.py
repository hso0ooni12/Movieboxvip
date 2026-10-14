from pathlib import Path
import re

PLAYER = Path("FrameNative/FrameXTVPlayerV6.swift")
MARKER = "V39R3_PLAYER_SMOOTHNESS"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise SystemExit(f"V39R3: {label} marker not found")
    return source.replace(old, new, 1)


s = PLAYER.read_text(encoding="utf-8")
if MARKER in s:
    print("V39R3 already applied")
    raise SystemExit(0)
if "V39R_SURGICAL_PLAYER_FIX" not in s:
    raise SystemExit("V39R3: expected V39R2 source is missing")

s = replace_once(
    s,
    "// V39R_SURGICAL_PLAYER_FIX: V39 baseline + exact server popup isolation + real subtitle background/opacity.",
    "// V39R3_PLAYER_SMOOTHNESS: fast source-owned server switching, bounded failover, de-duplicated panel scans.\n"
    "// V39R_SURGICAL_PLAYER_FIX: V39 baseline + exact server popup isolation + real subtitle background/opacity.",
    "marker",
)

s = replace_once(
    s,
    """    @Published var errorMessage: String?

    weak var webView""",
    """    @Published var errorMessage: String?
    @Published var serverSwitching = false
    private var serverSwitchTimeout: Task<Void, Never>?

    weak var webView""",
    "server state declarations",
)

s = replace_once(
    s,
    """        errorMessage = nil
    }

    func togglePlayback""",
    """        errorMessage = nil
        serverSwitchTimeout?.cancel()
        serverSwitching = false
    }

    func togglePlayback""",
    "server state reset",
)

s = replace_once(
    s,
    """    func selectServer(_ server: XSServerOption) {
        clearSubtitleRequest()
        subtitleFrameID = nil
        subtitleGeneration = -1
        subtitleOptions = []
        selectedSubtitleID = nil
        captionText = ""
        subtitleScanFinished = false
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
""",
    """    func selectServer(_ server: XSServerOption) {
        clearSubtitleRequest()
        subtitleFrameID = nil
        subtitleGeneration = -1
        subtitleOptions = []
        selectedSubtitleID = nil
        captionText = ""
        subtitleScanFinished = false
        activeServerName = server.name
        if !server.quality.isEmpty { activeQuality = server.quality }
        errorMessage = nil
        isReady = false
        serverSwitchTimeout?.cancel()
        serverSwitching = true
        serverSwitchTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard !Task.isCancelled, let self, self.serverSwitching else { return }
            self.serverSwitching = false
            self.isReady = true
            self.errorMessage = "This server did not respond. Try another server."
        }
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }
""",
    "server selection state",
)

s = replace_once(
    s,
    """        case "xs:ready":
            isReady = true
            errorMessage = nil

        case "xs:error":
            errorMessage = payload["message"] as? String ?? "Playback unavailable"
""",
    """        case "xs:ready":
            isReady = true
            errorMessage = nil

        case "xs:serverSwitching":
            serverSwitching = true
            errorMessage = nil

        case "xs:serverReady":
            serverSwitchTimeout?.cancel()
            serverSwitching = false
            isReady = true
            errorMessage = nil
            if let name = payload["name"] as? String, !name.isEmpty { activeServerName = name }

        case "xs:serverFailover":
            serverSwitching = true
            isReady = false
            if let name = payload["name"] as? String, !name.isEmpty { activeServerName = name }
            errorMessage = "Trying another server…"

        case "xs:serverFailed":
            serverSwitchTimeout?.cancel()
            serverSwitching = false
            isReady = true
            errorMessage = payload["message"] as? String ?? "This server is unavailable."

        case "xs:error":
            errorMessage = payload["message"] as? String ?? "Playback unavailable"
""",
    "server event handling",
)

# The V39R2 bridge retained call sites from the source adapter but not their
# helpers. Define one narrow source-popup implementation and use it for both
# manual selection and automatic recovery.
helper_block = r'''      let xsV39ServerChoices = [];
      let xsV39ServerKey = 'auto';
      let xsV39ServerProvider = 'auto';
      let xsV39ServerSwitching = false;
      let xsV39ServerWatchToken = 0;
      let xsV39ServerWatchTimer = null;
      let xsV39ServerStartedAt = 0;
      let xsV39ServerBaselineTime = 0;
      let xsV39ServerBaselineSrc = '';
      let xsV39ServerHealthy = false;
      let xsV39TriedServerKeys = new Set();
      let xsV39FailoverAttempts = 0;

      function xsV39ServerChoiceKey(name, provider) {
        return String(provider || name || 'auto').trim().toLowerCase();
      }

      function xsV39ServerLabel(el) {
        if (!el) return '';
        return cleanText(el).replace(/[✓✔]/g, ' ').replace(/\s+/g, ' ').trim();
      }

      function xsV39OpenServerMenu() {
        if (xsV39ServerPanel()) return true;
        const nodes = Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"]'));
        const found = nodes.find(el => {
          if (el.closest('video,iframe')) return false;
          const text = xsV39ServerLabel(el);
          return /select\s+server|server|provider|source/i.test(text) &&
            !/subtitle|caption|closed\s*caption|\bcc\b/i.test(text);
        });
        if (!found) return false;
        try { found.click(); return true; } catch (_) { return false; }
      }

      function openServerMenu() { return xsV39OpenServerMenu(); }

      function selectByText(name) {
        const wanted = String(name || '').trim().toLowerCase();
        if (!wanted) return false;
        const root = xsV39ServerPanel();
        const scope = root || document;
        const nodes = Array.from(scope.querySelectorAll('button,[role="button"],[role="menuitem"]'));
        const found = nodes.find(el => {
          const text = xsV39ServerLabel(el).toLowerCase();
          if (!text || /subtitle|caption|closed\s*caption|\bcc\b/i.test(text)) return false;
          return text === wanted || text.startsWith(wanted + ' ') || text.includes(wanted);
        });
        if (!found) return false;
        try { found.click(); return true; } catch (_) { return false; }
      }

      function openAndScanServers() {
        xsV39OpenServerMenu();
        setTimeout(scanServers, 80);
        setTimeout(scanServers, 260);
        setTimeout(scanServers, 620);
      }

      function openAndScanSubtitles() {
        sourceSubtitles.scan();
        setTimeout(() => sourceSubtitles.publish(false), 0);
        setTimeout(() => sourceSubtitles.publish(true), 220);
      }

      function xsV39BeginServerWatch(name, provider) {
        if (xsV39ServerWatchTimer) clearTimeout(xsV39ServerWatchTimer);
        xsV39ServerSwitching = true;
        xsV39ServerHealthy = false;
        xsV39ServerStartedAt = Date.now();
        xsV39ServerKey = xsV39ServerChoiceKey(name, provider);
        xsV39ServerProvider = String(provider || 'auto');
        xsV39TriedServerKeys.add(xsV39ServerKey);
        const v = video || findVideo();
        xsV39ServerBaselineTime = v ? Number(v.currentTime || 0) : 0;
        xsV39ServerBaselineSrc = v ? String(v.currentSrc || v.src || '') : '';
        bridge({event:'xs:serverSwitching', name:String(name || 'Auto'), provider:xsV39ServerProvider});
        const token = ++xsV39ServerWatchToken;
        xsV39ServerWatchTimer = setTimeout(() => {
          if (token === xsV39ServerWatchToken && xsV39ServerSwitching && !xsV39ServerHealthy) {
            xsV39Failover('timeout');
          }
        }, 8500);
      }

      function xsV39ServerHealthySignal(reason) {
        if (!xsV39ServerSwitching || xsV39ServerHealthy) return;
        const elapsed = Date.now() - xsV39ServerStartedAt;
        if (elapsed < 1200) return;
        const v = video || findVideo();
        if (!v) return;
        const currentTime = Number(v.currentTime || 0);
        const currentSrc = String(v.currentSrc || v.src || '');
        const moved = currentTime > xsV39ServerBaselineTime + 0.75;
        const changedSource = !!currentSrc && currentSrc !== xsV39ServerBaselineSrc;
        if (Number(v.readyState || 0) < 2) return;
        // A paused player has no timeupdate signal; once the source has had
        // time to settle, keep the user's paused state instead of cycling
        // through healthy servers just because playback is not moving.
        if (!moved && !changedSource && !v.paused && reason !== 'playing') return;
        xsV39ServerHealthy = true;
        xsV39ServerSwitching = false;
        if (xsV39ServerWatchTimer) clearTimeout(xsV39ServerWatchTimer);
        bridge({event:'xs:serverReady', name:xsV39ServerKey, provider:xsV39ServerProvider});
      }

      function xsV39Failover(reason) {
        if (!xsV39ServerSwitching || xsV39ServerHealthy) return;
        if (xsV39FailoverAttempts >= 3) {
          xsV39ServerSwitching = false;
          bridge({event:'xs:serverFailed', name:xsV39ServerKey,
            message:'This server is unavailable. Try another server.', reason:String(reason || 'unavailable')});
          return;
        }
        const next = xsV39ServerChoices.find(row => {
          const key = xsV39ServerChoiceKey(row.name, row.provider);
          return !xsV39TriedServerKeys.has(key);
        });
        if (!next) {
          xsV39FailoverAttempts += 1;
          xsV39OpenServerMenu();
          setTimeout(() => {
            scanServers();
            setTimeout(() => xsV39Failover(reason), 360);
          }, 120);
          return;
        }
        xsV39FailoverAttempts += 1;
        const nextKey = xsV39ServerChoiceKey(next.name, next.provider);
        xsV39TriedServerKeys.add(nextKey);
        bridge({event:'xs:serverFailover', name:next.name, provider:next.provider || 'auto', reason:String(reason || 'unavailable')});
        sourceSubtitles.reset();
        xsV39OpenServerMenu();
        setTimeout(() => {
          const clicked = selectByText(next.name);
          if (next.provider) {
            try { window.postMessage({action:'setProvider',provider:next.provider}, '*'); } catch (_) {}
          }
          hideSourcePanels();
          xsV39BeginServerWatch(next.name, next.provider || 'auto');
          if (!clicked && !next.provider) scanServers();
        }, 140);
      }

      function xsV39HandleServerSignal(reason) {
        if (!xsV39ServerSwitching || xsV39ServerHealthy) return;
        if (Date.now() - xsV39ServerStartedAt >= 2200) xsV39Failover(reason);
      }

'''
# Place state before the helper functions; function declarations are hoisted.
s = replace_once(
    s,
    "      function xsV39ServerMeta(el) {",
    helper_block + "      function xsV39ServerMeta(el) {",
    "server switching helpers",
)

s = replace_once(
    s,
    "        if (out.length) bridge({event:'xs:servers',items:out});",
    """        xsV39ServerChoices.splice(0, xsV39ServerChoices.length, ...out);
        if (out.length) bridge({event:'xs:servers',items:out});""",
    "server choice cache",
)

s = replace_once(
    s,
    """        ['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ratechange','ended','canplay'].forEach(name => {
          try { v.addEventListener(name,reportState,{passive:true}); } catch (_) {}
        });""",
    """        ['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ratechange','ended','canplay'].forEach(name => {
          try { v.addEventListener(name,reportState,{passive:true}); } catch (_) {}
        });
        ['timeupdate','playing','canplay','canplaythrough','progress','loadedmetadata'].forEach(name => {
          try { v.addEventListener(name,() => xsV39ServerHealthySignal(name),{passive:true}); } catch (_) {}
        });
        ['waiting','stalled','error','emptied','abort'].forEach(name => {
          try { v.addEventListener(name,() => xsV39HandleServerSignal(name),{passive:true}); } catch (_) {}
        });""",
    "server health listeners",
)

s = replace_once(
    s,
    """          else if (action === 'subtitleStyle') {
            subtitleStyle={size:Number(payload.size||1),color:String(payload.color||'#ffffff'),background:!!payload.background,bottom:Number(payload.bottom||76)};
            applySubtitleStyle();
          }""",
    """          else if (action === 'subtitleStyle') {
            subtitleStyle={
              size:Number(payload.size || 1),
              color:String(payload.color || '#ffffff'),
              background:payload.background !== false,
              backgroundStyle:String(payload.backgroundStyle || (payload.background === false ? 'none' : 'black')),
              backgroundOpacity:Math.max(0,Math.min(1,Number(payload.backgroundOpacity == null ? 0.68 : payload.backgroundOpacity))),
              bottom:Number(payload.bottom || 76)
            };
            applySubtitleStyle();
          }""",
    "full subtitle style command",
)

s = replace_once(
    s,
    """          else if (action === 'serverMenu') {
            openServerMenu();
            setTimeout(scanServers, 120);
            setTimeout(scanServers, 320);
            setTimeout(scanServers, 700);
          }""",
    """          else if (action === 'serverMenu') {
            openAndScanServers();
          }""",
    "server menu command",
)

server_start = s.index("          else if (action === 'server') {")
server_end = s.index("\n          else if (action === 'metadata')", server_start)
server_block = r'''          else if (action === 'server') {
            sourceSubtitles.reset();
            const name = String(payload.name || 'Auto').trim() || 'Auto';
            const provider = String(payload.provider || (name.toLowerCase() === 'auto' ? 'auto' : '')).trim();
            xsV39ServerSwitching = false;
            xsV39ServerHealthy = false;
            if (xsV39ServerWatchTimer) clearTimeout(xsV39ServerWatchTimer);
            xsV39TriedServerKeys = new Set();
            xsV39FailoverAttempts = 0;
            const trySelect = (attempt) => {
              const clicked = selectByText(name) || (name.toLowerCase() === 'auto' && selectByText('Auto'));
              if (!clicked) xsV39OpenServerMenu();
              setTimeout(() => {
                const selected = clicked || selectByText(name) || (name.toLowerCase() === 'auto' && selectByText('Auto'));
                if (provider) {
                  try { window.postMessage({action:'setProvider',provider:provider}, '*'); } catch (_) {}
                }
                hideSourcePanels();
                if (selected || provider || name.toLowerCase() === 'auto') {
                  xsV39BeginServerWatch(name, provider || 'auto');
                  scanServers();
                } else if (attempt < 2) {
                  xsV39OpenServerMenu();
                  setTimeout(() => trySelect(attempt + 1), 120);
                } else {
                  bridge({event:'xs:serverFailed',name:name,
                    message:'This server could not be selected.'});
                }
              }, 140);
            };
            xsV39OpenServerMenu();
            setTimeout(() => trySelect(0), 80);
          }'''
s = s[:server_start] + server_block + s[server_end:]

s = replace_once(
    s,
    """          else if (action === 'quality') {
            openServerMenu();
            setTimeout(() => selectByText(String(payload.name || '')),120);
          }""",
    """          else if (action === 'quality') {
            xsV39OpenServerMenu();
            setTimeout(() => selectByText(String(payload.name || '')),120);
          }""",
    "quality command helper",
)

s = replace_once(
    s,
    """    private func openPanel(_ newPanel: XSPlayerPanel) {
        holdControls()
        withAnimation(.easeInOut(duration: 0.18)) { panel = newPanel }
        if newPanel == .subtitles { player.requestSubtitleMenu() }
        if newPanel == .quality { player.requestQualityMenu(); player.requestMetadata() }
        if newPanel == .audio { player.requestAudioMenu() }
    }""",
    """    private func openPanel(_ newPanel: XSPlayerPanel) {
        holdControls()
        withAnimation(.easeInOut(duration: 0.18)) { panel = newPanel }
    }""",
    "duplicate panel requests",
)

s = replace_once(
    s,
    """    private func pushSubtitleStyle() {
        player.setSubtitleStyle(
            size: subtitleScale,
            color: subtitleColor,
            backgroundStyle: subtitleBackgroundStyle,
            backgroundOpacity: subtitleBackgroundOpacity,
            bottom: subtitleBottom
        )
    }""",
    """    private func pushSubtitleStyle() {
        player.setSubtitleStyle(
            size: subtitleScale,
            color: subtitleColor,
            backgroundStyle: subtitleBackground ? subtitleBackgroundStyle : "none",
            backgroundOpacity: subtitleBackgroundOpacity,
            bottom: subtitleBottom
        )
    }""",
    "effective subtitle background push",
)

s = replace_once(
    s,
    """    private var subtitleBackgroundColor: Color {
        switch subtitleBackgroundStyle {
        case "white": return .white
        case "gray": return Color(white: 0.19)
        default: return .black
        }
    }

    private func captionOverlay(width: CGFloat) -> some View {""",
    """    private var effectiveSubtitleBackgroundStyle: String {
        subtitleBackground ? subtitleBackgroundStyle : "none"
    }

    private var subtitleBackgroundColor: Color {
        switch effectiveSubtitleBackgroundStyle {
        case "white": return .white
        case "gray": return Color(white: 0.19)
        default: return .black
        }
    }

    private func captionOverlay(width: CGFloat) -> some View {""",
    "effective subtitle background state",
)

s = s.replace("subtitleBackgroundStyle == \"none\"", "effectiveSubtitleBackgroundStyle == \"none\"")

s = replace_once(
    s,
        """        .onAppear {
            installProgressHandler()
            player.setSubtitleDelay(subtitleDelay)
            pushSubtitleStyle()
            controlsVisible = true
            scheduleHide()
            Task { await resolveNextEpisode() }
        }""",
        """        .onAppear {
            installProgressHandler()
            if !subtitleBackground { subtitleBackgroundStyle = "none" }
            player.setSubtitleDelay(subtitleDelay)
            pushSubtitleStyle()
            controlsVisible = true
            scheduleHide()
            Task { await resolveNextEpisode() }
        }""",
    "subtitle background migration",
)

PLAYER.write_text(s, encoding="utf-8")
print("V39R3 smoothness patch applied")

