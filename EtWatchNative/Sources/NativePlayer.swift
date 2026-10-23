import SwiftUI
import AVFoundation
import UIKit

private struct SubtitleCue {
    let start: Double
    let end: Double
    let text: String
}

private enum SubtitleParser {
    static func parse(_ contents: String) -> [(Double, Double, String)] {
        let normalized = contents.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized.components(separatedBy: "\n\n").compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let index = lines.firstIndex(where: { $0.contains("-->") }) else { return nil }
            let times = lines[index].components(separatedBy: "-->")
            guard times.count == 2,
                  let start = timestamp(times[0]), let end = timestamp(times[1]), end > start else {
                return nil
            }
            let raw = lines.dropFirst(index + 1).joined(separator: "\n")
            let plain = raw.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return plain.isEmpty ? nil : (start, end, plain)
        }
    }

    private static func timestamp(_ text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: " ").first?
            .replacingOccurrences(of: ",", with: ".") ?? ""
        let parts = clean.split(separator: ":").compactMap { Double($0) }
        guard (parts.count == 2 || parts.count == 3) else { return nil }
        if parts.count == 2 { return parts[0] * 60 + parts[1] }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
}

@MainActor
final class NativePlayerModel: ObservableObject {
    let player = AVPlayer()
    let sources: [VideoSource]
    let subtitles: [SubtitleSource]

    @Published var sourceIndex = 0
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var playing = false
    @Published var loading = true
    @Published var errorMessage: String?
    @Published var subtitleText = ""
    @Published var subtitleLabel = "إيقاف الترجمة"
    @Published var embeddedNames: [String] = []
    @Published var captionSize: CGFloat = 22
    @Published var captionBottom: CGFloat = 24
    @Published var backgroundOpacity: Double = 0.55
    @Published var delay: Double = 0
    @Published var fillVideo = false
    @Published var preferredQuality = 0

    private var parsedCues: [SubtitleCue] = []
    private var externalTrackID: String?
    private var embedGroup: AVMediaSelectionGroup?
    private var embedOptions: [AVMediaSelectionOption] = []
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var stalledObserver: NSObjectProtocol?
    private var subtitleTask: Task<Void, Never>?
    private var failoverTask: Task<Void, Never>?
    private var sourceGeneration = 0

