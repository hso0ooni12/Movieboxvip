import SwiftUI
import WebKit
import AVFoundation
import AVKit

struct FrameXTVPlayback: Hashable, Codable, Identifiable {
    let tmdbID: Int
    var season: Int? = nil
    var episode: Int? = nil
    var autoplay: Bool = true
    var muted: Bool = false
    var provider: String? = nil
    var startAt: Double = 0
    var speed: Double = 1
    var showEmbeddedControls: Bool = false

    var id: String {
        "\(tmdbID)-\(season ?? 0)-\(episode ?? 0)-\(Int(startAt))"
    }

    func embedURL(title: String? = nil, posterURL: URL? = nil) -> URL? {
        var path = "https://framextv.tech/embed/\(tmdbID)"
        if let season, let episode {
            path += "/\(season)/\(episode)"
        }

        guard var components = URLComponents(string: path) else { return nil }
        var queryItems: [URLQueryItem] = [
            .init(name: "autoplay", value: autoplay ? "1" : "0"),
            .init(name: "muted", value: muted ? "1" : "0"),
            .init(name: "controls", value: "0"),
            .init(name: "speed", value: String(speed))
        ]
        if startAt > 0 {
            queryItems.append(.init(name: "start", value: String(Int(startAt))))
        }
        if let provider, !provider.isEmpty, provider != "auto" {
            queryItems.append(.init(name: "provider", value: provider))
        }
        if let title, !title.isEmpty {
            queryItems.append(.init(name: "title", value: title))
        }
        if let posterURL {
            queryItems.append(.init(name: "poster", value: posterURL.absoluteString))
        }
        components.queryItems = queryItems
        return components.url
    }
}

private struct XSSubtitleOption: Identifiable, Hashable {
    let id: String
    let sourceIndex: Int?
    let label: String
    let language: String
    let source: String

    var displayName: String {
        let clean = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { return clean }
        let code = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if !code.isEmpty,
           let localized = Locale.current.localizedString(forLanguageCode: code) {
            return localized.capitalized
        }
        return code.isEmpty ? "Subtitle" : code.uppercased()
    }
}

private struct XSServerOption: Identifiable, Hashable {
    let id: String
    let name: String
    let quality: String
    let provider: String?
    let selected: Bool
}

private struct XSQualityOption: Identifiable, Hashable {
    let id: String
    let name: String
    let selected: Bool
}

private struct XSAudioOption: Identifiable, Hashable {
    let id: String
    let name: String
    let selected: Bool
}

