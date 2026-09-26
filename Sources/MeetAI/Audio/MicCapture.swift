import AVFoundation
import Foundation

final class MicCapture {
    typealias Handler = ([Float]) -> Void
    private let engine = AVAudioEngine()
    private var resampler: StreamResampler?
    private(set) var isRunning = false

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(handler: @escaping Handler) throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw AudioError(L("No microphone available"))
        }
        let resampler = try StreamResampler(inputFormat: fmt)
        self.resampler = resampler
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { buffer, _ in
            if let out = try? resampler.process(buffer), !out.isEmpty {
                handler(out)
            }
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
