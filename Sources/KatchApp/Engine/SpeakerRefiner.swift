import FluidAudio
import Foundation

/// Offline re-pass over the whole recording with Nemotron 3's offline preset (best DER).
/// Live labels are kept: offline speakers are mapped onto the live slots by co-activity,
/// then every word is re-attributed. Fixes the "first word sticks to the previous speaker"
/// artefact of streaming diarization.
actor SpeakerRefiner {
    struct Result {
        var segments: [TranscriptSegment]
        var changedWords: Int
        var totalWords: Int
        var newSpeakers: Int
    }

    private var models: Nemotron3Models?
    private static let config = Nemotron3Config.offline
    private static let frameSeconds = 0.01

    func preload() async {
        _ = try? await loadModels()
    }

    /// Actor-serialised, so concurrent callers simply wait for the first load.
    private func loadModels() async throws -> Nemotron3Models {
        if let models { return models }
        let t0 = Date()
        let m = try await Nemotron3Models.loadFromHuggingFace(config: Self.config)
        AppLog.write(String(format: "offline diarizer ready in %.1fs", Date().timeIntervalSince(t0)))
        models = m
        return m
    }

    /// - Parameters:
    ///   - audio: full 16 kHz mono recording.
    ///   - segments: live-attributed segments.
    ///   - liveProbs / liveFrames: streaming diarizer output used for the label mapping.
    func refine(audio: [Float], segments: [TranscriptSegment], liveProbs: [Float], liveFrames: Int, numSpeakers: Int) async throws -> Result {
        let models = try await loadModels()
        let diarizer = Nemotron3Diarizer(config: Self.config, models: models)
        let t0 = Date()
        let (offProbs, offFrames) = try diarizer.processComplete(audio)
        AppLog.write(String(format: "offline diarization: %d frames in %.1fs", offFrames, Date().timeIntervalSince(t0)))

        // Co-activity matrix between offline labels (rows) and live slots (cols).
        let n = numSpeakers
        var co = [[Int]](repeating: [Int](repeating: 0, count: n), count: n)
        var offActive = [Int](repeating: 0, count: n)
        let frames = min(offFrames, liveFrames)
        for f in 0..<frames {
            for o in 0..<n where offProbs[f * n + o] > 0.5 {
                offActive[o] += 1
                for l in 0..<n where liveProbs[f * n + l] > 0.5 { co[o][l] += 1 }
            }
        }
        for f in frames..<offFrames {
            for o in 0..<n where offProbs[f * n + o] > 0.5 { offActive[o] += 1 }
        }
        // Greedy one-to-one assignment by largest overlap.
        var map = [Int?](repeating: nil, count: n)
        var usedLive = Set<Int>()
        var pairs: [(o: Int, l: Int, v: Int)] = []
        for o in 0..<n { for l in 0..<n where co[o][l] > 0 { pairs.append((o, l, co[o][l])) } }
        for p in pairs.sorted(by: { $0.v > $1.v }) where map[p.o] == nil && !usedLive.contains(p.l) {
            map[p.o] = p.l
            usedLive.insert(p.l)
        }
        // Offline speakers with real activity but no live counterpart get fresh slots.
        var nextSlot = (usedLive.max() ?? -1) + 1
        let liveSlots = Set(segments.flatMap { $0.words.compactMap(\.speaker) })
        nextSlot = max(nextSlot, (liveSlots.max() ?? -1) + 1)
        var newSpeakers = 0
        for o in 0..<n where map[o] == nil && Double(offActive[o]) * Self.frameSeconds >= 1.0 {
            map[o] = nextSlot
            nextSlot += 1
            newSpeakers += 1
        }

        func best(from start: Double, to end: Double) -> Int? {
            let f0 = max(0, Int(start / Self.frameSeconds))
            let f1 = min(offFrames, max(f0 + 1, Int(end / Self.frameSeconds)))
            guard f1 > f0 else { return nil }
            var score = [Float](repeating: 0, count: n)
            for f in f0..<f1 {
                for o in 0..<n {
                    let p = offProbs[f * n + o]
                    if p > 0.5 { score[o] += p }
                }
            }
            var bestO = -1
            var bestS: Float = 0
            for o in 0..<n where score[o] > bestS && map[o] != nil {
                bestO = o
                bestS = score[o]
            }
            return bestO >= 0 ? map[bestO] : nil
        }

        // Re-attribute every word, then rebuild runs.
        var words = segments.flatMap(\.words).sorted { $0.start < $1.start }
        let before = words.map(\.speaker)
        var previous: Int? = nil
        for i in words.indices {
            let sp = best(from: words[i].start, to: words[i].end) ?? best(from: words[i].start - 0.3, to: words[i].end + 0.3) ?? previous
            words[i].speaker = sp
            if sp != nil { previous = sp }
        }
        if let first = words.first(where: { $0.speaker != nil })?.speaker {
            for i in words.indices where words[i].speaker == nil { words[i].speaker = first }
        }
        if words.count >= 3 {
            for i in 1..<(words.count - 1)
            where words[i].speaker != words[i - 1].speaker && words[i - 1].speaker == words[i + 1].speaker
                && words[i].end - words[i].start < 0.4
            {
                words[i].speaker = words[i - 1].speaker
            }
        }
        var out: [TranscriptSegment] = []
        var run: [Word] = []
        func flush() {
            guard let f = run.first, let l = run.last else { return }
            out.append(TranscriptSegment(start: f.start, end: l.end, speaker: f.speaker, attributed: true, words: run))
            run = []
        }
        for w in words {
            if let last = run.last, last.speaker != w.speaker || w.start - last.end > 1.5 { flush() }
            run.append(w)
        }
        flush()
        let changed = zip(before, words.map(\.speaker)).filter { $0 != $1 }.count
        AppLog.write("speaker refinement: \(changed)/\(words.count) words changed, \(newSpeakers) new speakers")
        return Result(segments: out, changedWords: changed, totalWords: words.count, newSpeakers: newSpeakers)
    }
}
