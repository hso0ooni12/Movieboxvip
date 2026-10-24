import SwiftUI
import WebKit
import AVFoundation
import UniformTypeIdentifiers

// The catalog is 100% SwiftUI. Some streaming providers only publish an
// interactive embed, not an authorized, stable HLS/MP4 URL. Those titles use a
// confined in-app WebKit playback surface; direct streams still use VLC.
struct EmbeddedSelection: Identifiable {
    let id = UUID()
    let title: String
    let mediaID: String
    let kind: MediaKind
    let season: Int
    let episode: Int

    var servers: [EmbeddedServer] {
        let rawID = mediaID.replacingOccurrences(of: "tmdb:", with: "")
        let safeID = rawID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? rawID
        let path = kind == .movie
            ? "movie/\(safeID)"
            : "tv/\(safeID)/\(max(1, season))/\(max(1, episode))"
        let vidSrc = "https://embed.vidsrc.pk/\(path)"
        let vidLink = "https://vidlink.pro/\(path)"

        let auto = EmbeddedServer(id: "auto", title: "تلقائي", subtitle: "VidSrc · اختيار ذكي", url: URL(string: vidSrc)!)
        let mirror = EmbeddedServer(id: "mirror", title: "سيرفر بديل", subtitle: "VidSrc · NetMirror", url: URL(string: vidSrc + "?p=netmirror")!)
        let primary = EmbeddedServer(id: "primary", title: "السيرفر الأساسي", subtitle: "VidSrc · Primary", url: URL(string: vidSrc + "?p=primary")!)
        let link = EmbeddedServer(id: "vidlink", title: "VidLink", subtitle: "مشغّل احتياطي", url: URL(string: vidLink)!)
        // NetMirror was observed playing both movies and a TV episode; keep
        // automatic discovery and primary as one-tap fallbacks.
        return [mirror, link, auto, primary]
    }
}

struct EmbeddedServer: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let url: URL
}

struct EmbeddedSubtitleTrack: Identifiable, Equatable {
    let id: String
    let label: String
}

@MainActor
final class EmbeddedPlayerModel: ObservableObject {
    let selection: EmbeddedSelection
    let servers: [EmbeddedServer]
    @Published var sourceIndex = 0
    @Published var pageLoaded = false
    var playing = false
    @Published var playbackError: String?
    var currentTime: Double = 0
    @Published var captionText = ""
    @Published var captionFileName: String?
    @Published var captionDelay: Double = 0
    @Published var captionSize: CGFloat = 22
    @Published var captionBottom: CGFloat = 10
    @Published var captionOpacity: Double = 0.5
    @Published var availableSubtitles: [EmbeddedSubtitleTrack] = []
    @Published var selectedSubtitleLanguage: String? = nil
    @Published var subtitleStatus: String? = nil

    weak var webView: WKWebView?
    private var monitorTask: Task<Void, Never>?
    private var cues: [CaptionCue] = []
    private var serverCues: [CaptionCue] = []
    private var serverCueKey: String?
    private var subtitleFetchAttempts = Set<String>()
    private var subtitleFetchTask: Task<Void, Never>?
    private var browserCaption = ""
    private var browserCaptionLanguage = ""
    private var captionFrame: WKFrameInfo?
    private var captionFrameID: String?
    private var captionFrameLastSeen = Date.distantPast
    private var failedSources = Set<Int>()
    private var fallbackTask: Task<Void, Never>?
    private var sourceOpenedAt = Date()
    private var hasPlayedOnThisSource = false

