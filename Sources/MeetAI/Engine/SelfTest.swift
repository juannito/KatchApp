import FluidAudio
import Foundation

/// `MeetAI --selftest file.wav` — runs the live pipeline over a file as if it were streamed
/// and prints the attributed transcript. Used to validate models and timing offline.
enum SelfTest {
    static func run(path: String) async -> Int32 {
        let url = URL(fileURLWithPath: path)
        print("[selftest] cargando modelos…")
        let t0 = Date()
        let models: LoadedModels
        do {
            models = try await ModelLoader.load { step, fraction in
                if fraction == 0 || fraction == 1 { print("[models] \(step)") }
            }
        } catch {
            print("[selftest] ERROR cargando modelos: \(error)")
            return 2
        }
        print(String(format: "[selftest] modelos listos en %.1fs", Date().timeIntervalSince(t0)))

        let samples: [Float]
        do {
            samples = try AudioConverter().resampleAudioFile(url)
        } catch {
            print("[selftest] ERROR leyendo audio: \(error)")
            return 3
        }
        let audioSeconds = Double(samples.count) / 16000
        print(String(format: "[selftest] audio: %.1fs", audioSeconds))

        let engine = TranscriptionEngine(models: models)
        var segments: [TranscriptSegment] = []
        var fractions: [Int: Double] = [:]
        var warnings: [String] = []
        let consumer = Task {
            for await event in engine.events {
                switch event {
                case .transcribed(let s): segments.append(s)
                case .attributed(let id, let repl):
                    if let i = segments.firstIndex(where: { $0.id == id }) {
                        segments.replaceSubrange(i...i, with: repl)
                    } else {
                        segments.append(contentsOf: repl)
                    }
                case .speakerMicFraction(let f): for (k, v) in f { fractions[k] = v }
                case .warning(let w): warnings.append(w)
                case .vad: break
                }
            }
        }

        let t1 = Date()
        var i = 0
        let frame = MixBus.frame
        while i < samples.count {
            let end = min(samples.count, i + frame)
            var chunk = Array(samples[i..<end])
            if chunk.count < frame { chunk.append(contentsOf: [Float](repeating: 0, count: frame - chunk.count)) }
            var energy: Float = 0
            for v in chunk { energy += v * v }
            let rms = (energy / Float(frame)).squareRoot()
            await engine.push(MixedChunk(samples: chunk, micRMS: 0, sysRMS: rms))
            i = end
        }
        await engine.finish()
        await consumer.value
        let elapsed = Date().timeIntervalSince(t1)
        print(String(format: "[selftest] procesado en %.1fs (%.1fx tiempo real)", elapsed, audioSeconds / elapsed))

        let diar = await engine.diarizationSegments()
        print("[selftest] segmentos de diarización: \(diar.count)")
        for d in diar.prefix(40) {
            print(String(format: "  spk%d %6.2f – %6.2f", d.speakerIndex, d.startSeconds, d.endSeconds))
        }
        print("[selftest] transcripción (\(segments.count) segmentos):")
        let doc = SessionDocument(
            id: UUID(), startedAt: Date(), endedAt: nil, micEnabled: false, systemAudioEnabled: true,
            speakerNames: [:], speakerMicFraction: fractions, segments: segments)
        for turn in doc.turns {
            let name = SpeakerLabel.name(for: turn.speaker, names: [:])
            print(String(format: "  [%@ – %@] %@: %@", TimeFormat.clock(turn.start), TimeFormat.clock(turn.end), name, turn.text))
        }
        if !warnings.isEmpty {
            print("[selftest] avisos:")
            for w in warnings { print("  - \(w)") }
        }
        let unattributed = segments.filter { !$0.attributed }.count
        if unattributed > 0 { print("[selftest] ATENCIÓN: \(unattributed) segmentos sin atribuir") }
        return segments.isEmpty ? 4 : 0
    }
}
