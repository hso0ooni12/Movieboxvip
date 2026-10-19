import SwiftUI
import VLCKitSPM

// Media in shared Febbox folders is often MKV, which AVPlayer does not decode.
// Reuse the VLC framework already linked into XS TV for these source URLs.
struct XSFebboxVLCPlaybackView: View {
    let quality: XSFebboxQuality
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = XSFebboxVLCPlaybackModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            XSFebboxVLCVideoSurface(player: model.player)
                .ignoresSafeArea()
            VStack {
                HStack {
                    Spacer()
                    Button {
                        model.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .padding(12)
                            .background(.black.opacity(0.76), in: Circle())
                    }
                    .tint(.white)
                }
                Spacer()
                HStack(spacing: 22) {
                    Button {
                        model.restart(url: quality.url)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    Button {
                        model.togglePlayback()
                    } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(.black.opacity(0.65), in: Capsule())
                if model.didFail {
                    Text("تعذر تشغيل هذا الرابط من Febbox. قد تكون الجلسة انتهت أو أن الملف غير متاح.")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(10)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(18)
        }
        .preferredColorScheme(.dark)
        .onAppear { model.start(url: quality.url) }
        .onDisappear { model.stop() }
    }
}

@MainActor
private final class XSFebboxVLCPlaybackModel: NSObject, ObservableObject, VLCMediaPlayerDelegate {
    let player = VLCMediaPlayer()
    @Published var isPlaying = false
    @Published var didFail = false

    override init() {
        super.init()
        player.delegate = self
    }

    func start(url: URL) {
        didFail = false
        player.stop()
        player.media = VLCMedia(url: url)
        player.play()
    }

    func restart(url: URL) {
        start(url: url)
    }

    func togglePlayback() {
        if player.isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
        }
    }

    func stop() {
        player.stop()
        player.delegate = nil
        isPlaying = false
    }

    nonisolated func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if newState == .playing {
                self.isPlaying = true
                self.didFail = false
            } else if newState == .paused || newState == .stopped {
                self.isPlaying = false
            } else if newState == .error {
                self.didFail = true
                self.isPlaying = false
            }
        }
    }
}

private struct XSFebboxVLCVideoSurface: UIViewRepresentable {
    let player: VLCMediaPlayer

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        view.isUserInteractionEnabled = false
        player.drawable = view
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        if player.drawable as AnyObject? !== view {
            player.drawable = view
        }
    }
}
