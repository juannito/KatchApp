import AVFoundation
import Foundation

/// Writes 16 kHz mono 16-bit PCM WAV incrementally.
final class WavWriter {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let queue = DispatchQueue(label: "meetai.wavwriter", qos: .utility)

    init(url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        guard let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)
        else { throw AudioError("Invalid WAV format") }
        format = fmt
        file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func write(_ samples: [Float]) {
        queue.async { [self] in
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                let ch = buf.floatChannelData
            else { return }
            samples.withUnsafeBufferPointer { src in
                ch[0].update(from: src.baseAddress!, count: samples.count)
            }
            buf.frameLength = AVAudioFrameCount(samples.count)
            try? file.write(from: buf)
        }
    }

    func close(completion: @escaping () -> Void) {
        queue.async { completion() }
    }
}
