"""Apply after the V11 playback baseline; replace subtitle interception entirely."""
from pathlib import Path

p = Path('FrameNative/FrameXTVPlayerV6.swift')
s = p.read_text()

def replace(old, new):
    global s
    if old not in s:
        raise SystemExit('V24 expected source marker missing: ' + old[:100])
    s = s.replace(old, new, 1)

def section(start, end, new):
    global s
    a = s.index(start)
    b = s.index(end, a)
    s = s[:a] + new + s[b:]

# FrameXTV conditionally unmounts its entire CC toolbar for controls=0.
# Keep it mounted; the adapter hides ONLY its visual chrome with CSS.
replace('.init(name: "controls", value: "0")', '.init(name: "controls", value: "1")')
replace('    let sourceIndex: Int?\n', '    let frameID: String\n    let sourceIndex: Int?\n')
replace('    @Published var subtitleScanFinished = false\n', '''    @Published var subtitleScanFinished = false
    @Published var pendingSubtitleID: String?
    @Published var subtitleSelectionError: String?
    private var subtitleRequestID: String?
    private var subtitleFrameID: String?
    private var subtitleGeneration: Int = -1
    private var subtitleTimeout: Task<Void, Never>?
    private var subtitleScanTimeout: Task<Void, Never>?
''')
replace('''    func requestSubtitleMenu() {
        subtitleScanFinished = false
        send(["action": "subtitleMenu"])
    }''', '''    func requestSubtitleMenu() {
        subtitleScanTimeout?.cancel()
        subtitleScanFinished = false
        send(["action": "subtitleMenu"])
        subtitleScanTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.subtitleScanFinished = true
        }
    }''')
replace('        subtitleOptions = []\n        selectedSubtitleID = nil\n', '''        subtitleOptions = []
        selectedSubtitleID = nil
        clearSubtitleRequest()
        subtitleFrameID = nil
        subtitleGeneration = -1
''')
section('    func selectSubtitle(_ option: XSSubtitleOption?) {', '\n    func selectServer', '''    private func clearSubtitleRequest() {
        subtitleTimeout?.cancel()
        subtitleRequestID = nil
        pendingSubtitleID = nil
        subtitleSelectionError = nil
    }

    func selectSubtitle(_ option: XSSubtitleOption?) {
        guard let frameID = option?.frameID ?? subtitleFrameID else {
            subtitleSelectionError = "Open Subtitles again after playback starts."
            return
        }
        subtitleTimeout?.cancel()
        let requestID = UUID().uuidString
        subtitleRequestID = requestID
        subtitleSelectionError = nil
        pendingSubtitleID = option?.id ?? "off"
        send(["action": "subtitle", "id": option?.id ?? "off",
              "frameID": frameID, "requestID": requestID])
        subtitleTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 22_000_000_000)
            guard !Task.isCancelled, let self, self.subtitleRequestID == requestID else { return }
            self.subtitleSelectionError = "The source did not confirm this subtitle. Try again."
            self.subtitleRequestID = nil
            self.pendingSubtitleID = nil
        }
    }
''')
replace('    func selectServer(_ server: XSServerOption) {\n', '''    func selectServer(_ server: XSServerOption) {
        clearSubtitleRequest()
        subtitleFrameID = nil
        subtitleGeneration = -1
''')
section('        case "xs:caption":', '\n        case "xs:servers":', '''        case "xs:caption":
            guard payload["frameID"] as? String == subtitleFrameID else { return }
            captionText = payload["text"] as? String ?? ""

        case "xs:subtitleSelected", "xs:subtitleSelectionFailed":
            guard let requestID = payload["requestID"] as? String,
                  requestID == subtitleRequestID,
                  payload["frameID"] as? String == subtitleFrameID else { return }
            subtitleTimeout?.cancel()
            subtitleRequestID = nil
            if event == "xs:subtitleSelected" {
                let id = payload["id"] as? String
                selectedSubtitleID = id == "off" ? nil : id
                subtitleSelectionError = nil
            } else {
                selectedSubtitleID = nil
                subtitleSelectionError = payload["message"] as? String ?? "This subtitle could not be loaded."
                captionText = ""
            }
            pendingSubtitleID = nil

        case "xs:subtitles":
            guard let frameID = payload["frameID"] as? String,
                  let generation = intValue(payload["generation"]),
                  let rows = payload["items"] as? [[String: Any]] else { return }
            if let owner = subtitleFrameID, owner != frameID { return }
            guard generation >= subtitleGeneration else { return }
            if generation > subtitleGeneration {
                clearSubtitleRequest()
                selectedSubtitleID = nil
                captionText = ""
            }
            subtitleFrameID = frameID
            subtitleGeneration = generation
            subtitleScanFinished = payload["final"] as? Bool ?? false
            if subtitleScanFinished { subtitleScanTimeout?.cancel() }
            subtitleOptions = rows.compactMap { row -> XSSubtitleOption? in
                guard let id = row["id"] as? String,
                      let label = row["label"] as? String, !label.isEmpty else { return nil }
                return .init(id: id, frameID: frameID, sourceIndex: nil, label: label,
                             language: row["language"] as? String ?? "", source: "source-menu")
            }
''')

