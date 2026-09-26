import FluidAudio
import Foundation

/// `KatchApp --selftest file.wav` — runs the live pipeline over a file as if it were streamed
/// and prints the attributed transcript. Used to validate models and timing offline.
enum SelfTest {
    /// Runs the Ollama summarizer over a saved session and prints the minutes.
    @MainActor
    static func summarize(folder: URL, ollamaModel: String) async -> Int32 {
        guard let doc = SessionStore.readDocument(at: folder) else {
            print("[summarize] no transcript.json in \(folder.path)")
            return 2
        }
        let transcript = PromptBuilder.transcriptText(doc, names: doc.speakerNames)
        print("[summarize] \(doc.turns.count) turns, \(transcript.count) chars, model \(ollamaModel)")
        let summarizer = OllamaSummarizer(baseURL: "http://localhost:11434", model: ollamaModel)
        let request = SummaryRequest(
            instructions: SummarySettings.defaultInstructions, transcript: transcript,
            meetingTitle: doc.displayTitle, meetingDate: doc.startedAt)
        let t0 = Date()
        do {
            let summary = try await summarizer.summarize(request)
            print(String(format: "[summarize] done in %.1fs", Date().timeIntervalSince(t0)))
            print(summary.markdown())
            try SummaryService.write(summary, to: folder)
            print("[summarize] written to \(folder.appendingPathComponent(SummaryService.markdownFile).path)")
            return 0
        } catch {
            print("[summarize] ERROR: \(error.localizedDescription)")
            return 3
        }
    }

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
                case .speakerEmbedding(let slot, _): print("[selftest] live embedding for spk\(slot)")
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
        // Offline re-pass: compare against the live attribution.
        do {
            let live = await engine.diarizationProbabilities()
            let refiner = SpeakerRefiner()
            let t1 = Date()
            let r = try await refiner.refine(
                audio: samples, segments: segments, liveProbs: live.probs, liveFrames: live.frames, numSpeakers: live.numSpeakers)
            print(String(format: "[selftest] refinamiento offline en %.1fs: %d/%d palabras cambiaron, %d hablantes nuevos", Date().timeIntervalSince(t1), r.changedWords, r.totalWords, r.newSpeakers))
            print("[selftest] transcripción refinada (\(r.segments.count) segmentos):")
            for seg in r.segments {
                print("  [\(TimeFormat.clock(seg.start)) – \(TimeFormat.clock(seg.end))] \(SpeakerLabel.name(for: seg.speaker, names: [:])): \(seg.text)")
            }
        } catch {
            print("[selftest] refinamiento offline falló: \(error)")
        }

        // Voice fingerprint sanity check: same speaker (two halves) should score high,
        // different speakers low.
        if let fp = models.fingerprinter {
            let ranges = await engine.exclusiveSpeechRanges()
            var embeddings: [Int: [Float]] = [:]
            var halves: [Int: ([Float], [Float])] = [:]
            for (slot, r) in ranges.sorted(by: { $0.key < $1.key }) {
                let total = r.reduce(0) { $0 + $1.duration }
                let mid = r.count / 2
                do {
                    if let e = try await fp.embed(sessionAudio: samples, ranges: r) { embeddings[slot] = e }
                    if r.count >= 2, let a = try await fp.embed(sessionAudio: samples, ranges: Array(r[0..<mid])),
                        let b = try await fp.embed(sessionAudio: samples, ranges: Array(r[mid...]))
                    {
                        halves[slot] = (a, b)
                    }
                } catch {
                    print("[selftest] embedding error spk\(slot): \(error)")
                }
                print(String(format: "[selftest] spk%d exclusive speech %.1fs in %d ranges, embedding: %@", slot, total, r.count, embeddings[slot] == nil ? "no" : "yes"))
            }
            for (slot, h) in halves.sorted(by: { $0.key < $1.key }) {
                print(String(format: "[selftest] spk%d self-similarity (half vs half): %.3f", slot, VoiceFingerprinter.cosine(h.0, h.1)))
            }
            let slots = embeddings.keys.sorted()
            for i in 0..<slots.count {
                for j in (i + 1)..<slots.count {
                    print(String(format: "[selftest] spk%d vs spk%d similarity: %.3f", slots[i], slots[j], VoiceFingerprinter.cosine(embeddings[slots[i]]!, embeddings[slots[j]]!)))
                }
            }
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
