import SwiftUI
import UIKit
import AVFoundation
import VLCKitSPM

struct CaptionCue {
    let start: Double
    let end: Double
    let text: String
}

// SRT and WebVTT are rendered above the native VLC surface, so they do not
// disappear when the phone rotates or the transport controls are hidden.
enum CaptionParser {
    static func parse(_ content: String) -> [CaptionCue] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let arrow = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let columns = lines[arrow].components(separatedBy: "-->")
            guard columns.count == 2,
                  let start = time(columns[0]), let end = time(columns[1]), end > start else { return nil }
            let text = lines.dropFirst(arrow + 1).joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : CaptionCue(start: start, end: end, text: text)
        }
    }

    private static func time(_ value: String) -> Double? {
        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespaces).first?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        let parts = compact.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }
}

struct EmbeddedTrack: Identifiable {
    let id: Int
    let name: String
}

@MainActor
final class NativeVLCPlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    let sources: [VideoSource]
    let subtitles: [SubtitleSource]
    let contentID: String

    @Published var sourceIndex = 0
    @Published var time = 0.0
    @Published var duration = 0.0
    @Published var playing = false
    @Published var connecting = true
    @Published var errorText: String?
    @Published var externalCaption = ""
    @Published var captionName = "إيقاف الترجمة"
    @Published var embeddedTracks: [EmbeddedTrack] = []
    @Published var audioTracks: [EmbeddedTrack] = []
    @Published var selectedCaptionID: String?
    @Published var captionSize: CGFloat = 22
    @Published var captionBottom: CGFloat = 12
    @Published var captionOpacity = 0.50
    @Published var captionDelay = 0.0
    @Published var fillVideo = false
    @Published var speed = 1.0

    private var cues: [CaptionCue] = []
    private var activeExternal: SubtitleSource?
    private var captionTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var progressCheckpoint = 0.0
    private var generation = 0
    private var pendingSeek = 0.0
    private var stopped = false

    init(entry: PlaybackEntry, contentID: String) {
        self.sources = entry.sources.filter(\.isSupported)
        self.subtitles = entry.subtitles
        self.contentID = contentID
        super.init()
        player.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        if !sources.isEmpty {
            let saved = UserDefaults.standard.double(forKey: "gemflix.progress.\(contentID)")
            playSource(0, resumeAt: saved)
        } else {
            connecting = false
            errorText = "ما فيه رابط فيديو مباشر متاح لهذا العنوان."
        }
    }

    func playSource(_ index: Int, resumeAt: Double? = nil) {
        guard sources.indices.contains(index), !stopped else { return }
        generation += 1
        let token = generation
        timeoutTask?.cancel()
        let resume = resumeAt ?? time
        pendingSeek = max(0, resume)
        sourceIndex = index
        connecting = true
        playing = false
        errorText = nil
        duration = 0
        embeddedTracks = []
        audioTracks = []
        player.stop()

        guard let media = VLCMedia(url: sources[index].url) else {
            nextSource(reason: "رابط السيرفر غير صالح")
            return
        }
        media.addOption(":http-reconnect")
        media.addOption(":network-caching=1000")
        player.media = media
        player.rate = Float(speed)
        player.play()

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 19_000_000_000)
            guard !Task.isCancelled, let self, !self.stopped,
                  self.generation == token, self.connecting else { return }
            self.nextSource(reason: "السيرفر ما استجاب خلال 19 ثانية")
        }
    }

    private func nextSource(reason: String) {
        timeoutTask?.cancel()
        if sources.indices.contains(sourceIndex + 1) {
            playSource(sourceIndex + 1)
        } else {
            connecting = false
            playing = false
            errorText = "\(reason). ما توفرت سيرفرات مباشرة أخرى."
        }
    }

    func togglePlay() {
        if player.isPlaying { player.pause(); playing = false }
        else { player.play() }
    }

    func seek(_ target: Double) {
        guard duration > 0 else { return }
        let clamped = max(0, min(target, duration))
        player.position = clamped / duration
        time = clamped
        updateCaption()
    }

    func skip(_ interval: Double) { seek(time + interval) }

    func setSpeed(_ next: Double) {
        speed = next
        player.rate = Float(next)
    }

    func adjustDelay(_ delta: Double) { captionDelay += delta; updateCaption() }
    func adjustPosition(_ delta: CGFloat) { captionBottom = min(150, max(1, captionBottom + delta)) }

    func refreshTracks() {
        let textTracks = Array(player.textTracks)
        embeddedTracks = textTracks.enumerated().map { EmbeddedTrack(id: $0.offset, name: $0.element.trackName) }
        let audio = Array(player.audioTracks)
        audioTracks = audio.enumerated().map { EmbeddedTrack(id: $0.offset, name: $0.element.trackName) }
        if activeExternal == nil && selectedCaptionID == nil,
           let arabic = textTracks.firstIndex(where: {
               let name = $0.trackName.lowercased()
               return name.contains("arabic") || name.contains("عرب") || name.contains("ara")
           }) {
            selectEmbedded(arabic)
        }
    }

    func selectEmbedded(_ index: Int) {
        let tracks = Array(player.textTracks)
        guard tracks.indices.contains(index) else { return }
        captionTask?.cancel()
        activeExternal = nil
        cues = []
        externalCaption = ""
        tracks[index].isSelectedExclusively = true
        selectedCaptionID = "embedded:\(index)"
        captionName = tracks[index].trackName
    }

    func selectAudio(_ index: Int) {
        let tracks = Array(player.audioTracks)
        guard tracks.indices.contains(index) else { return }
        tracks[index].isSelectedExclusively = true
        refreshTracks()
    }

    func selectExternal(_ track: SubtitleSource?) {
        captionTask?.cancel()
        for embedded in Array(player.textTracks) where embedded.isSelected {
            embedded.isSelected = false
        }
        activeExternal = track
        cues = []
        externalCaption = ""
        selectedCaptionID = track?.id
        captionName = track?.label ?? "إيقاف الترجمة"
        guard let track, track.url.scheme?.lowercased() == "https" else { return }
        captionTask = Task { [weak self] in
            do {
                var request = URLRequest(url: track.url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 18)
                request.setValue("text/vtt,text/plain,*/*", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode), data.count < 5_000_000,
                      !Task.isCancelled else { return }
                let parsed = CaptionParser.parse(String(data: data, encoding: .utf8) ?? "")
                guard let self, self.activeExternal?.id == track.id else { return }
                self.cues = parsed
                self.updateCaption()
                if parsed.isEmpty { self.captionName = "الترجمة غير قابلة للقراءة" }
            } catch {
                guard let self, self.activeExternal?.id == track.id else { return }
                self.captionName = "تعذّر تحميل الترجمة"
            }
        }
    }

    private func updateClock() {
        let seconds = Double(player.time.intValue) / 1000
        guard seconds.isFinite && seconds >= 0 else { return }
        time = seconds
        let remainder = abs(Double(player.remainingTime?.intValue ?? 0)) / 1000
        if remainder > 0 { duration = max(duration, time + remainder) }
        updateCaption()
        if time > 1 && time - progressCheckpoint >= 5 {
            progressCheckpoint = time
            UserDefaults.standard.set(time, forKey: "gemflix.progress.\(contentID)")
        }
    }

    private func updateCaption() {
        let seconds = time + captionDelay
        let active = cues.first(where: { seconds >= $0.start && seconds < $0.end })?.text ?? ""
        if active != externalCaption { externalCaption = active }
    }

    func close() {
        guard !stopped else { return }
        stopped = true
        generation += 1
        timeoutTask?.cancel()
        captionTask?.cancel()
        UserDefaults.standard.set(time, forKey: "gemflix.progress.\(contentID)")
        player.stop()
        player.delegate = nil
        player.drawable = nil
    }

    nonisolated func mediaPlayerStateChanged(_ state: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            switch state {
            case .playing:
                self.connecting = false
                self.playing = true
                self.timeoutTask?.cancel()
                let token = self.generation
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard let self, !self.stopped, self.generation == token else { return }
                    self.updateClock()
                    if self.pendingSeek > 3, self.duration > 0 {
                        self.seek(self.pendingSeek)
                        self.pendingSeek = 0
                    }
                    self.refreshTracks()
                    if let external = self.activeExternal {
                        self.selectExternal(external)
                    }
                }
            case .paused:
                self.playing = false
            case .buffering:
                if !self.playing { self.connecting = true }
            case .error:
                self.nextSource(reason: "فشل تشغيل السيرفر")
            default: break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.updateClock() }
    }
}

