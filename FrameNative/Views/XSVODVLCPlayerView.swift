import SwiftUI
import VLCKitSPM

// V21: premium native controls inspired by the original R5 player.
// Its proprietary website-based decoder cannot play Xtream VOD URLs;
// the playback surface here is VLC 4, with independent player chrome.
struct XSVODSubtitleTrack: Identifiable, Hashable {
    let id: Int
    let name: String
    let selected: Bool
}

struct XSVODVLCPlayerView: View {
    let source: XSVODPlaybackSelection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = XSVODVLCPlayerModel()
    @State private var controlsVisible = true
    @State private var panel: Panel = .none
    @State private var isScrubbing = false
    @State private var scrubValue = 0.0
    @State private var controlsHideTask: Task<Void, Never>?

    private enum Panel { case none, subtitles, audio, settings }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.ignoresSafeArea()
                XSVODVLCSurface(player: model.player)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }

                if model.status == .connecting {
                    VStack(spacing: 13) {
                        ProgressView().controlSize(.large).tint(.white)
                        Text(model.tryingBackup ? "نجرب رابط التشغيل الاحتياطي…" : "جارٍ الاتصال بسيرفر الفيديو…")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                    .padding(20)
                    .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 15))
                    .allowsHitTesting(false)
                } else if model.status == .failed {
                    failureCard
                }

                if controlsVisible || panel != .none {
                    premiumChrome(proxy)
                        .transition(.opacity)
                }
                if panel != .none {
                    panelOverlay(proxy)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .animation(.easeOut(duration: 0.16), value: controlsVisible)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .onAppear {
            model.start(source: source)
            revealControls()
        }
        .onDisappear {
            controlsHideTask?.cancel()
            model.stop()
        }
        .onChange(of: model.playing) { playing in
            if playing { revealControls() }
        }
    }

    private var failureCard: some View {
        VStack(spacing: 13) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.yellow)
            Text("تعذر تشغيل الفيديو")
                .font(.headline)
            Text("المصدر لم يستجب للمشغل حتى بعد تجربة الرابط الاحتياطي. جرّب عنواناً آخر أو حدّث الاتصال.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.73))
            Button {
                model.start(source: source)
                revealControls()
            } label: {
                Label("إعادة المحاولة", systemImage: "arrow.clockwise")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 22)
                    .frame(height: 42)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 1.0, green: 0.29, blue: 0.39))
        }
        .padding(23)
        .frame(maxWidth: 310)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 18))
    }

    private func premiumChrome(_ proxy: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                roundButton("xmark") {
                    model.stop()
                    dismiss()
                }
                Text(source.title)
                    .font(.headline.weight(.medium))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                roundButton("captions.bubble.fill") { open(.subtitles) }
                roundButton("waveform") { open(.audio) }
                roundButton("ellipsis") { open(.settings) }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, max(proxy.safeAreaInsets.top, 18) + 8)

            Spacer(minLength: 35)

            HStack(spacing: 42) {
                Button {
                    model.seekBy(-10)
                    revealControls()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.system(size: 35, weight: .medium))
                }
                Button {
                    model.togglePlayPause()
                    revealControls()
                } label: {
                    Image(systemName: model.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 38, weight: .bold))
                        .frame(width: 82, height: 82)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18)))
                }
                Button {
                    model.seekBy(10)
                    revealControls()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.system(size: 35, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)

            Spacer(minLength: 30)

            HStack(spacing: 14) {
                Text(formatted(isScrubbing ? scrubValue : model.positionSeconds))
                    .font(.caption.monospacedDigit())
                    .frame(width: 58, alignment: .leading)
                Slider(value: Binding(get: {
                    isScrubbing ? scrubValue : model.positionSeconds
                }, set: { scrubValue = $0 }),
                in: 0...max(model.durationSeconds, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if editing {
                        scrubValue = model.positionSeconds
                        controlsHideTask?.cancel()
                    } else {
                        model.seek(to: scrubValue)
                        revealControls()
                    }
                })
                .tint(.white)
                Text("−" + formatted(max(model.durationSeconds -
                        (isScrubbing ? scrubValue : model.positionSeconds), 0)))
                    .font(.caption.monospacedDigit())
                    .frame(width: 65, alignment: .trailing)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.13)))
            .padding(.horizontal, 18)
            .padding(.bottom, max(proxy.safeAreaInsets.bottom, 18))
        }
        .background {
            LinearGradient(colors: [.black.opacity(0.65), .clear, .black.opacity(0.64)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private func panelOverlay(_ proxy: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { closePanel() }
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    HStack {
                        Text(panelTitle).font(.title3.bold())
                        Spacer()
                        Button { closePanel() } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2)
                        }
                    }
                    .foregroundStyle(.white)

                    if panel == .subtitles {
                        panelButton("إيقاف الترجمة", selected: model.selectedSubtitle == -1) {
                            model.selectSubtitle(-1); closePanel()
                        }
                        if model.subtitles.isEmpty {
                            Text("ما فيه ترجمة مدمجة ظاهرة في هذا الفيديو.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        ForEach(model.subtitles) { track in
                            panelButton(track.name, selected: model.selectedSubtitle == track.id) {
                                model.selectSubtitle(track.id); closePanel()
                            }
                        }
                        Button("تحديث قائمة الترجمة") { model.refreshTracks() }
                            .font(.caption)
                    } else if panel == .audio {
                        if model.audioTracks.isEmpty {
                            Text("ما فيه مسارات صوت إضافية.")
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        ForEach(model.audioTracks) { track in
                            panelButton(track.name, selected: track.selected) {
                                model.selectAudio(track.id); closePanel()
                            }
                        }
                    } else if panel == .settings {
                        Text("سرعة التشغيل").font(.subheadline.bold())
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                            panelButton(String(format: "%.2gx", speed),
                                        selected: abs(model.playbackSpeed - speed) < 0.01) {
                                model.setPlaybackSpeed(speed); closePanel()
                            }
                        }
                        Text("التشغيل المباشر من اشتراك VOD")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.63))
                        Button {
                            model.start(source: source)
                            closePanel()
                        } label: {
                            Label("إعادة الاتصال", systemImage: "arrow.clockwise")
                        }
                    }
                }
                .padding(24)
            }
            .frame(width: min(max(proxy.size.width * 0.62, 230), 410),
                   maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
    }

    private var panelTitle: String {
        switch panel {
        case .subtitles: return "الترجمة"
        case .audio: return "المسارات الصوتية"
        case .settings: return "إعدادات المشغل"
        case .none: return ""
        }
    }

    private func panelButton(_ title: String, selected: Bool,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title).lineLimit(2)
                Spacer(minLength: 5)
                if selected { Image(systemName: "checkmark").foregroundStyle(.pink) }
            }
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(selected ? 0.17 : 0.07),
                        in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func roundButton(_ symbol: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 43, height: 43)
                .background(.black.opacity(0.56), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.15)))
        }
        .buttonStyle(.plain)
    }

    private func formatted(_ seconds: Double) -> String {
        let n = Int(max(0, seconds.isFinite ? seconds : 0))
        if n >= 3600 {
            return String(format: "%d:%02d:%02d", n / 3600, (n % 3600) / 60, n % 60)
        }
        return String(format: "%02d:%02d", n / 60, n % 60)
    }

    private func open(_ which: Panel) {
        controlsHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            controlsVisible = true
            panel = which
        }
    }

    private func closePanel() {
        withAnimation(.easeOut(duration: 0.16)) { panel = .none }
        revealControls()
    }

    private func toggleControls() {
        if panel != .none { closePanel(); return }
        if controlsVisible {
            controlsHideTask?.cancel()
            withAnimation(.easeOut(duration: 0.16)) { controlsVisible = false }
        } else { revealControls() }
    }

    private func revealControls() {
        controlsHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) { controlsVisible = true }
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, panel == .none, model.playing else { return }
            withAnimation(.easeOut(duration: 0.16)) { controlsVisible = false }
        }
    }
}

