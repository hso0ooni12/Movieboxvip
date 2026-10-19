import Foundation
import AVFoundation
import ReplayKit
import SoundAnalysis
import CoreMedia

// V14_NATIVE_SPEECH_AI
// The iPhone's WKWebView does not implement HTMLMediaElement.captureStream().
// ReplayKit offers an explicit system-permission alternative to capture only
// the app's audio. Video buffers are ALWAYS discarded and NO audio is uploaded.
// Apple's on-device SoundAnalysis ML classifier detects speech windows. A
// confidence gate prevents incorrectly shifting subtitle timing.
// If content protection blocks app audio, return unavailable — never bypass it.

struct XSNativeSubtitleCue: Sendable {
    let start: Double
    let end: Double
}

enum XSNativeSubtitleResult {
    case applied(offset: Double, confidence: Double)
    case unavailable(String)
}

private struct XSNativeSpeechWindow {
    let start: Double
    let end: Double
    let confidence: Double
}

private final class XSNativeSpeechObserver: NSObject, SNResultsObserving {
    private(set) var events: [XSNativeSpeechWindow] = []

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let item = result as? SNClassificationResult else { return }
        let confidence = item.classification(forIdentifier: "speech")?.confidence ?? 0
        let start = CMTimeGetSeconds(item.timeRange.start)
        let duration = CMTimeGetSeconds(item.timeRange.duration)
        if start.isFinite, duration.isFinite, duration > 0 {
            events.append(.init(start: start, end: start + duration, confidence: confidence))
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) { }
    func requestDidComplete(_ request: SNRequest) { }
}

private final class XSNativeAudioWriter {
    private let queue = DispatchQueue(label: "xs.tv.subtitle.ml.audio.writer", qos: .utility)
    let url: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var count = 0

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("xstv-cue-align-\(UUID().uuidString).m4a")
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 64000
        ]
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw NSError(domain: "XSTV.Subtitles", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Audio encoding unavailable"])
        }
        writer.add(input)
    }

    func append(_ sample: CMSampleBuffer) {
        queue.async { [self] in
            guard CMSampleBufferIsValid(sample), CMSampleBufferDataIsReady(sample) else { return }
            if writer.status == .unknown {
                guard writer.startWriting() else { return }
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
            }
            if writer.status == .writing, input.isReadyForMoreMediaData, input.append(sample) {
                count += 1
            }
        }
    }

    func finish() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard writer.status == .writing, count > 20 else {
                    continuation.resume(throwing: NSError(
                        domain: "XSTV.Subtitles", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "No accessible app audio"]
                    ))
                    return
                }
                input.markAsFinished()
                writer.finishWriting {
                    if self.writer.status == .completed {
                        continuation.resume(returning: self.url)
                    } else {
                        continuation.resume(throwing: self.writer.error ??
                            NSError(domain:"XSTV.Subtitles",code:3))
                    }
                }
            }
        }
    }
}

@MainActor
final class XSNativeSubtitleAI {
    static let shared = XSNativeSubtitleAI()

    private var requestID = UUID()
    private var ownsCapture = false

    func cancel() {
        requestID = UUID()
        if ownsCapture {
            ownsCapture = false
            RPScreenRecorder.shared().stopCapture { _ in }
        }
    }