private struct VLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let host = UIView(frame: .zero)
        host.backgroundColor = .black
        host.isUserInteractionEnabled = false
        host.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        player.drawable = host
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        if player.drawable as AnyObject? !== host { player.drawable = host }
    }
}

enum PlayerOrientation {
    static func set(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        UIViewController.attemptRotationToDeviceOrientation()
    }
}

struct NativePlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: NativeVLCPlayerModel
    @State private var controls = true
    @State private var captionSettingsVisible = false
    @State private var dragging = false
    @State private var sliderTime = 0.0
    let title: String

    init(title: String, entry: PlaybackEntry) {
        self.title = title
        _model = StateObject(wrappedValue: NativeVLCPlayerModel(entry: entry, contentID: title))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                VLCVideoSurface(player: model.player)
                    .scaleEffect(model.fillVideo ? 1.18 : 1)
                    .ignoresSafeArea()

                // The caption overlay remains independent of player controls.
                if !model.externalCaption.isEmpty {
                    VStack {
                        Spacer()
                        Text(model.externalCaption)
                            .font(.system(size: model.captionSize, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.9), radius: 3)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(model.captionOpacity),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 22)
                            .padding(.bottom, max(1, model.captionBottom + geometry.safeAreaInsets.bottom))
                    }
                    .allowsHitTesting(false)
                }

                if controls {
                    LinearGradient(colors: [.black.opacity(0.8), .clear, .black.opacity(0.84)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea().allowsHitTesting(false)
                    VStack {
                        topBar
                        Spacer()
                        centralControls
                        Spacer()
                        bottomBar
                    }
                    .transition(.opacity)
                } else {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { controls = true } }
                }

                if model.connecting {
                    VStack(spacing: 12) {
                        ProgressView().tint(CinemaPalette.accent).scaleEffect(1.4)
                        Text("جارٍ الاتصال بالسيرفر…")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    }
                    .allowsHitTesting(false)
                }
            }
            .foregroundStyle(.white)
            .clipped()
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { PlayerOrientation.set(.landscape) }
        .onDisappear { model.close(); PlayerOrientation.set(.portrait) }
        .onReceive(model.$time) { value in if !dragging { sliderTime = value } }
        .sheet(isPresented: $captionSettingsVisible) { captionSettings }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { model.close(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.16), in: Circle())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                if model.sources.indices.contains(model.sourceIndex) {
                    Text("\(model.sources[model.sourceIndex].label) · \(model.sources[model.sourceIndex].quality)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.66))
                }
            }
            Spacer()
            Button { model.fillVideo.toggle() } label: {
                Image(systemName: model.fillVideo ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel("تكبير أو احتواء الصورة")
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var centralControls: some View {
        HStack(spacing: 46) {
            Button { model.skip(-10) } label: { Image(systemName: "gobackward.10") }
            Button { model.togglePlay() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 25, weight: .bold))
                    .frame(width: 61, height: 61)
                    .background(.white.opacity(0.20), in: Circle())
            }
            Button { model.skip(10) } label: { Image(systemName: "goforward.10") }
        }
        .font(.system(size: 26))
        .buttonStyle(.plain)
        .shadow(color: .black, radius: 7)
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            if let reason = model.errorText {
                HStack(spacing: 9) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    Text(reason).font(.system(size: 11))
                    Spacer()
                    Button("إعادة") { model.playSource(model.sourceIndex, resumeAt: model.time) }
                        .foregroundStyle(CinemaPalette.accent)
                }
                .padding(11)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 11) {
                Text(clock(sliderTime))
                Slider(value: $sliderTime, in: 0...max(model.duration, 1), onEditingChanged: { editing in
                    dragging = editing
                    if !editing { model.seek(sliderTime) }
                })
                .tint(CinemaPalette.accent)
                Text(clock(model.duration))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))

            HStack(spacing: 16) {
                Menu {
                    ForEach(Array(model.sources.enumerated()), id: \.offset) { index, source in
                        Button {
                            model.playSource(index)
                        } label: {
                            if model.sourceIndex == index { Label("\(source.label) · \(source.quality)", systemImage: "checkmark") }
                            else { Text("\(source.label) · \(source.quality)") }
                        }
                    }
                } label: { controlLabel("السيرفر", symbol: "server.rack") }

                Menu {
                    ForEach(Array(model.sources.enumerated()), id: \.offset) { index, source in
                        Button("\(source.quality) · \(source.label)") { model.playSource(index) }
                    }
                    Text("تغيير الجودة يعتمد على صيغ السيرفر المتاحة")
                } label: { controlLabel("الجودة", symbol: "slider.horizontal.3") }

                Menu {
                    Button("إيقاف الترجمة") { model.selectExternal(nil) }
                    if !model.embeddedTracks.isEmpty {
                        Section("داخل الفيديو") {
                            ForEach(model.embeddedTracks) { track in
                                Button(track.name) { model.selectEmbedded(track.id) }
                            }
                        }
                    }
                    if !model.subtitles.isEmpty {
                        Section("ترجمة خارجية") {
                            ForEach(model.subtitles) { subtitle in
                                Button(subtitle.label) { model.selectExternal(subtitle) }
                            }
                        }
                    }
                } label: { controlLabel("الترجمة", symbol: "captions.bubble") }

                Button { captionSettingsVisible = true } label: {
                    controlLabel("ضبط", symbol: "textformat.size")
                }

                Menu {
                    ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                        Button("\(speed.formatted())×") { model.setSpeed(speed) }
                    }
                    if !model.audioTracks.isEmpty {
                        Section("الصوت") {
                            ForEach(model.audioTracks) { track in
                                Button(track.name) { model.selectAudio(track.id) }
                            }
                        }
                    }
                } label: { controlLabel("المزيد", symbol: "ellipsis.circle") }

                Spacer(minLength: 0)
                Button { withAnimation(.easeInOut(duration: 0.2)) { controls = false } } label: {
                    Image(systemName: "eye.slash").font(.system(size: 15))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }

    private func controlLabel(_ label: String, symbol: String) -> some View {
        Label(label, systemImage: symbol)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
    }

    private var captionSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("الترجمة المحددة: \(model.captionName)")
                            .font(.subheadline).foregroundStyle(CinemaPalette.secondary)
                        Text("تزامن الترجمة")
                            .font(.headline)
                        Text("\(model.captionDelay.formatted(.number.precision(.fractionLength(1)))) ثانية")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundStyle(CinemaPalette.accent)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 8) {
                        ForEach([-60.0, -10.0, -1.0, -0.5, 0.5, 1.0, 10.0, 60.0], id: \.self) { value in
                            Button(value > 0 ? "+\(value.formatted())" : value.formatted()) {
                                model.adjustDelay(value)
                            }
                            .font(.system(size: 11, weight: .bold))
                            .buttonStyle(.bordered)
                        }
                    }
                    .minimumScaleFactor(0.7)
                    Button("تصفير التوقيت") { model.captionDelay = 0; model.adjustDelay(0) }
                        .foregroundStyle(CinemaPalette.accent)
                    Divider()
                    Text("حجم الترجمة · \(Int(model.captionSize)) pt")
                    Slider(value: $model.captionSize, in: 14...40, step: 1).tint(CinemaPalette.accent)
                    Text("موضع الترجمة · \(Int(model.captionBottom)) pt")
                    HStack(spacing: 13) {
                        Button("أسفل −1") { model.adjustPosition(-1) }
                        Button("أعلى +1") { model.adjustPosition(1) }
                    }
                    .buttonStyle(.bordered)
                    Slider(value: $model.captionBottom, in: 1...150, step: 1).tint(CinemaPalette.accent)
                    Text("خلفية الترجمة · \(Int(model.captionOpacity * 100))%")
                    Slider(value: $model.captionOpacity, in: 0...1).tint(CinemaPalette.accent)
                    Text("إعدادات الحجم والموضع والخلفية تنطبق على الترجمة الخارجية المعروضة فوق الفيديو. الترجمات المدمجة يتحكم VLC في رسمها.")
                        .font(.system(size: 12))
                        .foregroundStyle(CinemaPalette.secondary)
                }
                .padding(23)
            }
            .background(CinemaPalette.base)
            .foregroundStyle(.white)
            .navigationTitle("إعدادات الترجمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("تم") { captionSettingsVisible = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func clock(_ value: Double) -> String {
        let seconds = Int(max(0, value.isFinite ? value : 0))
        let hours = seconds / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, seconds % 3600 / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
