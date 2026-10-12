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

    var id: String { "\(tmdbID)-\(season ?? 0)-\(episode ?? 0)-\(Int(startAt))" }

    func embedURL(title: String? = nil, posterURL: URL? = nil) -> URL? {
        var path = "https://framextv.tech/embed/\(tmdbID)"
        if let season, let episode { path += "/\(season)/\(episode)" }
        guard var components = URLComponents(string: path) else { return nil }
        var query: [URLQueryItem] = [
            .init(name: "autoplay", value: autoplay ? "1" : "0"),
            .init(name: "muted", value: muted ? "1" : "0"),
            .init(name: "controls", value: "0"),
            .init(name: "speed", value: String(speed))
        ]
        if startAt > 0 { query.append(.init(name: "start", value: String(Int(startAt)))) }
        if let provider, !provider.isEmpty, provider != "auto" { query.append(.init(name: "provider", value: provider)) }
        if let title, !title.isEmpty { query.append(.init(name: "title", value: title)) }
        if let posterURL { query.append(.init(name: "poster", value: posterURL.absoluteString)) }
        components.queryItems = query
        return components.url
    }
}

private struct XSSubtitle: Identifiable, Hashable {
    let id: Int
    let label: String
    let language: String
    var displayName: String {
        if !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return label }
        if !language.isEmpty, let name = Locale.current.localizedString(forLanguageCode: language) { return name.capitalized }
        return language.isEmpty ? "Subtitle \(id + 1)" : language.uppercased()
    }
}

private struct XSServer: Identifiable, Hashable {
    let id: String
    let name: String
    let quality: String
    let provider: String?
}

@MainActor
private final class XSPlayerModel: ObservableObject {
    @Published var current: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var muted = false
    @Published var ready = false
    @Published var caption = ""
    @Published var subtitles: [XSSubtitle] = []
    @Published var selectedSubtitle: Int? = nil
    @Published var servers: [XSServer] = [
        XSServer(id: "auto", name: "Auto", quality: "AUTO", provider: "auto"),
        XSServer(id: "barbarian", name: "Barbarian", quality: "", provider: "barbarian"),
        XSServer(id: "archer", name: "Archer", quality: "", provider: "archer"),
        XSServer(id: "goblin", name: "Goblin", quality: "", provider: "goblin")
    ]
    @Published var activeServer = "Auto"
    @Published var activeQuality = "AUTO"
    @Published var error: String?

    weak var webView: WKWebView?
    var onProgress: ((Double, Double) -> Void)?

    func attach(_ webView: WKWebView) { self.webView = webView }
    func toggle() { send(["action": playing ? "pause" : "play"]) }
    func pause() { send(["action":"pause"]) }
    func seek(_ seconds: Double) { send(["action":"seek","time":max(0,seconds)]) }
    func seekBy(_ seconds: Double) { send(["action":"seekBy","seconds":seconds]) }
    func mute(_ value: Bool) { send(["action":"mute","muted":value]) }
    func pip() { send(["action":"pip"]) }
    func rate(_ value: Double) { send(["action":"rate","rate":value]) }
    func subtitle(_ index: Int?) { selectedSubtitle = index; send(["action":"subtitle","index":index ?? -1]) }
    func subtitleDelay(_ value: Double) { send(["action":"subtitleDelay","seconds":value]) }
    func metadata() { send(["action":"metadata"]) }
    func server(_ value: XSServer) {
        activeServer = value.name
        if !value.quality.isEmpty { activeQuality = value.quality }
        var p: [String:Any] = ["action":"server","name":value.name]
        if let provider = value.provider { p["provider"] = provider }
        send(p)
    }

    func reset() { current = 0; duration = 0; playing = false; ready = false; caption = ""; error = nil }