@MainActor
private final class XSPlayerState: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var playbackRate: Double = 1
    @Published var isReady = false
    @Published var captionText = ""
    @Published var subtitleOptions: [XSSubtitleOption] = []
    @Published var selectedSubtitleID: String? = nil
    @Published var servers: [XSServerOption] = [
        .init(id: "auto", name: "Auto", quality: "AUTO", provider: "auto", selected: true),
        .init(id: "barbarian", name: "Barbarian", quality: "", provider: "barbarian", selected: false),
        .init(id: "archer", name: "Archer", quality: "", provider: "archer", selected: false),
        .init(id: "goblin", name: "Goblin", quality: "", provider: "goblin", selected: false)
    ]
    @Published var qualities: [XSQualityOption] = [.init(id: "auto", name: "AUTO", selected: true)]
    @Published var audioOptions: [XSAudioOption] = [.init(id: "default", name: "Original / Default", selected: true)]
    @Published var activeServerName = "Auto"
    @Published var activeQuality = "AUTO"
    @Published var errorMessage: String?

    weak var webView: WKWebView?
    var onProgress: ((Double, Double) -> Void)?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func reset() {
        currentTime = 0
        duration = 0
        isPlaying = false
        isReady = false
        captionText = ""
        subtitleOptions = []
        selectedSubtitleID = nil
        qualities = [.init(id: "auto", name: "AUTO", selected: true)]
        audioOptions = [.init(id: "default", name: "Original / Default", selected: true)]
        errorMessage = nil
    }

    func togglePlayback() { send(["action": isPlaying ? "pause" : "play"]) }
    func play() { send(["action": "play"]) }
    func pause() { send(["action": "pause"]) }
    func seek(to seconds: Double) { send(["action": "seek", "time": max(seconds, 0)]) }
    func seekBy(_ seconds: Double) { send(["action": "seekBy", "seconds": seconds]) }
    func setMuted(_ muted: Bool) { send(["action": "mute", "muted": muted]) }
    func setRate(_ rate: Double) { playbackRate = rate; send(["action": "rate", "rate": rate]) }
    func requestPiP() { send(["action": "pip"]) }
    func requestMetadata() { send(["action": "metadata"]) }
    func requestSubtitleMenu() { send(["action": "subtitleMenu"]) }
    func requestQualityMenu() { send(["action": "qualityMenu"]) }
    func requestAudioMenu() { send(["action": "audioMenu"]) }
    func setSubtitleDelay(_ seconds: Double) { send(["action": "subtitleDelay", "seconds": seconds]) }
    func setAspect(_ mode: String) { send(["action": "aspect", "mode": mode]) }

    func setSubtitleStyle(size: Double, color: String, background: Bool, bottom: Double) {
        send([
            "action": "subtitleStyle",
            "size": size,
            "color": color,
            "background": background,
            "bottom": bottom
        ])
    }

    func selectSubtitle(_ option: XSSubtitleOption?) {
        selectedSubtitleID = option?.id
        if let option {
            send([
                "action": "subtitle",
                "id": option.id,
                "index": option.sourceIndex ?? -1,
                "label": option.label,
                "language": option.language,
                "source": option.source
            ])
        } else {
            send(["action": "subtitle", "id": "off", "index": -1, "source": "off"])
        }
    }

    func selectServer(_ server: XSServerOption) {
        activeServerName = server.name
        if !server.quality.isEmpty { activeQuality = server.quality }
        var payload: [String: Any] = ["action": "server", "name": server.name]
        if let provider = server.provider { payload["provider"] = provider }
        send(payload)
    }

    func selectQuality(_ quality: XSQualityOption) {
        activeQuality = quality.name
        send(["action": "quality", "name": quality.name])
    }

    func selectAudio(_ audio: XSAudioOption) {
        send(["action": "audio", "name": audio.name])
    }

    func receive(_ payload: [String: Any]) {
        guard let event = payload["event"] as? String else { return }
        switch event {
        case "xs:ready":
            isReady = true
            errorMessage = nil

        case "xs:error":
            errorMessage = payload["message"] as? String ?? "Playback unavailable"

        case "xs:state", "frameXTV:timeupdate":
            if let value = doubleValue(payload["currentTime"]) { currentTime = value }
            if let value = doubleValue(payload["duration"]) { duration = value }
            if let paused = payload["paused"] as? Bool { isPlaying = !paused }
            if let muted = payload["muted"] as? Bool { isMuted = muted }
            if let rate = doubleValue(payload["rate"]) { playbackRate = rate }
            if currentTime > 0 || duration > 0 {
                isReady = true
                onProgress?(currentTime, duration)
            }

        case "xs:caption":
            captionText = payload["text"] as? String ?? ""

        case "xs:subtitles":
            guard let rows = payload["items"] as? [[String: Any]] else { return }
            let parsed = rows.compactMap { row -> XSSubtitleOption? in
                let id = row["id"] as? String ?? UUID().uuidString
                let label = row["label"] as? String ?? ""
                let language = row["language"] as? String ?? ""
                let source = row["source"] as? String ?? "unknown"
                let index = intValue(row["index"])
                guard !label.isEmpty || !language.isEmpty || index != nil else { return nil }
                return .init(id: id, sourceIndex: index, label: label, language: language, source: source)
            }
            if !parsed.isEmpty { subtitleOptions = dedupeSubtitles(parsed) }

        case "xs:servers":
            guard let rows = payload["items"] as? [[String: Any]] else { return }
            let parsed = rows.compactMap { row -> XSServerOption? in
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let quality = row["quality"] as? String ?? ""
                let provider = row["provider"] as? String
                let selected = row["selected"] as? Bool ?? false
                return .init(id: (provider ?? name) + quality, name: name, quality: quality, provider: provider, selected: selected)
            }
            if !parsed.isEmpty {
                servers = parsed
                if let selected = parsed.first(where: { $0.selected }) {
                    activeServerName = selected.name
                    if !selected.quality.isEmpty { activeQuality = selected.quality }
                }
            }

        case "xs:qualities":
            guard let rows = payload["items"] as? [[String: Any]] else { return }
            let parsed = rows.compactMap { row -> XSQualityOption? in
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return .init(id: name.lowercased(), name: name, selected: row["selected"] as? Bool ?? false)
            }
            if !parsed.isEmpty {
                qualities = parsed
                if let selected = parsed.first(where: { $0.selected }) { activeQuality = selected.name }
            }

        case "xs:audio":
            guard let rows = payload["items"] as? [[String: Any]] else { return }
            let parsed = rows.compactMap { row -> XSAudioOption? in
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                return .init(id: name.lowercased(), name: name, selected: row["selected"] as? Bool ?? false)
            }
            if !parsed.isEmpty { audioOptions = parsed }

        default:
            break
        }
    }

    private func dedupeSubtitles(_ input: [XSSubtitleOption]) -> [XSSubtitleOption] {
        var seen = Set<String>()
        var output: [XSSubtitleOption] = []
        for item in input {
            let key = "\(item.displayName.lowercased())|\(item.language.lowercased())"
            if seen.insert(key).inserted { output.append(item) }
        }
        return output
    }

    private func send(_ payload: [String: Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.xsCommand && window.xsCommand(\(json));")
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }
}

