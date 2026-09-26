import Foundation

struct MixedChunk: Sendable {
    let samples: [Float]      // 16 kHz mono, 100 ms
    let micRMS: Float
    let sysRMS: Float
    var micDominant: Bool { micRMS > sysRMS * 1.5 && micRMS > 0.003 }
}

/// Aligns the microphone and system-audio streams (both 16 kHz mono) and emits
/// mixed 100 ms chunks. Sources may be enabled independently. If one enabled source
/// stalls, the other keeps flowing after a short grace period.
final class MixBus {
    static let frame = 1600  // 100 ms @ 16 kHz
    private let lock = NSLock()
    private var mic: [Float] = []
    private var sys: [Float] = []
    private let micEnabled: Bool
    private let sysEnabled: Bool
    private let stallSamples = 16000 * 2  // 2 s
    var output: ((MixedChunk) -> Void)?

    init(micEnabled: Bool, sysEnabled: Bool) {
        self.micEnabled = micEnabled
        self.sysEnabled = sysEnabled
    }

    func pushMic(_ s: [Float]) {
        guard micEnabled else { return }
        lock.lock()
        mic.append(contentsOf: s)
        lock.unlock()
        drain()
    }

    func pushSys(_ s: [Float]) {
        guard sysEnabled else { return }
        lock.lock()
        sys.append(contentsOf: s)
        lock.unlock()
        drain()
    }

    private func drain() {
        var chunks: [MixedChunk] = []
        lock.lock()
        let frame = Self.frame
        while true {
            var micAvail = micEnabled ? mic.count : Int.max
            var sysAvail = sysEnabled ? sys.count : Int.max
            // Stall handling: if one source has piled up > 2 s and the other has nothing,
            // synthesize silence for the missing one so the pipeline keeps moving.
            var padMic = false
            var padSys = false
            if micEnabled && sysEnabled {
                if sys.count >= stallSamples && mic.count < frame { padMic = true; micAvail = Int.max }
                if mic.count >= stallSamples && sys.count < frame { padSys = true; sysAvail = Int.max }
            }
            let avail = min(micAvail, sysAvail)
            if avail < frame { break }

            var out = [Float](repeating: 0, count: frame)
            var micEnergy: Float = 0
            var sysEnergy: Float = 0
            if sysEnabled && !padSys {
                for i in 0..<frame {
                    let v = sys[i]
                    out[i] += v
                    sysEnergy += v * v
                }
                sys.removeFirst(frame)
            }
            if micEnabled && !padMic {
                for i in 0..<frame { micEnergy += mic[i] * mic[i] }
                // Echo ducking: without headphones the microphone re-captures the remote side
                // a few ms later, and the diarizer then hears every remote voice twice. While the
                // system track clearly dominates, the mic contributes only a whisper; when the
                // local user actually talks over it, the mic is louder and passes through.
                let micRMS = (micEnergy / Float(frame)).squareRoot()
                let sysRMS = (sysEnergy / Float(frame)).squareRoot()
                let duck: Float = (sysEnabled && !padSys && sysRMS > 0.004 && micRMS < sysRMS * 2.5) ? 0.05 : 1
                for i in 0..<frame { out[i] += mic[i] * duck }
                if duck < 1 { micEnergy *= duck * duck }
                mic.removeFirst(frame)
            }
            for i in 0..<frame { out[i] = max(-1, min(1, out[i])) }
            chunks.append(MixedChunk(
                samples: out,
                micRMS: (micEnergy / Float(frame)).squareRoot(),
                sysRMS: (sysEnergy / Float(frame)).squareRoot()))
        }
        lock.unlock()
        for c in chunks { output?(c) }
    }
}
