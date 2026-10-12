import AVFoundation

@MainActor
enum XSTVPlaybackEnvironment {
    static func configure() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay]
            )
            try session.setActive(true)
        } catch {
            // Playback can still continue through WebKit if the audio session cannot be preconfigured.
        }
    }
}