    init(selection: EmbeddedSelection) {
        self.selection = selection
        self.servers = selection.servers
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    func switchTo(_ index: Int, automatically: Bool = false) {
        guard servers.indices.contains(index), index != sourceIndex else { return }
        fallbackTask?.cancel()
        fallbackTask = nil
        if !automatically { failedSources.removeAll() }
        sourceOpenedAt = Date()
        hasPlayedOnThisSource = false
        monitorTask?.cancel()
        subtitleFetchTask?.cancel()
        webView?.stopLoading()
        webView = nil
        sourceIndex = index
        pageLoaded = false
        playing = false
        playbackError = nil
        currentTime = 0
        captionText = ""
        browserCaption = ""
        browserCaptionLanguage = ""
        captionFrame = nil
        captionFrameID = nil
        captionFrameLastSeen = .distantPast
        serverCues = []
        serverCueKey = nil
        subtitleFetchAttempts = []
        availableSubtitles = []
        subtitleStatus = nil
    }

    func nextSource() { switchTo((sourceIndex + 1) % servers.count) }

    func attach(_ view: WKWebView) {
        webView = view
        monitorTask?.cancel()
        monitorTask = Task { [weak self, weak view] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self, let view, self.webView === view else { break }
                // Always check the top document for a source error. A healthy
                // subtitle iframe must not disable playback failure detection.
                await self.inspect(view)
                if !self.hasPlayedOnThisSource && !self.playing
                    && self.playbackError == nil
                    && Date().timeIntervalSince(self.sourceOpenedAt) > 25 {
                    self.reportPlaybackFailure("انتهت مهلة تحميل السيرفر، جارٍ تجربة بديل.")
                }
            }
        }
    }

    func loaded() { pageLoaded = true }

    // The actual HTML video frequently lives in a cross-origin iframe. Running
    // JavaScript only in the top document misses its subtitle tracks entirely.
    // Receive read-only caption probes from the user script installed in all
    // frames, then select the active video frame for native caption rendering.
    func receiveCaptionProbe(_ data: [String: Any], frame: WKFrameInfo, from webView: WKWebView) {
        guard self.webView === webView,
              let id = data["frameID"] as? String,
              !id.isEmpty else { return }
        if let failure = data["failure"] as? String, !failure.isEmpty {
            if !playing {
                reportPlaybackFailure("هذا السيرفر لم يوفر بثًا لهذا العنوان.")
            }
            return
        }
        let time = (data["t"] as? NSNumber)?.doubleValue ?? 0
        let ready = (data["ready"] as? NSNumber)?.intValue ?? 0
        let paused = data["paused"] as? Bool ?? true
        if let oldID = captionFrameID, oldID != id {
            // Prefer the established playing video; allow a fresh video to
            // replace an inactive frame after a navigation or source change.
            if Date().timeIntervalSince(captionFrameLastSeen) < 2 && playing {
                return
            }
            guard (ready >= 2 && !paused) || Date().timeIntervalSince(captionFrameLastSeen) > 3 else {
                return
            }
        }
        let changedFrame = captionFrameID != id
        captionFrame = frame
        captionFrameID = id
        captionFrameLastSeen = Date()
        pageLoaded = true
        let trackData = data["tracks"] as? [[String: Any]] ?? []
        let freshTracks = trackData.compactMap { info -> EmbeddedSubtitleTrack? in
            guard let lang = info["lang"] as? String, !lang.isEmpty else { return nil }
            return EmbeddedSubtitleTrack(id: lang, label: info["label"] as? String ?? lang)
        }
        if freshTracks != availableSubtitles { availableSubtitles = freshTracks }
        currentTime = max(0, time)
        playing = ready >= 2 && !paused
        if playing {
            hasPlayedOnThisSource = true
            playbackError = nil
        }
        browserCaption = data["caption"] as? String ?? ""
        browserCaptionLanguage = data["language"] as? String ?? ""
        let cueCount = (data["cueCount"] as? NSNumber)?.intValue ?? 0
        if changedFrame { applyCaptionPreferences() }
        if let selected = effectiveSubtitleLanguage,
           selected == browserCaptionLanguage,
           cueCount == 0,
           data["hasTrackSource"] as? Bool == true {
            fetchProviderSubtitle(selected, from: webView)
        } else if cueCount > 0,
                  selectedSubtitleLanguage != nil,
                  selectedSubtitleLanguage == browserCaptionLanguage,
                  serverCues.isEmpty {
            subtitleStatus = "ترجمة السيرفر جاهزة"
        }
        updateCaption()
    }