    func align(cues: [XSNativeSubtitleCue],
               mediaTime: @escaping @MainActor () -> Double,
               currentOffset: Double) async -> XSNativeSubtitleResult {
        guard cues.count >= 5 else {
            return .unavailable("لا تتوفر جمل ترجمة موقّتة كافية للمقارنة بالصوت.")
        }
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else {
            return .unavailable("النظام لا يسمح حالياً بتحليل صوت التطبيق.")
        }
        let token = UUID()
        requestID = token
        recorder.isMicrophoneEnabled = false

        let audio: XSNativeAudioWriter
        do { audio = try XSNativeAudioWriter() }
        catch {
            return .unavailable("تعذّر تجهيز التحليل الصوتي المحلي.")
        }
        defer { try? FileManager.default.removeItem(at: audio.url) }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                recorder.startCapture(handler: { sample, type, error in
                    guard error == nil, type == .audioApp else { return }
                    // Never append video frames, microphone audio, or raw screen.
                    audio.append(sample)
                }, completionHandler: { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
            ownsCapture = true
        } catch {
            return .unavailable("لم يسمح iOS بالتقاط صوت التطبيق. لم تتغير الترجمة.")
        }

        // On-device capture without microphone or network transmissions.
        // User has explicitly opted in by tapping "Smart Sync".
        let startMediaTime = mediaTime()
        try? await Task.sleep(nanoseconds: 26_000_000_000)
        guard requestID == token else {
            return .unavailable("أُلغيت المزامنة التلقائية.")
        }
        ownsCapture = false
        await withCheckedContinuation { continuation in
            recorder.stopCapture { _ in continuation.resume() }
        }
        let url: URL
        do { url = try await audio.finish() }
        catch {
            return .unavailable("الفيديو لا يتيح صوتاً قابلاً للتحليل على الآيفون.")
        }

        // Run Apple's built-in Core ML speech classifier outside the UI actor.
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    let analyzer = try SNAudioFileAnalyzer(url: url)
                    let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
                    let observer = XSNativeSpeechObserver()
                    try analyzer.add(request, withObserver: observer)
                    analyzer.analyze()
                    let correction = Self.estimateSpeechOffset(
                        speech: observer.events,
                        cues: cues,
                        mediaStart: startMediaTime,
                        originalOffset: currentOffset
                    )
                    continuation.resume(returning: correction)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
        guard requestID == token else {
            return .unavailable("أُلغيت المزامنة التلقائية.")
        }
        guard let result else {
            return .unavailable("تطابق الصوت مع الترجمة غير مؤكد، لذلك لم أغيّر التوقيت.")
        }
        return .applied(offset: result.0, confidence: result.1)
    }

    // Correlate Apple's ML speech probability with real timed subtitle cues.
    // A score improvement and an absolute confidence threshold are required.
    nonisolated private static func estimateSpeechOffset(
        speech: [XSNativeSpeechWindow],
        cues: [XSNativeSubtitleCue],
        mediaStart: Double,
        originalOffset: Double
    ) -> (Double, Double)? {
        guard speech.count >= 10, cues.count >= 5 else { return nil }
        guard let end = speech.map(\.end).max(), end >= 16 else { return nil }
        let steps = stride(from: 0.25, through: min(28, end), by: 0.25).map { $0 }
        let voice: [Bool] = steps.map { t in
            speech.contains { t >= $0.start && t < $0.end && $0.confidence >= 0.56 }
        }
        let voiceRate = Double(voice.filter { $0 }.count) / Double(max(1, voice.count))
        guard voiceRate > 0.16 && voiceRate < 0.84 else { return nil }

        func correlation(_ offset: Double) -> Double {
            var speechCount = 0.0, cueCount = 0.0, both = 0.0
            for (i, t) in steps.enumerated() {
                let talking = voice[i]
                let mediaPosition = mediaStart + t - offset
                let caption = cues.contains { $0.start <= mediaPosition && mediaPosition < $0.end }
                if talking { speechCount += 1 }
                if caption { cueCount += 1 }
                if talking && caption { both += 1 }
            }
            let n = Double(steps.count)
            let a = speechCount/n, b=cueCount/n
            guard b > 0.12 && b < 0.88 else { return -1 }
            let denom = sqrt(a*(1-a)*b*(1-b))
            return denom > 0 ? (both/n-a*b)/denom : -1
        }
        let previous = correlation(originalOffset)
        let candidates = (-32...32).map { step -> (Double,Double) in
            let offset = Double(step)*0.25
            return (offset,correlation(offset))
        }
        // V15_CONFIDENCE_GATE: repeated speech/music rhythms can create
        // multiple similarly strong alignments. Require a unique peak, not
        // merely a positive correlation — otherwise leave timing unchanged.
        guard let best=candidates.max(by: { $0.1 < $1.1 }),
              best.1 >= 0.69,
              best.1 - previous >= 0.19,
              abs(best.0 - originalOffset) >= 0.35 else { return nil }
        let otherPeaks = candidates.filter { abs($0.0 - best.0) >= 1.0 }
        let runnerUp = otherPeaks.map { $0.1 }.max() ?? -1
        guard best.1 - runnerUp >= 0.07 else { return nil }
        let confidence=min(0.99,max(0.0,(best.1-0.45)/0.5))
        return (best.0,confidence)
    }
}
