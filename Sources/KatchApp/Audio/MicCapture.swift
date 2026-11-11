import AVFoundation
import CoreAudio
import Foundation

/// Microphone capture that follows the system's default input: when headphones are connected or
/// removed the engine is rebuilt on the new device, so the recording keeps going.
final class MicCapture {
    typealias Handler = ([Float]) -> Void
    private let queue = DispatchQueue(label: "katchapp.miccapture")
    private var engine = AVAudioEngine()
    private var handler: Handler?
    private var observer: NSObjectProtocol?
    private var inputWatcher: AudioPropertyWatcher?
    private var generation = 0
    private(set) var isRunning = false

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    func start(handler: @escaping Handler) throws {
        try queue.sync {
            guard !isRunning else { return }
            self.handler = handler
            try startEngine()
            isRunning = true
            // Connecting AirPods flips the input between profiles and sample rates, which stops
            // the engine; the default-device listener catches switches that leave it running.
            observer = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil
            ) { [weak self] note in
                let source = ObjectIdentifier(note.object as AnyObject)
                self?.queue.async {
                    guard let self, source == ObjectIdentifier(self.engine) else { return }
                    self.scheduleRebuild(reason: "engine configuration changed")
                }
            }
            inputWatcher = AudioPropertyWatcher(selector: kAudioHardwarePropertyDefaultInputDevice, queue: queue) { [weak self] in
                self?.scheduleRebuild(reason: "default input changed")  // already on `queue`
            }
        }
    }

    func stop() {
        queue.sync {
            guard isRunning else { return }
            isRunning = false
            generation += 1
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            inputWatcher = nil
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            handler = nil
        }
    }

    /// Must run on `queue`.
    private func startEngine() throws {
        guard let handler else { return }
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw AudioError(L("No microphone available"))
        }
        let resampler = try StreamResampler(inputFormat: fmt)
        input.installTap(onBus: 0, bufferSize: 2048, format: fmt) { buffer, _ in
            if let out = try? resampler.process(buffer), !out.isEmpty {
                handler(out)
            }
        }
        engine.prepare()
        try engine.start()
        let device = (try? AudioObjectID.readDefaultInputDevice())?.readDeviceName() ?? "?"
        AppLog.write("mic capturing from \(device) @ \(Int(fmt.sampleRate)) Hz, \(fmt.channelCount) ch")
    }

    /// Debounced: connecting Bluetooth headphones fires several changes in a row.
    private func scheduleRebuild(reason: String) {
        guard isRunning else { return }
        generation += 1
        let gen = generation
        AppLog.write("mic: \(reason)")
        queue.asyncAfter(deadline: .now() + 0.5) { [self] in rebuild(generation: gen, attempt: 1) }
    }

    private func rebuild(generation gen: Int, attempt: Int) {
        guard isRunning, gen == generation else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        engine = AVAudioEngine()
        do {
            try startEngine()
        } catch {
            AppLog.write("mic restart failed (attempt \(attempt)): \(error.localizedDescription)")
            guard attempt < 8 else { return }
            // The new device may still be settling; try again shortly.
            queue.asyncAfter(deadline: .now() + 1) { [self] in rebuild(generation: gen, attempt: attempt + 1) }
        }
    }
}