    private func applyCaptionPreferences() {
        guard let view = webView, let frame = captionFrame else { return }
        let language = selectedSubtitleLanguage ?? ""
        let offset = captionDelay
        Task { [weak self, weak view] in
            guard let view, self?.webView === view else { return }
            _ = try? await view.callAsyncJavaScript(
                "window.__gemflixCaptionLanguage = String(language || ''); window.__gemflixCaptionOffset = Number(offset || 0); return true;",
                arguments: ["language": language, "offset": offset],
                in: frame,
                contentWorld: .page
            )
        }
    }

    func failed(_ message: String) {
        reportPlaybackFailure(message)
    }

    private func reportPlaybackFailure(_ message: String) {
        guard !playing else { return }
        pageLoaded = true
        playbackError = message
        tryAutomaticFallback()
    }

    private func inspect(_ view: WKWebView) async {
        let script = """
        const videos = Array.from(document.querySelectorAll('video'));
        const v = videos.find(x => x.readyState > 1) || videos[0];
        const tracks = v ? Array.from(v.textTracks || []) : [];
        const elements = v ? Array.from(v.querySelectorAll('track')) : [];
        const languageOf = (track, index) => String(track.language || elements[index]?.srclang || '').toLowerCase();
        const available = tracks.map((track, index) => ({
          lang: languageOf(track, index),
          label: String(track.label || elements[index]?.label || track.language || ('Track ' + (index + 1)))
        })).filter(track => track.lang)
           .filter((track, index, all) => all.findIndex(other => other.lang === track.lang) === index);
        const requested = String(requestedLanguage || '');
        if (requested === '__off') {
          tracks.forEach(track => { track.mode = 'disabled'; });
        } else if (requested) {
          tracks.forEach((track, index) => {
            track.mode = languageOf(track, index) === requested ? 'hidden' : 'disabled';
          });
        }
        let selectedIndex = tracks.findIndex(track => track.mode === 'showing');
        if (selectedIndex < 0) selectedIndex = tracks.findIndex(track => track.mode === 'hidden');
        const selected = selectedIndex >= 0 ? tracks[selectedIndex] : null;
        if (selected && selected.mode === 'showing') selected.mode = 'hidden';
        const language = selected ? languageOf(selected, selectedIndex) : '';
        const offsetTime = v ? Number(v.currentTime || 0) + Number(subtitleOffset || 0) : 0;
        const cues = selected && selected.cues ? selected.cues : null;
        let active = !Number(subtitleOffset || 0) && selected && selected.activeCues?.length
          ? selected.activeCues[0] : null;
        if (!active && cues && cues.length) {
          let low = 0, high = cues.length - 1;
          while (low <= high) {
            const mid = (low + high) >> 1;
            const cue = cues[mid];
            if (offsetTime < cue.startTime) high = mid - 1;
            else if (offsetTime >= cue.endTime) low = mid + 1;
            else { active = cue; break; }
          }
        }
        const caption = active ? String(active.text || '').replace(/<[^>]+>/g, '') : '';
        return {
          t: v ? Number(v.currentTime || 0) : 0,
          ready: v ? v.readyState : 0,
          paused: v ? v.paused : true,
          err: v && v.error ? v.error.code : 0,
          text: (document.body ? document.body.textContent : '').slice(0, 2500),
          tracks: available,
          language: language,
          caption: caption,
          cueCount: cues ? cues.length : 0,
          hasTrackSource: !!(selected && elements.some(el => String(el.srclang || '').toLowerCase() === language && el.src))
        };
        """
        let selectedLanguage = selectedSubtitleLanguage ?? ""
        let offset = captionDelay
        guard let data = try? await view.callAsyncJavaScript(
            script,
            arguments: ["requestedLanguage": selectedLanguage, "subtitleOffset": offset],
            in: nil,
            contentWorld: .page
        ) as? [String: Any],
              self.webView === view else { return }
        let time = (data["t"] as? NSNumber)?.doubleValue ?? 0
        let ready = (data["ready"] as? NSNumber)?.intValue ?? 0
        let paused = data["paused"] as? Bool ?? true
        let error = (data["err"] as? NSNumber)?.intValue ?? 0
        let body = (data["text"] as? String ?? "").lowercased()
        if error > 0 || body.contains("this title will not play") ||
             body.contains("no source returned a stream") {
            reportPlaybackFailure("السيرفر الحالي لم يرجع فيديو لهذا العنوان.")
            return
        }
        // A separate iframe supplies accurate tracks/cues: the top-level
        // document may have no video and must not erase those subtitles.
        if captionFrameID != nil && Date().timeIntervalSince(captionFrameLastSeen) < 2 { return }
        let trackData = data["tracks"] as? [[String: Any]] ?? []
        let freshTracks = trackData.compactMap { info -> EmbeddedSubtitleTrack? in
            guard let lang = info["lang"] as? String, !lang.isEmpty else { return nil }
            return EmbeddedSubtitleTrack(id: lang, label: info["label"] as? String ?? lang)
        }
        if freshTracks != availableSubtitles { availableSubtitles = freshTracks }
        browserCaption = data["caption"] as? String ?? ""
        browserCaptionLanguage = data["language"] as? String ?? ""
        let cueCount = (data["cueCount"] as? NSNumber)?.intValue ?? 0
        currentTime = max(0, time)
        if time > 0.2 && ready >= 2 {
            playing = !paused
            if playing {
                hasPlayedOnThisSource = true
                playbackError = nil
            }
        }
        if let selected = effectiveSubtitleLanguage,
           selected == browserCaptionLanguage,
           cueCount == 0,
           data["hasTrackSource"] as? Bool == true {
            fetchProviderSubtitle(selected, from: view)
        } else if cueCount > 0,
                  selectedSubtitleLanguage != nil,
                  selectedSubtitleLanguage == browserCaptionLanguage,
                  serverCues.isEmpty,
                  subtitleStatus != "ترجمة السيرفر جاهزة" {
            subtitleStatus = "ترجمة السيرفر جاهزة"
        }
        updateCaption()
    }

