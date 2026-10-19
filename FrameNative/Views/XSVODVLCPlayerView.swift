import SwiftUI
import VLCKitSPM

// Source-synchronized native tracks: no subtitle scraping, external SRT
// matching, or synthetic offsets. The same underlying VLC engine powers sports.
struct XSVODSubtitleTrack: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct XSVODVLCPlayerView: View {
    let source: XSVODPlaybackSelection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = XSVODVLCPlayerModel()
    @State private var showControls = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            XSVODVLCSurface(player: model.player)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { withAnimation(.easeOut(duration: 0.18)) { showControls.toggle() } }
            if showControls {
                VStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Text(source.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            model.stop()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.7), in: Circle())
                        }
                    }
                    .padding(.top, 12)

                    Spacer()

                    if model.status == .failed {
                        VStack(spacing: 11) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title2)
                                .foregroundStyle(.yellow)
                            Text("تعذر تشغيل الفيديو من مزود الخدمة")
                                .font(.subheadline.bold())
                            Button("إعادة المحاولة") { model.start(url: source.url) }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(20)
                        .background(.black.opacity(0.80), in: RoundedRectangle(cornerRadius: 16))
                    } else if model.status == .connecting {
                        ProgressView().tint(.white)
                        Text("جارٍ تشغيل الفيديو…")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()

                    HStack(spacing: 18) {
                        Button {
                            model.togglePlayPause()
                        } label: {
                            Image(systemName: model.playing ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .frame(width: 49, height: 45)
                        }
                        Menu {
                            Button("تحديث مسارات الترجمة") { model.refreshSubtitles() }
                            Button("إيقاف الترجمة") { model.selectSubtitle(-1) }
                            if model.subtitles.isEmpty {
                                Text("لا توجد مسارات ترجمة مدمجة في هذا الفيديو")
                            } else {
                                ForEach(model.subtitles) { track in
                                    Button {
                                        model.selectSubtitle(track.id)
                                    } label: {
                                        if model.selectedSubtitle == track.id {
                                            Label(track.name, systemImage: "checkmark")
                                        } else {
                                            Text(track.name)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("الترجمة", systemImage: "captions.bubble.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 13)
                                .frame(height: 43)
                                .background(.white.opacity(0.14), in: Capsule())
                        }
                        Button {
                            model.start(url: source.url)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 19))
                                .frame(width: 40, height: 43)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.bottom, 18)
                }
                .padding(.horizontal, 20)
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { model.start(url: source.url) }
        .onDisappear { model.stop() }
    }
}

@MainActor
final class XSVODVLCPlayerModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    enum Status { case connecting, playing, paused, failed }
    let player = VLCMediaPlayer()
    @Published var playing = false
    @Published var status: Status = .connecting
    @Published var subtitles: [XSVODSubtitleTrack] = []
    @Published var selectedSubtitle: Int = -1
    private var generation = 0
    private var refreshTask: Task<Void, Never>?

    override init() {
        super.init()
        player.delegate = self
    }

    func start(url: URL) {
        generation += 1
        refreshTask?.cancel()
        player.stop()
        player.delegate = self
        subtitles = []
        selectedSubtitle = -1
        playing = false
        status = .connecting
        player.media = VLCMedia(url: url)
        player.play()
    }

    func togglePlayPause() {
        if player.isPlaying {
            player.pause()
            playing = false
            status = .paused
        } else {
            player.play()
        }
    }

    func stop() {
        generation += 1
        refreshTask?.cancel()
        player.stop()
        player.delegate = nil
        playing = false
    }

    // VLC 4 exposes native per-media track objects. Those subtitle tracks
    // carry the same source timestamps as the video, avoiding SRT time offsets.
    func refreshSubtitles() {
        let tracks = Array(player.textTracks)
        subtitles = tracks.enumerated().map { index, track in
            XSVODSubtitleTrack(id: index, name: track.trackName)
        }
        if let arabicIndex = tracks.firstIndex(where: {
            let s = $0.trackName.lowercased()
            return s.contains("arabic") || s.contains("عربي")
                || s.contains("العربية") || s.contains("ara") || s.contains(" ar ")
        }) {
            tracks[arabicIndex].isSelectedExclusively = true
            selectedSubtitle = arabicIndex
        } else {
            selectedSubtitle = tracks.firstIndex(where: { $0.isSelected }) ?? -1
        }
    }

    func selectSubtitle(_ index: Int) {
        let tracks = Array(player.textTracks)
        if index < 0 {
            for track in tracks where track.isSelected { track.isSelected = false }
            selectedSubtitle = -1
        } else if tracks.indices.contains(index) {
            tracks[index].isSelectedExclusively = true
            selectedSubtitle = index
        }
    }

    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch newState {
            case .playing:
                self.playing = true
                self.status = .playing
                let active = self.generation
                self.refreshTask?.cancel()
                self.refreshTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 750_000_000)
                    guard !Task.isCancelled, let self,
                          self.generation == active else { return }
                    self.refreshSubtitles()
                }
            case .paused:
                self.playing = false
                self.status = .paused
            case .error:
                self.playing = false
                self.status = .failed
            case .buffering:
                if !self.playing { self.status = .connecting }
            default:
                break
            }
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
        if player.drawable as AnyObject? !== view { player.drawable = view }
    }
}