    init(entry: PlaybackEntry) {
        sources = entry.sources
        subtitles = entry.subtitles
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = true
        do { try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback) }
        catch { errorMessage = "تعذّر تفعيل صوت التشغيل." }

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.15, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.tick(time) }
        }
        selectSource(0, resumeAt: 0)
    }

    private func tick(_ time: CMTime) {
        if time.seconds.isFinite { position = max(0, time.seconds) }
        if let length = player.currentItem?.duration.seconds, length.isFinite { duration = max(0, length) }
        playing = player.rate > 0
        let captionTime = position + delay
        let caption = parsedCues.first { captionTime >= $0.start && captionTime < $0.end }?.text ?? ""
        if subtitleText != caption { subtitleText = caption }
        if position > 0.35 { loading = false; failoverTask?.cancel() }
    }

    func selectSource(_ index: Int, resumeAt: Double? = nil) {
        guard sources.indices.contains(index) else { return }
        sourceGeneration += 1
        let generation = sourceGeneration
        let resume = resumeAt ?? position
        sourceIndex = index
        position = 0
        loading = true
        errorMessage = nil
        statusObservation = nil
        failoverTask?.cancel()
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        let item = AVPlayerItem(url: sources[index].url)
        item.preferredPeakBitRate = bitrateCap
        player.replaceCurrentItem(with: item)
        embedGroup = nil
        embedOptions = []
        embeddedNames = []

        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observed, _ in
            Task { @MainActor [weak self] in
                guard let self, self.sourceGeneration == generation, self.player.currentItem === observed else { return }
                if observed.status == .readyToPlay {
                    if resume > 1 { self.player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) }
                    self.player.play()
                    await self.loadEmbeddedCaptions(item, generation: generation)
                } else if observed.status == .failed {
                    self.failover(after: observed.error?.localizedDescription ?? "السيرفر لم يبدأ التشغيل.")
                }
            }
        }
        stalledObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemPlaybackStalled,
                                                                  object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.failover(after: "توقف بث السيرفر.")
            }
        }
        failoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            guard !Task.isCancelled, let self, self.sourceGeneration == generation,
                  self.position < 0.35, self.loading else { return }
            self.failover(after: "السيرفر لم يستجب خلال 18 ثانية.")
        }
    }

    private func failover(after reason: String) {
        guard loading || player.timeControlStatus != .playing else { return }
        if sourceIndex + 1 < sources.count {
            selectSource(sourceIndex + 1)
        } else {
            loading = false
            errorMessage = reason + " جرّب سيرفرًا آخر أو أعد المحاولة."
        }
    }

    private func loadEmbeddedCaptions(_ item: AVPlayerItem, generation: Int) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
              self.sourceGeneration == generation else { return }
        embedGroup = group
        embedOptions = group.options
        embeddedNames = group.options.map(\.displayName)
    }

    private var bitrateCap: Double {
        switch preferredQuality {
        case 1: 6_000_000
        case 2: 3_000_000
        case 3: 1_200_000
        default: 0
        }
    }

    func setQuality(_ selection: Int) {
        preferredQuality = selection
        player.currentItem?.preferredPeakBitRate = bitrateCap
    }

    func selectEmbedded(_ index: Int) {
        guard embedOptions.indices.contains(index), let group = embedGroup else { return }
        subtitleTask?.cancel()
        parsedCues = []
        subtitleText = ""
        externalTrackID = nil
        player.currentItem?.select(embedOptions[index], in: group)
        subtitleLabel = embeddedNames[index]
    }

    func selectExternal(_ track: SubtitleSource?) {
        subtitleTask?.cancel()
        if let group = embedGroup { player.currentItem?.select(nil, in: group) }
        parsedCues = []
        subtitleText = ""
        externalTrackID = track?.id
        guard let track else {
            subtitleLabel = "إيقاف الترجمة"
            return
        }
        subtitleLabel = track.label
        subtitleTask = Task { [weak self] in
            do {
                var request = URLRequest(url: track.url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)
                request.setValue("text/vtt,text/plain,*/*", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      200..<300 ~= http.statusCode, data.count < 4_000_000 else { throw AppAPIError.invalidResponse }
                let content = String(data: data, encoding: .utf8) ?? ""
                let cues = SubtitleParser.parse(content).map {
                    SubtitleCue(start: $0.0, end: $0.1, text: $0.2)
                }
                guard !Task.isCancelled, let self, self.externalTrackID == track.id else { return }
                self.parsedCues = cues
                if cues.isEmpty { self.errorMessage = "تعذّر قراءة ملف الترجمة المختار." }
            } catch {
                guard !Task.isCancelled, let self, self.externalTrackID == track.id else { return }
                self.errorMessage = "تعذّر تحميل الترجمة. جرّب مسارًا آخر."
            }
        }
    }

    func togglePlay() { playing ? player.pause() : player.play(); playing.toggle() }
    func seek(_ seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func skip(_ seconds: Double) { seek(min(max(position + seconds, 0), duration > 0 ? duration : position + 10)) }
    func adjustDelay(_ amount: Double) { delay += amount }
    func adjustPosition(_ amount: CGFloat) { captionBottom = max(1, min(130, captionBottom + amount)) }
    func retry() { selectSource(sourceIndex) }

    func close() {
        failoverTask?.cancel()
        subtitleTask?.cancel()
        player.pause()
        statusObservation = nil
        if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
        stalledObserver = nil
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }
}

private final class VideoLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct NativeVideoSurface: UIViewRepresentable {
    let player: AVPlayer
    let fill: Bool

    func makeUIView(context: Context) -> VideoLayerView {
        let view = VideoLayerView()
        view.backgroundColor = .black
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: VideoLayerView, context: Context) {
        view.playerLayer.player = player
        view.playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
}

struct NativePlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: NativePlayerModel
    @State private var controlsVisible = true
    @State private var showingCaptionSettings = false
    @State private var seekPosition = 0.0
    @State private var dragging = false

    let title: String

    init(title: String, entry: PlaybackEntry) {
        self.title = title
        _model = StateObject(wrappedValue: NativePlayerModel(entry: entry))
    }

    var body: some View {
        GeometryReader { screen in
            ZStack {
                Color.black.ignoresSafeArea()
                NativeVideoSurface(player: model.player, fill: model.fillVideo)
                    .ignoresSafeArea()

                if !model.subtitleText.isEmpty {
                    VStack {
                        Spacer()
                        Text(model.subtitleText)
                            .font(.system(size: model.captionSize, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.95), radius: 3)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(model.backgroundOpacity), in: RoundedRectangle(cornerRadius: 5))
                            .padding(.horizontal, 22)
                            .padding(.bottom, max(model.captionBottom, screen.safeAreaInsets.bottom + 1))
                    }
                    .allowsHitTesting(false)
                }

                if controlsVisible {
                    LinearGradient(colors: [.black.opacity(0.78), .clear, .black.opacity(0.78)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    VStack(spacing: 0) {
                        topControls
                        Spacer()
                        centralControls
                        Spacer()
                        bottomControls
                    }
                    .transition(.opacity)
                } else {
                    Color.clear.contentShape(Rectangle()).onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = true }
                    }
                }

                if model.loading {
                    VStack(spacing: 12) {
                        ProgressView().tint(CinemaPalette.accent).scaleEffect(1.25)
                        Text("جارٍ الاتصال بالسيرفر…")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.83))
                    }
                    .allowsHitTesting(false)
                }
            }
            .foregroundStyle(.white)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .background(Color.black.ignoresSafeArea())
        .onReceive(model.$position) { value in if !dragging { seekPosition = value } }
        .onDisappear { model.close() }
        .sheet(isPresented: $showingCaptionSettings) { captionSettings }
    }

    private var topControls: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text("\(model.sources[model.sourceIndex].label) · \(model.sources[model.sourceIndex].quality)")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.66))
            }
            Spacer(minLength: 2)
            Button { model.fillVideo.toggle() } label: {
                Image(systemName: model.fillVideo ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .accessibilityLabel("ملء الشاشة")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
    }

    private var centralControls: some View {
        HStack(spacing: 46) {
            Button { model.skip(-10) } label: { Image(systemName: "gobackward.10") }
            Button { model.togglePlay() } label: {
                Image(systemName: model.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .frame(width: 62, height: 62)
                    .background(.white.opacity(0.20), in: Circle())
            }
            Button { model.skip(10) } label: { Image(systemName: "goforward.10") }
        }
        .font(.system(size: 26, weight: .medium))
        .buttonStyle(.plain)
        .shadow(color: .black, radius: 8)
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            if let errorMessage = model.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(errorMessage).font(.system(size: 11)).lineLimit(3)
                    Spacer(minLength: 0)
                    Button("إعادة المحاولة") { model.retry() }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CinemaPalette.accent)
                }
                .padding(11)
                .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
            }

            HStack(spacing: 11) {
                Text(clock(seekPosition))
                Slider(value: $seekPosition, in: 0...max(model.duration, 1), onEditingChanged: { editing in
                    dragging = editing
                    if !editing { model.seek(seekPosition) }
                })
                .tint(CinemaPalette.accent)
                Text(clock(model.duration))
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))

            HStack(spacing: 14) {
                Menu {
                    ForEach(Array(model.sources.enumerated()), id: \.offset) { index, source in
                        Button {
                            model.selectSource(index)
                        } label: {
                            if model.sourceIndex == index {
                                Label("\(source.label) · \(source.quality)", systemImage: "checkmark")
                            } else { Text("\(source.label) · \(source.quality)") }
                        }
                    }
                } label: { menuLabel("سيرفر", icon: "server.rack") }

                Menu {
                    Button("Auto") { model.setQuality(0) }
                    Button("High · 6 Mbps") { model.setQuality(1) }
                    Button("Medium · 3 Mbps") { model.setQuality(2) }
                    Button("Data saver · 1.2 Mbps") { model.setQuality(3) }
                } label: { menuLabel("الجودة", icon: "slider.horizontal.3") }

                Menu {
                    Button("إيقاف الترجمة") { model.selectExternal(nil) }
                    if !model.embeddedNames.isEmpty {
                        Section("الترجمة المدمجة") {
                            ForEach(Array(model.embeddedNames.enumerated()), id: \.offset) { index, name in
                                Button(name) { model.selectEmbedded(index) }
                            }
                        }
                    }
                    if !model.subtitles.isEmpty {
                        Section("الترجمات الخارجية") {
                            ForEach(model.subtitles) { track in
                                Button(track.label) { model.selectExternal(track) }
                            }
                        }
                    }
                } label: { menuLabel("الترجمة", icon: "captions.bubble") }

                Button { showingCaptionSettings = true } label: {
                    menuLabel("ضبط", icon: "textformat.size")
                }
                Spacer(minLength: 1)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { controlsVisible = false }
                } label: {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 15))
                }
                .accessibilityLabel("إخفاء الأزرار")
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 9)
    }

    private func menuLabel(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
    }

    private var captionSettings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    Text("توقيت الترجمة")
                        .font(.headline)
                    Text("\(model.delay.formatted(.number.precision(.fractionLength(1)))) ثانية")
                        .font(.title2.monospacedDigit().bold())
                        .foregroundStyle(CinemaPalette.accent)
                    HStack(spacing: 9) {
                        ForEach([-10.0, -1.0, 1.0, 10.0], id: \.self) { value in
                            Button(value > 0 ? "+\(Int(value))" : "\(Int(value))") {
                                model.adjustDelay(value)
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    Button("تصفير التوقيت") { model.delay = 0 }
                        .foregroundStyle(CinemaPalette.accent)
                    Divider()
                    HStack {
                        Text("حجم الترجمة")
                        Spacer()
                        Text("\(Int(model.captionSize)) pt")
                            .foregroundStyle(CinemaPalette.secondary)
                    }
                    Slider(value: $model.captionSize, in: 14...38, step: 1)
                        .tint(CinemaPalette.accent)
                    HStack {
                        Text("ارتفاع الترجمة")
                        Spacer()
                        Text("\(Int(model.captionBottom)) pt")
                            .foregroundStyle(CinemaPalette.secondary)
                    }
                    HStack(spacing: 9) {
                        Button("أسفل −1") { model.adjustPosition(-1) }
                        Button("أعلى +1") { model.adjustPosition(1) }
                    }
                    .buttonStyle(.bordered)
                    Slider(value: $model.captionBottom, in: 1...130, step: 1)
                        .tint(CinemaPalette.accent)
                    HStack {
                        Text("شفافية الخلفية")
                        Spacer()
                        Text("\(Int(model.backgroundOpacity * 100))%")
                            .foregroundStyle(CinemaPalette.secondary)
                    }
                    Slider(value: $model.backgroundOpacity, in: 0...1)
                        .tint(CinemaPalette.accent)
                }
                .padding(22)
            }
            .navigationTitle("إعدادات الترجمة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") { showingCaptionSettings = false }
                }
            }
            .background(CinemaPalette.base)
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private func clock(_ time: Double) -> String {
        guard time.isFinite else { return "00:00" }
        let total = max(0, Int(time))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