    private func tryAutomaticFallback() {
        let previousIndex = sourceIndex
        guard failedSources.insert(previousIndex).inserted else { return }
        // A genuinely separate provider is preferable to retrying variants
        // of a failed VidSrc page. Every source is tried at most once.
        let remaining = servers.indices.filter { !failedSources.contains($0) }
        let next = remaining.first {
            servers[$0].url.host != servers[previousIndex].url.host
        } ?? remaining.first
        guard let next else {
            playbackError = "لم نجد بثًا صالحًا لهذا العنوان لدى السيرفرات المتاحة. جرّب عنوانًا آخر."
            return
        }
        playbackError = "السيرفر لم يوفر بثًا. يجري الانتقال إلى \(servers[next].title)…"
        fallbackTask?.cancel()
        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self,
                  self.sourceIndex == previousIndex, !self.playing else { return }
            self.switchTo(next, automatically: true)
        }
    }

    private var effectiveSubtitleLanguage: String? {
        if selectedSubtitleLanguage == "__off" { return nil }
        if let selectedSubtitleLanguage { return selectedSubtitleLanguage }
        return browserCaptionLanguage.isEmpty ? nil : browserCaptionLanguage
    }

    func selectSubtitle(_ language: String?) {
        selectedSubtitleLanguage = language
        browserCaption = ""
        browserCaptionLanguage = ""
        captionText = ""
        if language == "__off" {
            subtitleStatus = "الترجمة متوقفة"
        } else if let language {
            subtitleFetchAttempts.remove("\(sourceIndex):\(language)")
            subtitleStatus = "جارٍ تحميل ترجمة \(availableSubtitles.first(where: { $0.id == language })?.label ?? language)…"
        } else {
            subtitleStatus = "متابعة اختيار المشغّل"
        }
        serverCues = []
        serverCueKey = nil
        applyCaptionPreferences()
        updateCaption()
    }

    // Some providers serve SRT tracks that WebKit exposes in video.textTracks
    // but does not decode. Read only the same-origin track chosen by the user;
    // render it with SwiftUI above the video instead of opening another page.
    private func fetchProviderSubtitle(_ language: String, from view: WKWebView) {
        let key = "\(sourceIndex):\(language)"
        guard subtitleFetchAttempts.insert(key).inserted else { return }
        subtitleFetchTask?.cancel()
        let source = sourceIndex
        subtitleFetchTask = Task { [weak self, weak view] in
            guard let self, let view else { return }
            let script = """
            const video = Array.from(document.querySelectorAll('video')).find(v => v.readyState > 1)
                          || document.querySelector('video');
            const tag = video ? Array.from(video.querySelectorAll('track')).find(
              track => String(track.srclang || '').toLowerCase() === String(language || '').toLowerCase()
            ) : null;
            if (!tag || !tag.src) return null;
            const controller = new AbortController();
            const timer = setTimeout(() => controller.abort(), 6500);
            try {
              const response = await fetch(tag.src, { credentials: 'same-origin', signal: controller.signal });
              if (!response.ok) return null;
              const content = await response.text();
              return content.length <= 1250000 ? content : null;
            } catch (_) {
              return null;
            } finally {
              clearTimeout(timer);
            }
            """
            let subtitle = try? await view.callAsyncJavaScript(
                script, arguments: ["language": language], in: self.captionFrame, contentWorld: .page
            ) as? String
            guard !Task.isCancelled, self.webView === view, self.sourceIndex == source,
                  self.effectiveSubtitleLanguage == language else { return }
            let parsed = subtitle.map(CaptionParser.parse) ?? []
            if !parsed.isEmpty {
                self.serverCueKey = key
                self.serverCues = parsed
                self.subtitleStatus = "تم تحميل الترجمة · \(parsed.count) سطر"
                self.updateCaption()
            } else if self.selectedSubtitleLanguage == language {
                self.subtitleStatus = "لم تُحمَّل ترجمة هذا السيرفر؛ جرّب سيرفرًا آخر"
            }
        }
    }

    func installCaptions(_ content: String, fileName: String) {
        cues = CaptionParser.parse(content)
        captionFileName = cues.isEmpty ? nil : fileName
        captionDelay = 0
        updateCaption()
    }

    func clearCaptions() {
        cues = []
        captionFileName = nil
        updateCaption()
    }

    func shiftCaptions(_ seconds: Double) {
        captionDelay += seconds
        applyCaptionPreferences()
        updateCaption()
    }

    private func updateCaption() {
        let target = currentTime + captionDelay
        let newText: String
        if !cues.isEmpty {
            newText = cues.first(where: { target >= $0.start && target < $0.end })?.text ?? ""
        } else if let selected = effectiveSubtitleLanguage,
                  serverCueKey == "\(sourceIndex):\(selected)",
                  !serverCues.isEmpty {
            newText = serverCues.first(where: { target >= $0.start && target < $0.end })?.text ?? ""
        } else if effectiveSubtitleLanguage == browserCaptionLanguage {
            newText = browserCaption
        } else {
            newText = ""
        }
        if captionText != newText { captionText = newText }
    }

    func stop() {
        fallbackTask?.cancel()
        monitorTask?.cancel()
        subtitleFetchTask?.cancel()
        webView?.stopLoading()
        webView?.loadHTMLString("", baseURL: nil)
        webView = nil
        captionFrame = nil
        captionFrameID = nil
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

private struct EmbeddedWebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var model: EmbeddedPlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let inlineScript = WKUserScript(source: """
          (function() {
            function keepInline() {
              document.querySelectorAll('video').forEach(function(video) {
                video.setAttribute('playsinline', '');
                video.setAttribute('webkit-playsinline', '');
              });
            }
            document.addEventListener('DOMContentLoaded', keepInline);
            keepInline();
            new MutationObserver(keepInline).observe(document, { childList: true, subtree: true });
          })();
          """, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(inlineScript)
        // Observe video textTracks in every frame, including cross-origin
        // player iframes. WKScriptMessage carries the originating WKFrameInfo.
        configuration.userContentController.add(context.coordinator, name: "gemflixCaption")
        let captionBridge = WKUserScript(source: """
          (function () {
            if (window.__gemflixCaptionBridge) return;
            window.__gemflixCaptionBridge = true;
            window.__gemflixCaptionLanguage = '';
            window.__gemflixCaptionOffset = 0;
            const frameID = String(Date.now()) + ':' + Math.random().toString(36).slice(2);
            function capture() {
              const allVideos = Array.from(document.querySelectorAll('video'));
              const video = allVideos.find(v => v.readyState >= 2 && !v.paused)
                       || allVideos.find(v => v.readyState >= 2) || allVideos[0];
              const pageText = String(document.body?.innerText || '').slice(0,3000);
              const failure = /this title will not play|no source returned a stream|something went wrong while finding a source/i.test(pageText);
              if (!video) {
                if (failure) {
                  try {
                    window.webkit.messageHandlers.gemflixCaption.postMessage({ frameID, failure:'no_stream' });
                  } catch (e) {}
                }
                return;
              }
              const tracks = Array.from(video.textTracks || []);
              const elements = Array.from(video.querySelectorAll('track'));
              const lang = (t, i) => String(t.language || elements[i]?.srclang ||
                 t.label || elements[i]?.label || '').toLowerCase().trim();
              const chosen = String(window.__gemflixCaptionLanguage || '').toLowerCase();
              if (chosen === '__off') {
                tracks.forEach(t => { t.mode = 'disabled'; });
              } else if (chosen) {
                tracks.forEach((t,i) => {
                  const key = lang(t,i);
                  const matched = key === chosen || key.startsWith(chosen + '-') ||
                      chosen.startsWith(key + '-');
                  t.mode = matched ? 'hidden' : 'disabled';
                });
              }
              let index = tracks.findIndex(t => t.mode === 'showing');
              if (index < 0) index = tracks.findIndex(t => t.mode === 'hidden');
              let selected = index >= 0 ? tracks[index] : null;
              if (selected && selected.mode === 'showing') selected.mode = 'hidden';
              const selectedLang = selected ? lang(selected,index) : '';
              const t = Number(video.currentTime || 0);
              const seekTime = t + Number(window.__gemflixCaptionOffset || 0);
              const cues = selected?.cues || null;
              let active = null;
              if (cues?.length) {
                let lo=0, hi=cues.length-1;
                while(lo<=hi) {
                  const mid=(lo+hi)>>1, cue=cues[mid];
                  if(seekTime<cue.startTime) hi=mid-1;
                  else if(seekTime>=cue.endTime) lo=mid+1;
                  else { active=cue; break; }
                }
              } else if (seekTime === t && selected?.activeCues?.length) {
                active = selected.activeCues[0];
              }
              const caption = active ? String(active.text || '').replace(/<[^>]+>/g,'') : '';
              const list = tracks.map((track,i) => ({
                lang: lang(track,i),
                label: String(track.label || elements[i]?.label || track.language || ('Track ' + (i+1)))
              })).filter(track => track.lang).filter((track,i,list) =>
                list.findIndex(other => other.lang === track.lang) === i);
              const hasTrackSource = !!(selected && elements.some(el =>
                lang(selected,index) === String(el.srclang || '').toLowerCase() && !!el.src));
              try {
                window.webkit.messageHandlers.gemflixCaption.postMessage({
                  frameID, failure: failure ? 'no_stream' : '',
                  t, ready:video.readyState, paused:video.paused,
                  language:selectedLang, caption:caption.slice(0,800),
                  cueCount:cues?.length || 0, hasTrackSource, tracks:list
                });
              } catch(e) {}
            }
            setInterval(capture, 400);
            capture();
          })();
          """, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        configuration.userContentController.addUserScript(captionBridge)

        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.backgroundColor = .black
        web.isOpaque = false
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsBackForwardNavigationGestures = false
        model.attach(web)
        web.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 24))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "gemflixCaption")
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let model: EmbeddedPlayerModel
        init(model: EmbeddedPlayerModel) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "gemflixCaption",
                  let info = message.body as? [String: Any],
                  let view = model.webView else { return }
            model.receiveCaptionProbe(info, frame: message.frameInfo, from: view)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard model.webView === webView else { return }
            model.loaded()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard model.webView === webView,
                  (error as NSError).code != NSURLErrorCancelled else { return }
            model.failed("تعذر الاتصال بالمشغّل. يمكنك تجربة سيرفر ثاني.")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Third-party embeds sometimes ask to open unrelated ad pages or
            // new browser windows. Playback must stay inside this app.
            if action.targetFrame == nil {
                decisionHandler(.cancel)
                return
            }
            guard action.targetFrame?.isMainFrame == true,
                  let destination = action.request.url else {
                decisionHandler(.allow)
                return
            }
            if destination.scheme == "about" || destination.scheme == "blob" {
                decisionHandler(.allow)
                return
            }
            let host = destination.host?.lowercased() ?? ""
            let trusted = ["embed.vidsrc.pk", "vidlink.pro", "www.vidlink.pro"]
            decisionHandler(destination.scheme == "https" && trusted.contains(host) ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
    }
}