@MainActor
final class XSVODVLCPlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    enum Status { case connecting, playing, paused, failed }
    let player = VLCMediaPlayer()

    @Published var playing = false
    @Published var status: Status = .connecting
    @Published var tryingBackup = false
    @Published var subtitles: [XSVODSubtitleTrack] = []
    @Published var audioTracks: [XSVODSubtitleTrack] = []
    @Published var selectedSubtitle: Int = -1
    @Published var positionSeconds = 0.0
    @Published var durationSeconds = 0.0
    @Published var playbackSpeed = 1.0

    private var urls: [URL] = []
    private var index = 0
    private var generation = 0
    private var fallbackTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var subtitleWasSelectedByUser = false

    override init() {
        super.init()
        player.delegate = self
    }

    func start(source: XSVODPlaybackSelection) {
        var candidates = [source.url]
        if let fallback = source.fallbackURL,
           !candidates.contains(fallback) { candidates.append(fallback) }
        urls = candidates
        index = 0
        subtitleWasSelectedByUser = false
        play(index: 0)
    }

    private func play(index requested: Int) {
        guard urls.indices.contains(requested) else {
            status = .failed
            return
        }
        generation += 1
        let token = generation
        fallbackTask?.cancel()
        refreshTask?.cancel()
        index = requested
        tryingBackup = requested > 0
        status = .connecting
        playing = false
        positionSeconds = 0
        durationSeconds = 0
        subtitles = []
        audioTracks = []
        selectedSubtitle = -1
        player.stop()
        player.delegate = self

        let media = VLCMedia(url: urls[requested])
        media.addOption(":http-reconnect")
        media.addOption(":network-caching=850")
        player.media = media
        player.play()

        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 16_000_000_000)
            guard !Task.isCancelled, let self, token == self.generation else { return }
            if !self.player.isPlaying { self.nextCandidate() }
        }
    }

    private func nextCandidate() {
        fallbackTask?.cancel()
        let next = index + 1
        if urls.indices.contains(next) {
            play(index: next)
        } else {
            playing = false
            status = .failed
        }
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            playing = false
            status = .paused
        } else {
            player.play()
            status = .connecting
        }
    }

    func seekBy(_ seconds: Double) {
        seek(to: positionSeconds + seconds)
    }

    func seek(to seconds: Double) {
        guard durationSeconds > 0 else { return }
        let clamped = min(max(seconds, 0), durationSeconds)
        player.position = Float(clamped / durationSeconds)
        positionSeconds = clamped
    }

    func setPlaybackSpeed(_ speed: Double) {
        player.rate = Float(speed)
        playbackSpeed = speed
    }

    func stop() {
        generation += 1
        fallbackTask?.cancel()
        refreshTask?.cancel()
        player.stop()
        player.delegate = nil
        playing = false
    }

    func refreshTracks() {
        let textTracks = Array(player.textTracks)
        subtitles = textTracks.enumerated().map { i, track in
            XSVODSubtitleTrack(id: i, name: track.trackName, selected: track.isSelected)
        }
        let audio = Array(player.audioTracks)
        audioTracks = audio.enumerated().map { i, track in
            XSVODSubtitleTrack(id: i, name: track.trackName, selected: track.isSelected)
        }

        if !subtitleWasSelectedByUser,
           let arabic = textTracks.firstIndex(where: {
               let title = $0.trackName.lowercased()
               return title.contains("arabic") || title.contains("العربية")
                   || title.contains("عربي") || title.contains("ara")
           }) {
            textTracks[arabic].isSelectedExclusively = true
            selectedSubtitle = arabic
        } else {
            selectedSubtitle = textTracks.firstIndex(where: { $0.isSelected }) ?? -1
        }
    }

    func selectSubtitle(_ index: Int) {
        subtitleWasSelectedByUser = true
        let all = Array(player.textTracks)
        if index < 0 {
            for track in all where track.isSelected { track.isSelected = false }
            selectedSubtitle = -1
        } else if all.indices.contains(index) {
            all[index].isSelectedExclusively = true
            selectedSubtitle = index
        }
        refreshTracks()
    }

    func selectAudio(_ index: Int) {
        let all = Array(player.audioTracks)
        if all.indices.contains(index) { all[index].isSelectedExclusively = true }
        refreshTracks()
    }

    private func updateClock() {
        let ms = Double(player.time.intValue)
        guard ms.isFinite, ms >= 0 else { return }
        positionSeconds = ms / 1000
        let remaining = abs(Double(player.remainingTime?.intValue ?? 0)) / 1000
        if remaining > 0 {
            durationSeconds = max(durationSeconds, positionSeconds + remaining)
        }
    }

    nonisolated func mediaPlayerStateChanged(_ state: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch state {
            case .playing:
                self.status = .playing
                self.playing = true
                self.fallbackTask?.cancel()
                let token = self.generation
                self.refreshTask?.cancel()
                self.refreshTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 850_000_000)
                    guard !Task.isCancelled, let self, token == self.generation else { return }
                    self.refreshTracks()
                    self.updateClock()
                }
            case .paused:
                self.status = .paused
                self.playing = false
            case .buffering:
                if !self.playing { self.status = .connecting }
            case .error:
                self.nextCandidate()
            default: break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateClock()
        }
    }
}

private struct XSVODVLCSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        player.drawable = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.isUserInteractionEnabled = false
        if player.drawable as AnyObject? !== view {
            player.drawable = view
        }
    }
}
