import AVFoundation
import Foundation

/// Streaming converter from any PCM format to 16 kHz mono Float32.
/// Keeps AVAudioConverter state across calls so sample-rate conversion is continuous.
final class StreamResampler {
    static let targetRate: Double = 16000
    private let converter: AVAudioConverter
    private let outFormat: AVAudioFormat
    private let inRate: Double

    init(inputFormat: AVAudioFormat) throws {
        guard let out = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.targetRate, channels: 1, interleaved: false)
        else { throw AudioError("Could not create the 16 kHz mono format") }
        guard let c = AVAudioConverter(from: inputFormat, to: out) else {
            throw AudioError("Could not create AVAudioConverter from \(inputFormat)")
        }
        converter = c
        outFormat = out
        inRate = inputFormat.sampleRate
    }

    func process(_ input: AVAudioPCMBuffer) throws -> [Float] {
        guard input.frameLength > 0 else { return [] }
        let ratio = Self.targetRate / inRate
        let capacity = AVAudioFrameCount(Double(input.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw error ?? AudioError("AVAudioConverter failed")
        }
        let n = Int(out.frameLength)
        guard n > 0, let ch = out.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: ch[0], count: n))
    }
}