struct EmbeddedPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: EmbeddedPlayerModel
    @State private var captionSheet = false
    @State private var fileImporter = false
    private let selection: EmbeddedSelection

    init(selection: EmbeddedSelection) {
        self.selection = selection
        _model = StateObject(wrappedValue: EmbeddedPlayerModel(selection: selection))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                EmbeddedWebView(url: model.servers[model.sourceIndex].url, model: model)
                    .id(model.servers[model.sourceIndex].id)
                    .ignoresSafeArea()

                if !model.captionText.isEmpty {
                    VStack {
                        Spacer()
                        Text(model.captionText)
                            .font(.system(size: model.captionSize, weight: .semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black, radius: 4)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(model.captionOpacity), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 30)
                            .padding(.bottom, max(1, model.captionBottom + geometry.safeAreaInsets.bottom))
                    }
                    .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    if let problem = model.playbackError {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text(problem).font(.system(size: 11, weight: .medium)).lineLimit(2)
                            Button("التالي") { model.nextSource() }
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CinemaPalette.accent)
                        }
                        .padding(12)
                        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 13))
                        .padding(.horizontal, 22)
                        .padding(.bottom, 12)
                    } else if !model.pageLoaded {
                        HStack(spacing: 9) {
                            ProgressView().tint(CinemaPalette.accent)
                            Text("جارٍ فتح المشغّل…")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.74), in: Capsule())
                        .padding(.bottom, 8)
                    }
                }
            }
            .foregroundStyle(.white)
        }
        .background(.black)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { PlayerOrientation.set(.landscape) }
        .onDisappear { model.stop(); PlayerOrientation.set(.portrait) }
        .sheet(isPresented: $captionSheet) { captionControls }
        .fileImporter(isPresented: $fileImporter, allowedContentTypes: [
            .plainText,
            UTType(filenameExtension: "srt") ?? .plainText,
            UTType(filenameExtension: "vtt") ?? .plainText
        ]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let content = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .utf16) else { return }
            model.installCaptions(content, fileName: url.lastPathComponent)
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            Button {
                model.stop()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.15), in: Circle())
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(selection.title)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(model.servers[model.sourceIndex].subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.70))
            }
            Spacer(minLength: 3)
            Menu {
                ForEach(Array(model.servers.enumerated()), id: \.offset) { index, source in
                    Button {
                        model.switchTo(index)
                    } label: {
                        if model.sourceIndex == index {
                            Label("\(source.title) · \(source.subtitle)", systemImage: "checkmark")
                        } else {
                            Text("\(source.title) · \(source.subtitle)")
                        }
                    }
                }
            } label: {
                Label("السيرفر", systemImage: "server.rack")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(.white.opacity(0.15), in: Capsule())
            }
            Button { captionSheet = true } label: {
                Image(systemName: "captions.bubble")
                    .font(.system(size: 17))
                    .frame(width: 39, height: 39)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("إعدادات الترجمة")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
        .background(LinearGradient(colors: [.black.opacity(0.90), .black.opacity(0.14)], startPoint: .top, endPoint: .bottom))
    }

    private var captionControls: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("الترجمة")
                            .font(.title3.bold())
                        Text("اختر اللغة هنا، وتظهر الترجمة فوق الفيديو حتى في وضع الشاشة الكاملة. تقدر تضبط التوقيت والشكل مباشرة.")
                            .font(.system(size: 12))
                            .foregroundStyle(CinemaPalette.secondary)
                    }
                    VStack(alignment: .leading, spacing: 11) {
                        Text("لغات السيرفر")
                            .font(.system(size: 14, weight: .semibold))
                        if model.availableSubtitles.isEmpty {
                            HStack(spacing: 9) {
                                ProgressView().tint(CinemaPalette.accent)
                                Text("بانتظار اكتشاف الترجمات من المشغّل…")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(CinemaPalette.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                Button {
                                    model.selectSubtitle("__off")
                                } label: {
                                    subtitleOption("إيقاف الترجمة", chosen: model.selectedSubtitleLanguage == "__off")
                                }
                                Button {
                                    model.selectSubtitle(nil)
                                } label: {
                                    subtitleOption("اختيار المشغّل", chosen: model.selectedSubtitleLanguage == nil)
                                }
                                ForEach(model.availableSubtitles) { track in
                                    Button {
                                        model.selectSubtitle(track.id)
                                    } label: {
                                        subtitleOption(track.label, chosen: model.selectedSubtitleLanguage == track.id)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        if let status = model.subtitleStatus {
                            Text(status)
                                .font(.system(size: 12))
                                .foregroundStyle(CinemaPalette.accent)
                        }
                    }
                    Divider()
                    Button { fileImporter = true } label: {
                        Label("إضافة ملف ترجمة SRT / VTT", systemImage: "doc.badge.plus")
                            .font(.system(size: 14, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 45)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CinemaPalette.accent)
                    if let name = model.captionFileName {
                        HStack {
                            Label(name, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(CinemaPalette.accent)
                            Spacer()
                            Button("إزالة") { model.clearCaptions() }
                        }
                    }
                    Divider()
                    Text("تزامن الترجمة · \(model.captionDelay.formatted(.number.precision(.fractionLength(1)))) ثانية")
                        .font(.system(size: 14, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 9) {
                        ForEach([-60.0, -10.0, -1.0, -0.5, 0.5, 1, 10, 60], id: \.self) { amount in
                            Button(amount > 0 ? "+\(amount.formatted())" : amount.formatted()) {
                                model.shiftCaptions(amount)
                            }
                            .font(.system(size: 11, weight: .bold))
                            .buttonStyle(.bordered)
                        }
                    }
                    Button("تصفير التوقيت") { model.shiftCaptions(-model.captionDelay) }
                        .font(.system(size: 12))
                        .foregroundStyle(CinemaPalette.accent)
                    Divider()
                    Text("حجم الترجمة · \(Int(model.captionSize)) pt")
                    Slider(value: $model.captionSize, in: 14...40, step: 1).tint(CinemaPalette.accent)
                    Text("موقع الترجمة · \(Int(model.captionBottom)) pt من الأسفل")
                    Slider(value: $model.captionBottom, in: 1...150, step: 1).tint(CinemaPalette.accent)
                    Text("خلفية الترجمة · \(Int(model.captionOpacity * 100))%")
                    Slider(value: $model.captionOpacity, in: 0...1).tint(CinemaPalette.accent)
                    Text("إذا ما ظهرت ترجمة السيرفر، جرّب اختيارها مرة ثانية أو اختر سيرفرًا ثانيًا. ملفات SRT وVTT الخارجية تأخذ الأولوية إذا أضفتها.")
                        .font(.system(size: 11))
                        .foregroundStyle(CinemaPalette.secondary)
                }
                .padding(21)
            }
            .background(CinemaPalette.base)
            .foregroundStyle(.white)
            .navigationTitle("الترجمة والشكل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("تم") { captionSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func subtitleOption(_ title: String, chosen: Bool) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.system(size: 12, weight: chosen ? .bold : .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
            if chosen { Image(systemName: "checkmark.circle.fill").foregroundStyle(CinemaPalette.accent) }
        }
        .padding(.horizontal, 11)
        .frame(height: 43)
        .background(chosen ? CinemaPalette.accent.opacity(0.18) : .white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}
