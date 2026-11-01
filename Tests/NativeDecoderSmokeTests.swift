import AVFoundation
import CoreVideo
import UIKit
import XCTest
@testable import WatchedNative

final class NativeDecoderSmokeTests: XCTestCase {
    /// An actual MP4 decoding check using a generated local test pattern, never a catalogue title.
    /// This validates the native engine; it does not claim live Watched playback was verified.
    @MainActor
    func testNativeEngineDecodesVideoFrames() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-decoder-smoke", withExtension: "mp4"))
        let item = NativeMediaAsset.item(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first
        window?.layer.addSublayer(layer)
        defer { player.pause(); player.replaceCurrentItem(with: nil); layer.removeFromSuperlayer() }
        player.play()
        let deadline = Date().addingTimeInterval(12)
        var decoded = false
        while Date() < deadline {
            if item.status == .failed { XCTFail(item.error?.localizedDescription ?? "Native decoder failed"); break }
            let time = player.currentTime()
            if time.seconds > 0.05, output.hasNewPixelBuffer(forItemTime: time),
               let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                XCTAssertEqual(CVPixelBufferGetWidth(frame), 320)
                // H.264 decoders may retain macroblock padding around the 180px clean aperture.
                XCTAssertGreaterThanOrEqual(CVPixelBufferGetHeight(frame), 180)
                XCTAssertLessThanOrEqual(CVPixelBufferGetHeight(frame), 192)
                decoded = true; break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(decoded, "AVPlayer must deliver decoded video frames, not just construct a player object")
        XCTAssertEqual(item.status, .readyToPlay)
    }
}