    func receive(_ payload: [String:Any]) {
        guard let event = payload["event"] as? String else { return }
        switch event {
        case "xs:ready": ready = true; error = nil
        case "xs:error": error = payload["message"] as? String ?? "Playback unavailable"
        case "xs:state", "frameXTV:timeupdate":
            if let v = number(payload["currentTime"]) { current = v }
            if let v = number(payload["duration"]) { duration = v }
            if let paused = payload["paused"] as? Bool { playing = !paused }
            if let m = payload["muted"] as? Bool { muted = m }
            if current > 0 || duration > 0 { ready = true; onProgress?(current,duration) }
        case "xs:caption": caption = payload["text"] as? String ?? ""
        case "xs:tracks":
            guard let list = payload["subtitles"] as? [[String:Any]] else { return }
            subtitles = list.compactMap { row in
                guard let id = integer(row["index"]) else { return nil }
                return XSSubtitle(id: id, label: row["label"] as? String ?? "", language: row["language"] as? String ?? "")
            }
        case "xs:servers":
            guard let list = payload["servers"] as? [[String:Any]] else { return }
            let parsed: [XSServer] = list.compactMap { row in
                let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return nil }
                let q = row["quality"] as? String ?? ""
                let p = row["provider"] as? String
                return XSServer(id: (p ?? name)+q, name: name, quality: q, provider: p)
            }
            if !parsed.isEmpty { servers = parsed }
        default: break
        }
    }

    private func send(_ payload: [String:Any]) {
        guard let webView,
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.xsCommand && window.xsCommand(\(json));")
    }
    private func number(_ x: Any?) -> Double? { if let n=x as? NSNumber { return n.doubleValue }; if let s=x as? String { return Double(s) }; return nil }
    private func integer(_ x: Any?) -> Int? { if let n=x as? NSNumber { return n.intValue }; if let s=x as? String { return Int(s) }; return nil }
}