# Keep the existing browser/player transport; route the envelope through child
# frames only, and let the unique owner consume subtitle selection requests.
replace("          try{engine.contentWindow.postMessage(payload,'*')}catch(_){ }", '')
replace("          if (event.data && event.data.__xsCommand) command(event.data.__xsCommand);", '''          if (event.source === window.parent && event.data && event.data.__xsCommand) {
            command(event.data.__xsCommand);
            Array.from(document.querySelectorAll('iframe')).forEach(frame => {
              try { frame.contentWindow.postMessage(event.data, '*'); } catch (_) {}
            });
          }''')

adapter = Path('scripts/xs_source_subtitles.js').read_text()
section('      let networkSubtitleItems = [];', '\n      function parseServerRow', adapter + '''
      const sourceSubtitles = createXSSourceSubtitles({document, window, findVideo, emit: bridge});
      function scanSubtitles(finalPass) { sourceSubtitles.publish(!!finalPass); }
''')
section('      function hideSourcePanels() {', '\n      function hideChrome()', '''      function hideSourcePanels() { sourceSubtitles.hidePanels(); }
''')
section('      function openSubtitleMenu() {', '\n      function selectByText', '''      function openSubtitleMenu() { sourceSubtitles.scan(); }
''')
section('      function openAndScanSubtitles() {', '\n      function install(v)', '''      function openAndScanSubtitles() { sourceSubtitles.scan(); }
      function reportCaption() { sourceSubtitles.tick(); }
      function applySubtitleStyle() { sourceSubtitles.setStyle(subtitleStyle); }
''')
section("          else if (action === 'subtitle') {", "\n          else if (action === 'server') {", '''          else if (action === 'subtitle') { sourceSubtitles.select(payload); }
''')
replace("          else if (action === 'subtitleDelay') subtitleDelay = Number(payload.seconds || 0);", "          else if (action === 'subtitleDelay') { subtitleDelay = Number(payload.seconds || 0); sourceSubtitles.setDelay(subtitleDelay); }")
replace("          else if (action === 'server') {", "          else if (action === 'server') {\n            sourceSubtitles.reset();")

# DocumentStart can precede documentElement/body. Never abort bridge setup there.
section('      installSubtitleNetworkObserver();', '\n      setInterval', '''      function observeDocument() {
        if (!document.documentElement) return;
        new MutationObserver(() => {
          const v = findVideo();
          if (v) install(v);
          if (v) hideChrome();
          hideSourcePanels();
        }).observe(document.documentElement, {subtree:true,childList:true});
        const v = findVideo();
        if (v) install(v);
      }
      if (document.documentElement) observeDocument();
      else document.addEventListener('DOMContentLoaded', observeDocument, {once:true});
      window.addEventListener('pagehide', () => sourceSubtitles.dispose(), {once:true});
''')

replace('        .onChange(of: player.currentTime)', '''        .onChange(of: player.pendingSubtitleID) { pending in
            if pending == nil && player.subtitleSelectionError == nil && panel == .subtitles { closePanel() }
        }
        .onChange(of: player.currentTime)''')
replace('panelRow(title: "Off", detail: player.selectedSubtitleID == nil ? "Selected" : nil)', 'panelRow(title: "Off", detail: player.pendingSubtitleID == "off" ? "Loading…" : (player.selectedSubtitleID == nil ? "Selected" : nil))')
replace('                    player.selectSubtitle(nil)\n                    closePanel()', '                    player.selectSubtitle(nil)\n                    holdControls()')
replace('detail: player.selectedSubtitleID == option.id ? "Selected" : languageDetail(option)', 'detail: player.pendingSubtitleID == option.id ? "Loading…" : (player.selectedSubtitleID == option.id ? "Selected" : languageDetail(option))')
replace('                            player.selectSubtitle(option)\n                            closePanel()', '                            player.selectSubtitle(option)\n                            holdControls()')
replace('                if player.subtitleOptions.isEmpty {', '''                if let message = player.subtitleSelectionError {
                    Text(message).font(.footnote).foregroundStyle(.orange).padding(.vertical, 6)
                }
                if player.subtitleOptions.isEmpty {''')
p.write_text(s)
print('Applied V24: source CC menu, owner-scoped selection, cue-load acknowledgement')