private struct XSPlaybackWebView: UIViewRepresentable {
    let playback: FrameXTVPlayback
    let title: String
    let posterURL: URL?
    @ObservedObject var model: XSPlayerState

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "xsTelemetry")
        contentController.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        )

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.isUserInteractionEnabled = false

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay])
            try session.setActive(true)
        } catch { }

        model.attach(webView)
        load(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) { }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "xsTelemetry")
    }

    private func load(in webView: WKWebView) {
        guard let embedURL = playback.embedURL(title: title, posterURL: posterURL) else { return }
        let escaped = embedURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let html = """
        <!doctype html>
        <html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">
        <style>
        html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}
        iframe{position:fixed;inset:0;width:100%;height:100%;border:0;pointer-events:none;background:#000}
        </style></head><body>
        <iframe id="engine" src="\(escaped)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe>
        <script>
        const engine=document.getElementById('engine');
        window.xsCommand=function(payload){
          try{engine.contentWindow.postMessage({__xsCommand:payload},'*')}catch(_){ }
          try{engine.contentWindow.postMessage(payload,'*')}catch(_){ }
        };
        window.addEventListener('message',function(event){
          try{
            const d=event.data;
            if(d&&d.event&&String(d.event).indexOf('frameXTV:')===0){
              window.webkit.messageHandlers.xsTelemetry.postMessage(d);
            }
          }catch(_){ }
        });
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://framextv.tech"))
    }

    private static let bridgeScript = #"""
    (function(){
      if(window.__xsV6)return;
      window.__xsV6=true;

      let video=null;
      let selectedTrack=-1;
      let selectedDomSubtitle='';
      let subtitleDelay=0;
      let lastCaption='';
      let subtitleStyle={size:1,color:'#ffffff',background:true,bottom:76};

      function bridge(payload){try{window.webkit.messageHandlers.xsTelemetry.postMessage(payload)}catch(_){}}
      function cleanText(el){return String((el&&(el.innerText||el.textContent))||'').replace(/\s+/g,' ').trim()}
      function findVideo(){try{const list=Array.from(document.querySelectorAll('video'));return list.sort((a,b)=>(b.clientWidth*b.clientHeight)-(a.clientWidth*a.clientHeight))[0]||null}catch(_){return null}}
      function isLanguageText(text){return /arabic|english|spanish|french|german|italian|portuguese|turkish|russian|hindi|urdu|japanese|korean|chinese|thai|indonesian|malay|dutch|polish|swedish|norwegian|danish|finnish|greek|hebrew|العربية|انجليزي|إنجليزي|عربي|español|français|deutsch|italiano|português|türkçe|русский|日本語|한국어|中文/i.test(text)}

      function hideChrome(){
        const v=video||findVideo();
        if(v){try{v.controls=false;v.setAttribute('playsinline','');v.setAttribute('webkit-playsinline','')}catch(_){}}
        try{
          Array.from(document.querySelectorAll('button,[role="button"],[role="dialog"],header,nav')).forEach(el=>{
            el.style.setProperty('opacity','0','important');
            el.style.setProperty('pointer-events','none','important');
          });
        }catch(_){ }
      }

      function applyCueStyle(){
        try{
          let style=document.getElementById('xs-cue-style');
          if(!style){style=document.createElement('style');style.id='xs-cue-style';document.head.appendChild(style)}
          const bg=subtitleStyle.background?'rgba(0,0,0,.68)':'transparent';
          const px=Math.round(22*Number(subtitleStyle.size||1));
          style.textContent='video::cue{font-size:'+px+'px!important;color:'+subtitleStyle.color+'!important;background:'+bg+'!important;font-family:-apple-system,BlinkMacSystemFont,Helvetica Neue,Arial,sans-serif!important;font-weight:700!important}';
          document.documentElement.style.setProperty('--xs-sub-bottom',String(subtitleStyle.bottom||76)+'px');
          Array.from(document.querySelectorAll('[class*="subtitle" i],[class*="caption" i]')).forEach(el=>{
            if(el.closest('button,[role="button"],[role="dialog"]'))return;
            el.style.setProperty('font-size',px+'px','important');
            el.style.setProperty('color',subtitleStyle.color,'important');
            el.style.setProperty('font-family','-apple-system,BlinkMacSystemFont,Helvetica Neue,Arial,sans-serif','important');
            el.style.setProperty('font-weight','700','important');
          });
        }catch(_){ }
      }

      function reportState(){
        const v=video||findVideo();if(!v)return;
        bridge({event:'xs:state',currentTime:Number(v.currentTime||0),duration:Number(isFinite(v.duration)?v.duration:0),paused:!!v.paused,muted:!!v.muted,rate:Number(v.playbackRate||1)});
      }

      function languageFromCode(code){
        const c=String(code||'').toLowerCase();
        const m={ar:'Arabic',ara:'Arabic',en:'English',eng:'English',es:'Spanish',spa:'Spanish',fr:'French',fra:'French',de:'German',deu:'German',it:'Italian',ita:'Italian',pt:'Portuguese',por:'Portuguese',tr:'Turkish',tur:'Turkish',ru:'Russian',rus:'Russian',ja:'Japanese',jpn:'Japanese',ko:'Korean',kor:'Korean',zh:'Chinese',zho:'Chinese',hi:'Hindi',hin:'Hindi',ur:'Urdu',urd:'Urdu'};
        return m[c]||code||'';
      }

      function scanSubtitles(){
        const items=[];const seen=new Set();const v=video||findVideo();
        function add(id,index,label,language,source){
          let l=String(label||'').trim();let lang=String(language||'').trim();
          if(!l&&lang)l=languageFromCode(lang);
          if(!l&&!lang)return;
          const key=(l+'|'+lang).toLowerCase();if(seen.has(key))return;seen.add(key);
          items.push({id:String(id),index:index,label:l,language:lang,source:source});
        }
        try{
          if(v&&v.textTracks){for(let i=0;i<v.textTracks.length;i++){const t=v.textTracks[i];add('track-'+i,i,t.label||'',t.language||'','textTrack')}}
        }catch(_){ }
        try{
          Array.from(document.querySelectorAll('track[kind="subtitles"],track[kind="captions"]')).forEach((t,i)=>add('tag-'+i,i,t.getAttribute('label')||'',t.getAttribute('srclang')||'','trackTag'));
        }catch(_){ }
        try{
          Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div')).forEach((el,i)=>{
            const text=cleanText(el);if(!text||text.length>45||!isLanguageText(text))return;
            add('dom-'+i,null,text,'','dom');
          });
        }catch(_){ }
        bridge({event:'xs:subtitles',items:items});
      }

      function clickControl(kind){
        try{
          const nodes=Array.from(document.querySelectorAll('button,[role="button"]'));
          const found=nodes.find(el=>{
            const meta=(String(el.getAttribute('aria-label')||'')+' '+String(el.getAttribute('title')||'')+' '+cleanText(el)).toLowerCase();
            if(kind==='subtitle')return /subtitle|caption|\bcc\b/.test(meta);
            if(kind==='quality')return /quality|resolution|auto|1080|720|4k|fhd/.test(meta);
            if(kind==='audio')return /audio|language|sound/.test(meta);
            return false;
          });
          if(found){found.click();return true}
        }catch(_){ }
        return false;
      }

      function openAndScan(kind){
        clickControl(kind);
        setTimeout(()=>{if(kind==='subtitle')scanSubtitles();else if(kind==='quality')scanQualities();else scanAudio()},150);
        setTimeout(()=>{if(kind==='subtitle')scanSubtitles();else if(kind==='quality')scanQualities();else scanAudio()},500);
      }

      function selectDomText(text){
        const wanted=String(text||'').trim().toLowerCase();if(!wanted)return false;
        try{
          const nodes=Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,label,div'));
          const found=nodes.find(el=>{const t=cleanText(el).toLowerCase();return t===wanted||t.startsWith(wanted+' ')||wanted.startsWith(t+' ')});
          if(found){found.click();return true}
        }catch(_){ }
        return false;
      }

      function scanQualities(){
        const out=[];const seen=new Set();
        try{
          Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div')).forEach(el=>{
            const text=cleanText(el);if(!text||text.length>35)return;
            const m=text.match(/\b(AUTO|4K|2160P|1440P|1080P|FHD|720P|HD|480P|360P)\b/i);if(!m)return;
            const name=m[1].toUpperCase();if(seen.has(name))return;seen.add(name);out.push({name:name,selected:/selected|active|connected/i.test(String(el.className||'')+' '+text)});
          });
        }catch(_){ }
        if(!seen.has('AUTO'))out.unshift({name:'AUTO',selected:out.length===0});
        bridge({event:'xs:qualities',items:out});
      }

      function scanAudio(){
        const out=[];const seen=new Set();
        try{
          Array.from(document.querySelectorAll('button,[role="button"],[role="menuitem"],li,div')).forEach(el=>{
            const text=cleanText(el);if(!text||text.length>50)return;
            if(!/audio|original|dubbed|english|arabic|japanese|hindi|spanish|french/i.test(text))return;
            const key=text.toLowerCase();if(seen.has(key))return;seen.add(key);out.push({name:text,selected:/selected|active|connected/i.test(String(el.className||''))});
          });
        }catch(_){ }
        if(!out.length)out.push({name:'Original / Default',selected:true});
        bridge({event:'xs:audio',items:out});
      }

      function scanServers(){
        const out=[];const seen=new Set();
        try{
          Array.from(document.querySelectorAll('button,[role="button"],li,div')).forEach(el=>{
            const text=cleanText(el);if(!text||text.length>100)return;
            if(!/(Connected|Available|4K|FHD|UHD|1080p|720p|HD)/i.test(text))return;
            const q=(text.match(/(4K|UHD|FHD|1080p|720p|HD)/i)||[])[1]||'';
            const name=text.replace(/Connected|Available|4K|UHD|FHD|1080p|720p|HD/ig,'').replace(/\s+/g,' ').trim();
            if(!name||name.length>45||seen.has(name.toLowerCase()))return;seen.add(name.toLowerCase());
            out.push({name:name,quality:q.toUpperCase(),selected:/Connected/i.test(text)});
          });
        }catch(_){ }
        if(out.length)bridge({event:'xs:servers',items:out});
      }

      function reportCaption(){
        const v=video||findVideo();
        if(!v||!v.textTracks||selectedTrack<0||selectedTrack>=v.textTracks.length){if(lastCaption!==''){lastCaption='';bridge({event:'xs:caption',text:''})}return}
        const t=v.textTracks[selectedTrack];
        try{t.mode='hidden'}catch(_){ }
        const wanted=Number(v.currentTime||0)+subtitleDelay;let text='';
        try{
          const cues=t.cues||[];
          for(let i=0;i<cues.length;i++){const cue=cues[i];if(cue.startTime<=wanted&&cue.endTime>=wanted){text=cue.text||'';break}if(cue.startTime>wanted)break}
        }catch(_){ }
        if(text!==lastCaption){lastCaption=text;bridge({event:'xs:caption',text:text})}
      }

      function install(v){
        if(!v||video===v)return;video=v;
        try{v.controls=false;v.setAttribute('playsinline','');v.setAttribute('webkit-playsinline','')}catch(_){ }
        ['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ratechange','ended','canplay'].forEach(name=>{try{v.addEventListener(name,reportState,{passive:true})}catch(_){}});
        try{v.addEventListener('loadedmetadata',()=>{scanSubtitles();scanQualities();scanAudio()},{passive:true})}catch(_){ }
        bridge({event:'xs:ready'});reportState();scanSubtitles();scanServers();applyCueStyle();hideChrome();
      }

      function command(p){
        const v=video||findVideo();const a=p&&p.action;
        try{
          if(a==='play'&&v)v.play();
          else if(a==='pause'&&v)v.pause();
          else if(a==='seek'&&v)v.currentTime=Math.max(0,Number(p.time||0));
          else if(a==='seekBy'&&v)v.currentTime=Math.max(0,Number(v.currentTime||0)+Number(p.seconds||0));
          else if(a==='mute'&&v)v.muted=!!p.muted;
          else if(a==='rate'&&v)v.playbackRate=Number(p.rate||1);
          else if(a==='pip'&&v){if(typeof v.webkitSetPresentationMode==='function')v.webkitSetPresentationMode('picture-in-picture');else if(v.requestPictureInPicture)v.requestPictureInPicture()}
          else if(a==='aspect'&&v){const mode=String(p.mode||'adapt');v.style.objectFit=mode==='stretch'?'fill':(mode==='fill'?'cover':'contain')}
          else if(a==='subtitleDelay')subtitleDelay=Number(p.seconds||0);
          else if(a==='subtitleStyle'){subtitleStyle={size:Number(p.size||1),color:String(p.color||'#ffffff'),background:!!p.background,bottom:Number(p.bottom||76)};applyCueStyle()}
          else if(a==='subtitleMenu')openAndScan('subtitle');
          else if(a==='qualityMenu')openAndScan('quality');
          else if(a==='audioMenu')openAndScan('audio');
          else if(a==='subtitle'){
            if(String(p.source)==='off'||Number(p.index)<0){selectedTrack=-1;selectedDomSubtitle='';if(v&&v.textTracks){for(let i=0;i<v.textTracks.length;i++){try{v.textTracks[i].mode='disabled'}catch(_){}}}lastCaption='';bridge({event:'xs:caption',text:''})}
            else if(Number(p.index)>=0&&v&&v.textTracks&&Number(p.index)<v.textTracks.length){selectedTrack=Number(p.index);for(let i=0;i<v.textTracks.length;i++){try{v.textTracks[i].mode=i===selectedTrack?'hidden':'disabled'}catch(_){}}reportCaption()}
            else {selectedTrack=-1;selectedDomSubtitle=String(p.label||p.language||'');openAndScan('subtitle');setTimeout(()=>selectDomText(selectedDomSubtitle),180)}
          }
          else if(a==='quality'){openAndScan('quality');setTimeout(()=>selectDomText(String(p.name||'')),180);setTimeout(scanQualities,450)}
          else if(a==='audio'){openAndScan('audio');setTimeout(()=>selectDomText(String(p.name||'')),180);setTimeout(scanAudio,450)}
          else if(a==='server'){
            if(p.provider)window.postMessage({action:'setProvider',provider:p.provider},'*');
            if(p.name)setTimeout(()=>selectDomText(String(p.name)),100);
            setTimeout(scanServers,550);
          }
          else if(a==='metadata'){scanSubtitles();scanServers();scanQualities();scanAudio();openAndScan('subtitle')}
        }catch(_){ }
        reportState();
      }

      window.addEventListener('message',function(event){
        try{
          const d=event.data;
          if(d&&d.__xsCommand)command(d.__xsCommand);
          if(d&&d.event&&String(d.event).indexOf('frameXTV:')===0){
            if(Array.isArray(d.subtitles)){bridge({event:'xs:subtitles',items:d.subtitles})}
            if(Array.isArray(d.tracks)){bridge({event:'xs:subtitles',items:d.tracks})}
          }
        }catch(_){ }
      },true);

      try{new MutationObserver(()=>{const v=findVideo();if(v)install(v);hideChrome();applyCueStyle()}).observe(document.documentElement||document.body,{subtree:true,childList:true})}catch(_){ }
      setInterval(()=>{const v=findVideo();if(v)install(v);hideChrome();reportState();reportCaption();scanSubtitles();applyCueStyle()},350);
      setInterval(()=>{scanServers();scanQualities()},1400);
      setTimeout(()=>{if(!findVideo())bridge({event:'xs:error',message:'Waiting for playback engine…'})},9000);
    })();
    """#

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let model: XSPlayerState
        init(model: XSPlayerState) { self.model = model }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let payload = message.body as? [String: Any] else { return }
            Task { @MainActor in model.receive(payload) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

private struct XSAirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = true
        view.tintColor = .white
        view.activeTintColor = .white
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}

private enum XSPlayerPanel: Equatable {
    case none
    case quality
    case subtitles
    case subtitleStyle
    case subtitleDelay
    case settings
    case audio
}

struct FrameXTVPlayerScreen: View {
    let item: MediaItem
    let playback: FrameXTVPlayback
    let nextPlayback: FrameXTVPlayback?
    let nextLabel: String?

    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var player = XSPlayerState()
    @State private var activePlayback: FrameXTVPlayback
    @State private var queuedPlayback: FrameXTVPlayback?
    @State private var queuedLabel: String?
    @State private var controlsVisible = true
    @State private var panel: XSPlayerPanel = .none
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hideTask: Task<Void, Never>?
    @State private var resolvingNext = false
    @State private var advancing = false
    @State private var aspectMode = "adapt"

    @AppStorage("XSTV.autoNextEpisode") private var autoNext = true
    @AppStorage("XSTV.subtitleFontScale") private var subtitleScale = 1.0
    @AppStorage("XSTV.subtitleBottomPadding") private var subtitleBottom = 76.0
    @AppStorage("XSTV.subtitleDelay") private var subtitleDelay = 0.0
    @AppStorage("XSTV.subtitleBackground") private var subtitleBackground = true
    @AppStorage("XSTV.subtitleColor") private var subtitleColor = "#FFFFFF"

    init(item: MediaItem, playback: FrameXTVPlayback, nextPlayback: FrameXTVPlayback? = nil, nextLabel: String? = nil) {
        self.item = item
        self.playback = playback
        self.nextPlayback = nextPlayback
        self.nextLabel = nextLabel
        var clean = playback
        clean.showEmbeddedControls = false
        _activePlayback = State(initialValue: clean)
        _queuedPlayback = State(initialValue: nextPlayback)
        _queuedLabel = State(initialValue: nextLabel)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()

                XSPlaybackWebView(
                    playback: activePlayback,
                    title: playbackTitle,
                    posterURL: item.imageURL(backdrop: true, width: 1280) ?? item.imageURL(width: 780),
                    model: player
                )
                .id(activePlayback.id)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { revealControls() }

                if !player.captionText.isEmpty {
                    captionOverlay(width: proxy.size.width)
                }

                if controlsVisible {
                    controlsOverlay(proxy)
                        .transition(.opacity)
                }

                if panel != .none {
                    panelOverlay(proxy)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                if !player.isReady {
                    loadingOverlay
                }

                if shouldShowNext {
                    VStack {
                        Spacer()
                        HStack { Spacer(); nextEpisodePrompt }
                            .padding(.trailing, 28)
                            .padding(.bottom, 96)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onAppear {
            installProgressHandler()
            player.setSubtitleDelay(subtitleDelay)
            pushSubtitleStyle()
            controlsVisible = true
            scheduleHide()
            Task { await resolveNextEpisode() }
        }
        .onChange(of: player.isPlaying) { playing in
            if playing { scheduleHide() }
            else { hideTask?.cancel(); controlsVisible = true }
        }
        .onChange(of: player.currentTime) { _ in handlePlaybackProgress() }
        .onChange(of: subtitleDelay) { value in player.setSubtitleDelay(value) }
        .onChange(of: subtitleScale) { _ in pushSubtitleStyle() }
        .onChange(of: subtitleBottom) { _ in pushSubtitleStyle() }
        .onChange(of: subtitleBackground) { _ in pushSubtitleStyle() }
        .onChange(of: subtitleColor) { _ in pushSubtitleStyle() }
        .onDisappear {
            hideTask?.cancel()
            player.pause()
            player.onProgress = nil
        }
    }

    private var playbackTitle: String {
        if let season = activePlayback.season, let episode = activePlayback.episode {
            return "\(item.title) S\(season)E\(episode)"
        }
        return item.title
    }

    private func controlsOverlay(_ proxy: GeometryProxy) -> some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.60), .clear, .black.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    roundButton("xmark") { dismiss() }

                    HStack(spacing: 8) {
                        Button { player.requestPiP(); revealControls() } label: {
                            Image(systemName: "pip.enter")
                        }
                        .buttonStyle(.plain)

                        XSAirPlayPicker()
                            .frame(width: 35, height: 35)
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(.black.opacity(0.46), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16)))

                    Text(playbackTitle)
                        .font(.headline.weight(.medium))
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 17) {
                        Button { openPanel(.quality) } label: {
                            Text(player.activeQuality)
                                .font(.caption.bold())
                                .padding(.horizontal, 4)
                        }
                        Button { openPanel(.subtitles) } label: {
                            Image(systemName: "captions.bubble.fill")
                        }
                        Button { openPanel(.audio) } label: {
                            Image(systemName: "waveform")
                        }
                        Button { openPanel(.settings) } label: {
                            Image(systemName: "ellipsis")
                        }
                    }
                    .font(.system(size: 19, weight: .semibold))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(.black.opacity(0.46), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16)))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.top, max(proxy.safeAreaInsets.top, 14))

                Spacer()

                HStack(spacing: 52) {
                    Button { player.seekBy(-10); revealControls() } label: {
                        Image(systemName: "gobackward.10").font(.system(size: 38, weight: .medium))
                    }
                    Button { player.togglePlayback(); revealControls() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 44, weight: .bold))
                            .frame(width: 88, height: 88)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.22)))
                    }
                    Button { player.seekBy(10); revealControls() } label: {
                        Image(systemName: "goforward.10").font(.system(size: 38, weight: .medium))
                    }
                }
                .foregroundStyle(.white)

                Spacer()

                HStack(alignment: .bottom) {
                    HStack(spacing: 20) {
                        Button { openPanel(.subtitleDelay) } label: { Image(systemName: "tortoise") }
                        Button { openPanel(.subtitleStyle) } label: { Text("Aa").font(.system(size: 20, weight: .medium)) }
                        Button { openPanel(.subtitles) } label: { Image(systemName: "character.bubble") }
                        Button { player.selectSubtitle(nil); revealControls() } label: { Image(systemName: "xmark") }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 48)
                    .background(.black.opacity(0.46), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16)))

                    Spacer()

                    HStack(spacing: 14) {
                        Button { openPanel(.settings) } label: { Image(systemName: "list.bullet.rectangle") }
                        Button { openPanel(.settings) } label: { Image(systemName: "hexagon") }
                        Button {
                            aspectMode = aspectMode == "adapt" ? "fill" : "adapt"
                            player.setAspect(aspectMode)
                            revealControls()
                        } label: {
                            Image(systemName: aspectMode == "adapt" ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 48)
                    .background(.black.opacity(0.46), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.16)))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)

                HStack(spacing: 12) {
                    Text(formatTime(isScrubbing ? scrubValue : player.currentTime))
                        .font(.caption.monospacedDigit())
                        .frame(width: 64, alignment: .leading)

                    Slider(
                        value: Binding(get: { isScrubbing ? scrubValue : player.currentTime }, set: { scrubValue = $0 }),
                        in: 0...max(player.duration, 1),
                        onEditingChanged: { editing in
                            isScrubbing = editing
                            if editing {
                                scrubValue = player.currentTime
                                holdControls()
                            } else {
                                player.seek(to: scrubValue)
                                revealControls()
                            }
                        }
                    )
                    .tint(.white)

                    Text("−" + formatTime(max(player.duration - (isScrubbing ? scrubValue : player.currentTime), 0)))
                        .font(.caption.monospacedDigit())
                        .frame(width: 68, alignment: .trailing)
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 28)
                .frame(height: 54)
                .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.12)))
                .padding(.horizontal, 28)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 12))
            }
        }
    }

    @ViewBuilder
    private func panelOverlay(_ proxy: GeometryProxy) -> some View {
        switch panel {
        case .quality:
            trailingPanel(width: min(proxy.size.width * 0.52, 620), title: "Quality & Server") { qualityPanel }
        case .subtitles:
            trailingPanel(width: min(proxy.size.width * 0.52, 620), title: "Subtitles") { subtitlesPanel }
        case .audio:
            trailingPanel(width: min(proxy.size.width * 0.48, 560), title: "Audio") { audioPanel }
        case .settings:
            trailingPanel(width: min(proxy.size.width * 0.50, 590), title: "Playback") { settingsPanel }
        case .subtitleStyle:
            bottomPanel { subtitleStylePanel }
        case .subtitleDelay:
            bottomPanel { subtitleDelayPanel }
        case .none:
            EmptyView()
        }
    }

    private func trailingPanel<Content: View>(width: CGFloat, title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.18)
                .contentShape(Rectangle())
                .onTapGesture { closePanel() }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(title).font(.title3.bold())
                    Spacer()
                    Button { closePanel() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
                }
                .foregroundStyle(.white)
                content()
                Spacer(minLength: 0)
            }
            .padding(26)
            .frame(width: width, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial)
            .overlay(Rectangle().fill(.white.opacity(0.08)).frame(width: 1), alignment: .leading)
        }
        .ignoresSafeArea()
    }

    private func bottomPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                content()
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).stroke(.white.opacity(0.12)))
            .padding(.horizontal, 28)
            .padding(.bottom, 76)
        }
        .ignoresSafeArea()
    }

    private var qualityPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("QUALITY").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(player.qualities) { quality in
                    panelRow(title: quality.name, detail: quality.selected ? "Selected" : nil) {
                        player.selectQuality(quality)
                        closePanel()
                    }
                }

                Divider().padding(.vertical, 6)
                Text("SERVERS").font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(player.servers) { server in
                    panelRow(title: server.name, detail: server.quality.isEmpty ? (server.selected ? "Connected" : "Available") : "\(server.quality) · \(server.selected ? "Connected" : "Available")") {
                        player.selectServer(server)
                        closePanel()
                    }
                }
            }
        }
        .onAppear {
            player.requestQualityMenu()
            player.requestMetadata()
        }
    }

    private var subtitlesPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                panelRow(title: "Off", detail: player.selectedSubtitleID == nil ? "Selected" : nil) {
                    player.selectSubtitle(nil)
                    closePanel()
                }

                if player.subtitleOptions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Looking for subtitle tracks on this server…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Scan Again") {
                            player.requestSubtitleMenu()
                            player.requestMetadata()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 10)
                } else {
                    ForEach(player.subtitleOptions) { option in
                        panelRow(title: option.displayName, detail: player.selectedSubtitleID == option.id ? "Selected" : languageDetail(option)) {
                            player.selectSubtitle(option)
                            closePanel()
                        }
                    }
                }

                Divider().padding(.vertical, 6)
                Button {
                    panel = .subtitleStyle
                } label: {
                    Label("Subtitle Appearance", systemImage: "textformat.size")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)

                Button {
                    panel = .subtitleDelay
                } label: {
                    Label("Subtitle Timing", systemImage: "timer")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .onAppear {
            player.requestSubtitleMenu()
            player.requestMetadata()
        }
    }

    private var audioPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(player.audioOptions) { audio in
                    panelRow(title: audio.name, detail: audio.selected ? "Selected" : nil) {
                        player.selectAudio(audio)
                        closePanel()
                    }
                }
            }
        }
        .onAppear { player.requestAudioMenu() }
    }

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Aspect Ratio").font(.headline)
                HStack(spacing: 10) {
                    settingChip("Adapt", selected: aspectMode == "adapt") { aspectMode = "adapt"; player.setAspect("adapt") }
                    settingChip("Stretch", selected: aspectMode == "stretch") { aspectMode = "stretch"; player.setAspect("stretch") }
                    settingChip("Filling", selected: aspectMode == "fill") { aspectMode = "fill"; player.setAspect("fill") }
                }

                Text("Speed").font(.headline)
                HStack(spacing: 8) {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        settingChip(speed == 1 ? "1" : String(speed), selected: abs(player.playbackRate - speed) < 0.01) {
                            player.setRate(speed)
                        }
                    }
                }

                Toggle("Auto Play Next Episode", isOn: $autoNext)
                    .tint(.blue)

                Button {
                    player.seek(to: 0)
                    closePanel()
                } label: {
                    Label("Jump to Start", systemImage: "backward.end.fill")
                }
                .buttonStyle(.bordered)
            }
            .foregroundStyle(.white)
        }
    }

    private var subtitleStylePanel: some View {
        HStack(spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Size").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { subtitleScale = max(0.7, subtitleScale - 0.1) } label: { Image(systemName: "minus.circle") }
                    Text("\(Int(subtitleScale * 100))%").frame(width: 58)
                    Button { subtitleScale = min(1.8, subtitleScale + 0.1) } label: { Image(systemName: "plus.circle") }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    colorButton("#FFFFFF", .white)
                    colorButton("#FFD60A", .yellow)
                    colorButton("#00D4FF", .cyan)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Background").font(.caption).foregroundStyle(.secondary)
                Toggle("", isOn: $subtitleBackground).labelsHidden().tint(.blue)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Position").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { subtitleBottom = max(38, subtitleBottom - 12) } label: { Image(systemName: "arrow.down") }
                    Button { subtitleBottom = min(190, subtitleBottom + 12) } label: { Image(systemName: "arrow.up") }
                }
            }

            Spacer()
            Button { closePanel() } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
        }
        .font(.title3)
        .foregroundStyle(.white)
    }

    private var subtitleDelayPanel: some View {
        VStack(spacing: 12) {
            Text("If subtitle is slow, increase it")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(String(format: "%+.2f s", subtitleDelay))
                .font(.title3.monospacedDigit().bold())
            Slider(value: $subtitleDelay, in: -7.5...9.0, step: 0.25)
                .tint(.white)
            HStack {
                Text("−7.5").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Reset") { subtitleDelay = 0 }
                    .buttonStyle(.bordered)
                Spacer()
                Text("+9.0").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
    }

    private func panelRow(title: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func settingChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(selected ? Color.blue : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func colorButton(_ hex: String, _ color: Color) -> some View {
        Button {
            subtitleColor = hex
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(color)
                .frame(width: 34, height: 34)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(subtitleColor == hex ? Color.blue : Color.white.opacity(0.25), lineWidth: subtitleColor == hex ? 3 : 1))
        }
        .buttonStyle(.plain)
    }

    private func captionOverlay(width: CGFloat) -> some View {
        VStack {
            Spacer()
            Text(player.captionText)
                .font(.system(size: max(18, min(width * 0.028, 34)) * subtitleScale, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(colorFromHex(subtitleColor))
                .padding(.horizontal, 13)
                .padding(.vertical, subtitleBackground ? 7 : 0)
                .background(subtitleBackground ? Color.black.opacity(0.68) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .shadow(color: .black.opacity(0.9), radius: 2)
                .padding(.horizontal, width * 0.12)
                .padding(.bottom, subtitleBottom)
        }
        .allowsHitTesting(false)
    }

    private var loadingOverlay: some View {
        VStack(spacing: 14) {
            ProgressView().tint(.white).scaleEffect(1.15)
            Text(player.errorMessage ?? "Loading video…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(22)
        .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 20))
        .allowsHitTesting(false)
    }

    private func roundButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
    }

    private func openPanel(_ newPanel: XSPlayerPanel) {
        holdControls()
        withAnimation(.easeInOut(duration: 0.18)) { panel = newPanel }
        if newPanel == .subtitles { player.requestSubtitleMenu() }
        if newPanel == .quality { player.requestQualityMenu(); player.requestMetadata() }
        if newPanel == .audio { player.requestAudioMenu() }
    }

    private func closePanel() {
        withAnimation(.easeInOut(duration: 0.18)) { panel = .none }
        revealControls()
    }

    private func pushSubtitleStyle() {
        player.setSubtitleStyle(size: subtitleScale, color: subtitleColor, background: subtitleBackground, bottom: subtitleBottom)
    }

    private func languageDetail(_ option: XSSubtitleOption) -> String? {
        let code = option.language.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.isEmpty { return option.source == "dom" ? "Player subtitle" : nil }
        return code.uppercased()
    }

    private func colorFromHex(_ hex: String) -> Color {
        switch hex.uppercased() {
        case "#FFD60A": return .yellow
        case "#00D4FF": return .cyan
        default: return .white
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    private func holdControls() {
        hideTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeInOut(duration: 0.15)) { controlsVisible = true }
        }
    }

    private func revealControls() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { controlsVisible = true }
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible, player.isPlaying, panel == .none, !isScrubbing else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    if player.isPlaying, panel == .none, !isScrubbing {
                        withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
                    }
                }
            }
        }
    }

    private var shouldShowNext: Bool {
        queuedPlayback != nil && player.duration > 0 && player.duration - player.currentTime <= 22 && player.duration - player.currentTime > 0
    }

    private var nextEpisodePrompt: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("UP NEXT").font(.caption2.bold()).tracking(1.8).foregroundStyle(.white.opacity(0.58))
            Text(queuedLabel ?? "Next Episode").font(.subheadline.bold())
            HStack {
                if autoNext { Text("Playing soon").font(.caption).foregroundStyle(.white.opacity(0.66)) }
                Button("Play Now") { playNextEpisode() }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
    }

    private func installProgressHandler() {
        player.onProgress = { current, duration in
            library.updateProgress(item: item, season: activePlayback.season, episode: activePlayback.episode, current: current, duration: duration)
        }
    }

    private func handlePlaybackProgress() {
        guard autoNext, queuedPlayback != nil, player.duration > 0, player.duration - player.currentTime <= 1.2, !advancing else { return }
        playNextEpisode()
    }

    @MainActor
    private func resolveNextEpisode() async {
        guard queuedPlayback == nil,
              !resolvingNext,
              item.kind != .movie,
              let season = activePlayback.season,
              let episode = activePlayback.episode else { return }

        resolvingNext = true
        defer { resolvingNext = false }

        do {
            let episodes = try await app.episodes(tmdbID: item.tmdbID, season: season)
            if let index = episodes.firstIndex(where: { $0.episodeNumber == episode }), episodes.indices.contains(index + 1) {
                let next = episodes[index + 1]
                queuedPlayback = FrameXTVPlayback(tmdbID: item.tmdbID, season: season, episode: next.episodeNumber)
                queuedLabel = "S\(season) · E\(next.episodeNumber)  \(next.name)"
                return
            }

            let seasons = try await app.seasons(for: item)
            guard let nextSeason = seasons.map(\.seasonNumber).filter({ $0 > season }).sorted().first else { return }
            let nextEpisodes = try await app.episodes(tmdbID: item.tmdbID, season: nextSeason)
            guard let first = nextEpisodes.first else { return }
            queuedPlayback = FrameXTVPlayback(tmdbID: item.tmdbID, season: nextSeason, episode: first.episodeNumber)
            queuedLabel = "S\(nextSeason) · E\(first.episodeNumber)  \(first.name)"
        } catch { }
    }

    private func playNextEpisode() {
        guard var next = queuedPlayback else { return }
        advancing = true
        next.showEmbeddedControls = false
        player.pause()
        player.reset()
        activePlayback = next
        queuedPlayback = nil
        queuedLabel = nil
        controlsVisible = true
        panel = .none

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await resolveNextEpisode()
            await MainActor.run {
                advancing = false
                revealControls()
            }
        }
    }
}