private struct XSPlaybackWebView: UIViewRepresentable {
    let playback: FrameXTVPlayback
    let title: String
    let posterURL: URL?
    @ObservedObject var model: XSPlayerModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeUIView(context: Context) -> WKWebView {
        let cc = WKUserContentController()
        cc.add(context.coordinator, name: "xsTelemetry")
        cc.addUserScript(WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        let config = WKWebViewConfiguration()
        config.userContentController = cc
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.backgroundColor = .black
        web.isOpaque = false
        web.isUserInteractionEnabled = false
        model.attach(web)
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay]); try AVAudioSession.sharedInstance().setActive(true) } catch {}
        load(web)
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) { uiView.stopLoading(); uiView.configuration.userContentController.removeScriptMessageHandler(forName:"xsTelemetry") }

    private func load(_ web: WKWebView) {
        guard let u = playback.embedURL(title:title, posterURL:posterURL) else { return }
        let src = u.absoluteString.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"\"",with:"&quot;")
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no"><style>html,body{margin:0;width:100%;height:100%;background:#000;overflow:hidden}iframe{position:fixed;inset:0;width:100%;height:100%;border:0;pointer-events:none}</style></head><body><iframe id="engine" src="\(src)" allow="autoplay; fullscreen; picture-in-picture; encrypted-media" allowfullscreen></iframe><script>const e=document.getElementById('engine');window.xsCommand=function(p){try{e.contentWindow.postMessage({__xsCommand:p},'*')}catch(_){};try{e.contentWindow.postMessage(p,'*')}catch(_){}};</script></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string:"https://framextv.tech"))
    }

    private static let bridgeScript = #"""
    (function(){if(window.__xsV4)return;window.__xsV4=true;let v=null,sub=-1,delay=0,last='',tracks='',servers='';
    const B=o=>{try{window.webkit.messageHandlers.xsTelemetry.postMessage(o)}catch(_){}};
    const V=()=>{try{let a=[...document.querySelectorAll('video')];return a.sort((x,y)=>y.clientWidth*y.clientHeight-x.clientWidth*x.clientHeight)[0]||null}catch(_){return null}};
    function hide(){let x=v||V();if(!x)return;try{x.controls=false;x.setAttribute('playsinline','')}catch(_){};try{[...document.querySelectorAll('button,[role=button],[role=dialog]')].forEach(e=>{e.style.setProperty('display','none','important');e.style.setProperty('pointer-events','none','important')})}catch(_){}}
    function state(){let x=v||V();if(!x)return;B({event:'xs:state',currentTime:+(x.currentTime||0),duration:isFinite(x.duration)?+x.duration:0,paused:!!x.paused,muted:!!x.muted})}
    function reportTracks(){let x=v||V();if(!x||!x.textTracks)return;let a=[];for(let i=0;i<x.textTracks.length;i++){let t=x.textTracks[i];a.push({index:i,label:t.label||'',language:t.language||''})}let s=JSON.stringify(a);if(s!==tracks){tracks=s;B({event:'xs:tracks',subtitles:a})}}
    function caption(){let x=v||V();if(!x||!x.textTracks||sub<0||sub>=x.textTracks.length){if(last){last='';B({event:'xs:caption',text:''})}return}let t=x.textTracks[sub];try{t.mode='hidden'}catch(_){};let w=+(x.currentTime||0)+delay,text='';try{for(let c of (t.cues||[])){if(c.startTime<=w&&c.endTime>=w){text=c.text||'';break}if(c.startTime>w)break}}catch(_){};if(text!==last){last=text;B({event:'xs:caption',text})}}
    function scan(){let a=[],seen=new Set();try{[...document.querySelectorAll('button,[role=button],li,div')].forEach(e=>{let t=String(e.innerText||e.textContent||'').replace(/\s+/g,' ').trim();if(!t||t.length>90||!/(Connected|Available|4K|FHD|UHD|1080p|720p|HD)/i.test(t))return;let m=t.match(/(4K|UHD|FHD|1080p|720p|HD)/i),q=m?m[1].toUpperCase():'';let n=t.replace(/Connected|Available|4K|UHD|FHD|1080p|720p|HD/ig,'').replace(/\s+/g,' ').trim();if(!n||seen.has(n.toLowerCase()))return;seen.add(n.toLowerCase());a.push({name:n,quality:q})})}catch(_){};if(a.length){let s=JSON.stringify(a);if(s!==servers){servers=s;B({event:'xs:servers',servers:a})}}}
    function install(x){if(!x||v===x)return;v=x;try{x.controls=false}catch(_){};['timeupdate','durationchange','loadedmetadata','play','pause','volumechange','ended','canplay'].forEach(n=>{try{x.addEventListener(n,state,{passive:true})}catch(_){}});B({event:'xs:ready'});state();reportTracks();hide();scan()}
    function cmd(p){let x=v||V(),a=p&&p.action;try{if(a==='play'&&x)x.play();else if(a==='pause'&&x)x.pause();else if(a==='seek'&&x)x.currentTime=Math.max(0,+p.time||0);else if(a==='seekBy'&&x)x.currentTime=Math.max(0,+(x.currentTime||0)+(+p.seconds||0));else if(a==='mute'&&x)x.muted=!!p.muted;else if(a==='rate'&&x)x.playbackRate=+p.rate||1;else if(a==='pip'&&x){if(x.webkitSetPresentationMode)x.webkitSetPresentationMode('picture-in-picture');else if(x.requestPictureInPicture)x.requestPictureInPicture()}else if(a==='subtitleDelay')delay=+p.seconds||0;else if(a==='subtitle'&&x&&x.textTracks){sub=+p.index;for(let i=0;i<x.textTracks.length;i++){try{x.textTracks[i].mode=i===sub?'hidden':'disabled'}catch(_){}}}else if(a==='server'&&p.provider)window.postMessage({action:'setProvider',provider:p.provider},'*');else if(a==='metadata'){reportTracks();scan()}}catch(_){};state()}
    addEventListener('message',e=>{try{if(e.data&&e.data.__xsCommand)cmd(e.data.__xsCommand)}catch(_){}});new MutationObserver(()=>{let x=V();if(x)install(x);hide()}).observe(document.documentElement||document.body,{subtree:true,childList:true});setInterval(()=>{let x=V();if(x)install(x);hide();state();reportTracks();caption();scan()},300);setTimeout(()=>{if(!V())B({event:'xs:error',message:'Waiting for playback engine…'})},9000);
    })();
    """#

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let model: XSPlayerModel
        init(model: XSPlayerModel) { self.model = model }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { guard let p=message.body as? [String:Any] else{return}; Task{@MainActor in model.receive(p)} }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy)->Void) { decisionHandler(.allow) }
    }
}

private struct XSAirPlayPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let v=AVRoutePickerView();v.prioritizesVideoDevices=true;v.tintColor=.white;v.activeTintColor=.white;return v }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct FrameXTVPlayerScreen: View {
    let item: MediaItem
    let playback: FrameXTVPlayback
    let nextPlayback: FrameXTVPlayback?
    let nextLabel: String?
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = XSPlayerModel()
    @State private var active: FrameXTVPlayback
    @State private var queued: FrameXTVPlayback?
    @State private var queuedLabel: String?
    @State private var controls = true
    @State private var showSubs = false
    @State private var showServers = false
    @State private var showSettings = false
    @State private var scrubbing = false
    @State private var scrub: Double = 0
    @State private var hideTask: Task<Void,Never>?
    @State private var resolvingNext = false
    @State private var advancing = false
    @AppStorage("XSTV.autoNextEpisode") private var autoNext = true
    @AppStorage("XSTV.subtitleFontScale") private var subScale = 1.0
    @AppStorage("XSTV.subtitleBottomPadding") private var subBottom = 76.0
    @AppStorage("XSTV.subtitleDelay") private var subDelay = 0.0
    @AppStorage("XSTV.subtitleBackground") private var subBackground = true

    init(item: MediaItem, playback: FrameXTVPlayback, nextPlayback: FrameXTVPlayback?=nil, nextLabel:String?=nil) {
        self.item=item; self.playback=playback; self.nextPlayback=nextPlayback; self.nextLabel=nextLabel
        var p=playback;p.showEmbeddedControls=false;_active=State(initialValue:p);_queued=State(initialValue:nextPlayback);_queuedLabel=State(initialValue:nextLabel)
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                Color.black.ignoresSafeArea()
                XSPlaybackWebView(playback: active, title: title, posterURL: item.imageURL(backdrop:true,width:1280) ?? item.imageURL(width:780), model:model)
                    .id(active.id).ignoresSafeArea().allowsHitTesting(false)

                Rectangle().fill(Color.clear).contentShape(Rectangle()).ignoresSafeArea()
                    .onTapGesture { revealControls() }

                if !model.caption.isEmpty { caption(width:g.size.width) }
                if controls { controlLayer(g).transition(.opacity) }
                if !model.ready { loading }
                if shouldShowNext { VStack{Spacer();HStack{Spacer();nextPrompt}.padding(.trailing,28).padding(.bottom,96)} }
            }
        }
        .toolbar(.hidden, for:.navigationBar).toolbar(.hidden,for:.tabBar).statusBarHidden(true)
        .onAppear { installProgress(); model.subtitleDelay(subDelay); controls=true; scheduleHide(); Task{await resolveNext()} }
        .onChange(of:model.playing){ playing in if playing { scheduleHide() } else { hideTask?.cancel(); controls=true } }
        .onChange(of:model.current){ _ in handleProgress() }
        .onChange(of:subDelay){ model.subtitleDelay($0) }
        .onDisappear { hideTask?.cancel();model.pause();model.onProgress=nil }
        .sheet(isPresented:$showSubs,onDismiss:{revealControls()}){subSheet}
        .sheet(isPresented:$showServers,onDismiss:{revealControls()}){serverSheet}
        .sheet(isPresented:$showSettings,onDismiss:{revealControls()}){settingsSheet}
    }

    private var title:String { if let s=active.season,let e=active.episode{return "\(item.title) · S\(s) E\(e)"};return item.title }

    private func controlLayer(_ g: GeometryProxy)->some View {
        ZStack {
            LinearGradient(colors:[.black.opacity(0.62),.clear,.black.opacity(0.7)],startPoint:.top,endPoint:.bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                HStack(spacing:12) {
                    circle("xmark"){dismiss()}
                    VStack(alignment:.leading,spacing:3){Text(item.title).font(.headline.bold()).lineLimit(1);if let s=active.season,let e=active.episode{Text("S\(s) · E\(e)").font(.caption).foregroundStyle(.white.opacity(0.65))}}
                    Spacer()
                    Button{showServers=true;model.metadata();holdControls()}{Text(model.activeQuality).font(.caption.bold()).padding(.horizontal,12).frame(height:42).background(.black.opacity(0.45),in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).stroke(.white.opacity(0.16)))}.buttonStyle(.plain)
                    Button{showSubs=true;model.metadata();holdControls()}{Image(systemName:"captions.bubble.fill").font(.system(size:19,weight:.semibold)).frame(width:44,height:42).background(.black.opacity(0.45),in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).stroke(.white.opacity(0.16)))}.buttonStyle(.plain)
                    Button{showSettings=true;holdControls()}{Image(systemName:"ellipsis").font(.system(size:20,weight:.bold)).frame(width:44,height:42).background(.black.opacity(0.45),in:RoundedRectangle(cornerRadius:13)).overlay(RoundedRectangle(cornerRadius:13).stroke(.white.opacity(0.16)))}.buttonStyle(.plain)
                }.foregroundStyle(.white).padding(.horizontal,22).padding(.top,max(g.safeAreaInsets.top,14))
                Spacer()
                HStack(spacing:52){Button{model.seekBy(-10);revealControls()}{Image(systemName:"gobackward.10").font(.system(size:38,weight:.medium))};Button{model.toggle();revealControls()}{Image(systemName:model.playing ? "pause.fill":"play.fill").font(.system(size:44,weight:.bold)).frame(width:88,height:88).background(.ultraThinMaterial,in:Circle()).overlay(Circle().stroke(.white.opacity(0.22)))};Button{model.seekBy(10);revealControls()}{Image(systemName:"goforward.10").font(.system(size:38,weight:.medium))}}.foregroundStyle(.white)
                Spacer()
                VStack(spacing:11){
                    HStack(spacing:12){Text(time(scrubbing ? scrub:model.current)).font(.caption.monospacedDigit()).frame(width:58,alignment:.leading);Slider(value:Binding(get:{scrubbing ? scrub:model.current},set:{scrub=$0}),in:0...max(model.duration,1),onEditingChanged:{editing in scrubbing=editing;if editing{scrub=model.current;holdControls()}else{model.seek(scrub);revealControls()}}).tint(.white);Text("−"+time(max(model.duration-(scrubbing ? scrub:model.current),0))).font(.caption.monospacedDigit()).frame(width:62,alignment:.trailing)}
                    HStack{Button{model.mute(!model.muted);revealControls()}{Image(systemName:model.muted ? "speaker.slash.fill":"speaker.wave.2.fill")};Text(model.activeServer).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.65));Spacer();XSAirPlayPicker().frame(width:35,height:35);Button{model.pip();revealControls()}{Image(systemName:"pip.enter")}}
                }.foregroundStyle(.white).padding(.horizontal,28).padding(.bottom,max(g.safeAreaInsets.bottom,18))
            }
        }
    }

    private func caption(width:CGFloat)->some View { VStack{Spacer();Text(model.caption).font(.system(size:max(18,min(width*0.028,34))*subScale,weight:.semibold)).multilineTextAlignment(.center).foregroundStyle(.white).padding(.horizontal,13).padding(.vertical,subBackground ? 7:0).background(subBackground ? Color.black.opacity(0.68):Color.clear,in:RoundedRectangle(cornerRadius:7)).shadow(color:.black.opacity(0.9),radius:2).padding(.horizontal,width*0.12).padding(.bottom,subBottom)}.allowsHitTesting(false) }
    private var loading:some View { VStack(spacing:14){ProgressView().tint(.white).scaleEffect(1.15);Text(model.error ?? "Loading video…").font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.7))}.padding(22).background(.black.opacity(0.42),in:RoundedRectangle(cornerRadius:20)).allowsHitTesting(false) }

    private var serverSheet:some View { NavigationStack{List{ForEach(model.servers){s in Button{model.server(s);showServers=false}{HStack{Text(s.name).font(.headline);Spacer();if !s.quality.isEmpty{Text(s.quality).font(.caption.bold()).foregroundStyle(.orange)}}.contentShape(Rectangle())}.buttonStyle(.plain)}}.navigationTitle("Servers & Quality").navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark).task{model.metadata()}}.presentationDetents([.medium,.large]) }
    private var subSheet:some View { NavigationStack{Form{Section("Subtitles"){Button{model.subtitle(nil);showSubs=false}{HStack{Text("Off");Spacer();if model.selectedSubtitle==nil{Image(systemName:"checkmark")}}};ForEach(model.subtitles){s in Button{model.subtitle(s.id);showSubs=false}{HStack{Text(s.displayName);Spacer();if model.selectedSubtitle==s.id{Image(systemName:"checkmark")}}}};Section("Appearance"){VStack(alignment:.leading){Text("Size · \(Int(subScale*100))%");Slider(value:$subScale,in:0.7...1.6,step:0.1)};VStack(alignment:.leading){Text("Position");Slider(value:$subBottom,in:38...180,step:4)};VStack(alignment:.leading){Text(String(format:"Timing · %+.1fs",subDelay));Slider(value:$subDelay,in:-5...5,step:0.25)};Toggle("Background",isOn:$subBackground)}}.navigationTitle("Subtitles").navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark).task{model.metadata()}}.presentationDetents([.medium,.large]) }
    private var settingsSheet:some View { NavigationStack{Form{Section("Playback Speed"){Picker("Speed",selection:Binding(get:{1.0},set:{model.rate($0)})){Text("0.5×").tag(0.5);Text("1×").tag(1.0);Text("1.25×").tag(1.25);Text("1.5×").tag(1.5);Text("2×").tag(2.0)}.pickerStyle(.segmented)};Section("Episodes"){Toggle("Auto Play Next Episode",isOn:$autoNext)}}.navigationTitle("Player Settings").navigationBarTitleDisplayMode(.inline).preferredColorScheme(.dark)}.presentationDetents([.medium]) }

    private func circle(_ symbol:String,_ action:@escaping()->Void)->some View { Button(action:action){Image(systemName:symbol).font(.system(size:18,weight:.bold)).frame(width:44,height:44).background(.black.opacity(0.45),in:Circle()).overlay(Circle().stroke(.white.opacity(0.16)))}.buttonStyle(.plain).foregroundStyle(.white) }
    private func time(_ x:Double)->String { guard x.isFinite,x>=0 else{return "0:00"};let t=Int(x);let h=t/3600,m=(t%3600)/60,s=t%60;return h>0 ? String(format:"%d:%02d:%02d",h,m,s):String(format:"%d:%02d",m,s) }

    private func holdControls(){ hideTask?.cancel(); if !controls { withAnimation(.easeInOut(duration:0.15)){controls=true} } }
    private func revealControls(){ hideTask?.cancel(); withAnimation(.easeInOut(duration:0.15)){controls=true}; scheduleHide() }
    private func scheduleHide(){ hideTask?.cancel(); guard controls,model.playing,!showSubs,!showServers,!showSettings,!scrubbing else{return};hideTask=Task{try? await Task.sleep(nanoseconds:5_000_000_000);if !Task.isCancelled{await MainActor.run{if model.playing && !showSubs && !showServers && !showSettings && !scrubbing{withAnimation(.easeOut(duration:0.2)){controls=false}}}}} }

    private var shouldShowNext:Bool { queued != nil && model.duration>0 && model.duration-model.current<=22 && model.duration-model.current>0 }
    private var nextPrompt:some View { VStack(alignment:.leading,spacing:7){Text("UP NEXT").font(.caption2.bold()).tracking(1.8).foregroundStyle(.white.opacity(0.58));Text(queuedLabel ?? "Next Episode").font(.subheadline.bold());HStack{if autoNext{Text("Playing soon").font(.caption).foregroundStyle(.white.opacity(0.66))};Button("Play Now"){playNext()}.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)}}.padding(16).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:20)).overlay(RoundedRectangle(cornerRadius:20).stroke(.white.opacity(0.12))) }
    private func installProgress(){ model.onProgress={c,d in library.updateProgress(item:item,season:active.season,episode:active.episode,current:c,duration:d)} }
    private func handleProgress(){ guard autoNext,queued != nil,model.duration>0,model.duration-model.current<=1.2,!advancing else{return};playNext() }
    @MainActor private func resolveNext() async { guard queued==nil,!resolvingNext,item.kind != .movie,let s=active.season,let e=active.episode else{return};resolvingNext=true;defer{resolvingNext=false};do{let eps=try await app.episodes(tmdbID:item.tmdbID,season:s);if let i=eps.firstIndex(where:{$0.episodeNumber==e}),eps.indices.contains(i+1){let n=eps[i+1];queued=FrameXTVPlayback(tmdbID:item.tmdbID,season:s,episode:n.episodeNumber);queuedLabel="S\(s) · E\(n.episodeNumber)  \(n.name)";return};let seasons=try await app.seasons(for:item);guard let ns=seasons.map(\.seasonNumber).filter({$0>s}).sorted().first else{return};let ne=try await app.episodes(tmdbID:item.tmdbID,season:ns);guard let f=ne.first else{return};queued=FrameXTVPlayback(tmdbID:item.tmdbID,season:ns,episode:f.episodeNumber);queuedLabel="S\(ns) · E\(f.episodeNumber)  \(f.name)"}catch{}}
    private func playNext(){guard var n=queued else{return};advancing=true;n.showEmbeddedControls=false;model.pause();model.reset();active=n;queued=nil;queuedLabel=nil;controls=true;Task{try? await Task.sleep(nanoseconds:500_000_000);await resolveNext();await MainActor.run{advancing=false;revealControls()}}}
}
