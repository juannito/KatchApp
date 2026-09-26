import FluidAudio
import Foundation

/// Live pipeline: 16 kHz mono chunks in → VAD-gated ASR segments + streaming diarization
/// → words attributed to arrival-ordered speaker slots.
actor TranscriptionEngine {
    enum Event: Sendable {
        case transcribed(TranscriptSegment)                       // text available, speaker pending
        case attributed(replacing: UUID, with: [TranscriptSegment])
        case speakerMicFraction([Int: Double])
        case speakerEmbedding(slot: Int, embedding: [Float])
        case vad(Float)
        case warning(String)
    }

    struct Config: Sendable {
        var speechStart: Float = 0.5
        var speechEnd: Float = 0.35
        var minSilence: Double = 0.7      // seconds of silence that closes a segment
        var maxSegment: Double = 15.0     // force a cut on continuous speech
        var padding: Double = 0.25        // audio kept before/after speech
        var minWordsForOwnTurn = 1
    }

    static let sampleRate = 16000
    private static let vadBlock = VadManager.chunkSize  // 4096 samples = 256 ms
    private static let frameSeconds = 0.01

    private let asr: AsrManager
    private let vad: VadManager
    private let diarizer: Nemotron3Diarizer
    private let fingerprinter: VoiceFingerprinter?
    private var embeddedSeconds: [Int: Double] = [:]   // exclusive speech already fingerprinted, per slot
    private var embeddingInFlight: Set<Int> = []
    private static let liveEmbeddingStep = 5.0         // seconds of new clean speech before re-embedding
    private let numSpeakers: Int
    private let config: Config

    // Rolling audio buffer (absolute indexing) for segment extraction.
    private var audio: [Float] = []
    private var audioOffset = 0
    private var totalSamples = 0
    private let keepSamples = 16000 * 90

    // VAD state
    private var vadState: VadStreamState
    private var vadPending: [Float] = []
    private var vadConsumed = 0        // absolute sample index of next VAD block start
    private var speechActive = false
    private var silenceSeconds = 0.0
    private var segmentStart = 0
    private var lastSpeechEnd = 0

    // Diarization timeline: probabilities [frame * numSpeakers], 10 ms per frame
    private var probs: [Float] = []
    private var diarFrames = 0
    private var micDominant: [Bool] = []   // one flag per 100 ms chunk

    // ASR queue
    private struct AsrJob { let start: Int; let samples: [Float] }
    private var asrQueue: [AsrJob] = []
    private var asrRunning = false
    private var asrDrainTask: Task<Void, Never>?
    private var pendingAttribution: [TranscriptSegment] = []
    private var finished = false

    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation

    init(models: LoadedModels, config: Config = Config()) {
        self.asr = models.asr
        self.vad = models.vad
        self.diarizer = Nemotron3Diarizer(config: models.diarizerConfig, models: models.diarizerModels)
        self.fingerprinter = models.fingerprinter
        self.numSpeakers = models.diarizerConfig.numSpeakers
        self.config = config
        self.vadState = VadStreamState.initial()
        let (stream, cont) = AsyncStream<Event>.makeStream(bufferingPolicy: .unbounded)
        self.events = stream
        self.continuation = cont
        diarizer.reset()
    }

    // MARK: - Input

    func push(_ chunk: MixedChunk) async {
        guard !finished else { return }
        let samples = chunk.samples
        audio.append(contentsOf: samples)
        totalSamples += samples.count
        micDominant.append(chunk.micDominant)
        trimAudioBuffer()

        // Diarization (streaming, host-side state)
        diarizer.appendAudio(samples)
        do {
            for result in try diarizer.processBufferedAudio() {
                probs.append(contentsOf: result.probabilities)
                diarFrames += result.frameCount
            }
        } catch {
            continuation.yield(.warning("Diarization: \(error.localizedDescription)"))
        }

        // VAD + segmentation
        vadPending.append(contentsOf: samples)
        while vadPending.count >= Self.vadBlock {
            let block = Array(vadPending[0..<Self.vadBlock])
            vadPending.removeFirst(Self.vadBlock)
            let blockStart = vadConsumed
            vadConsumed += Self.vadBlock
            await processVadBlock(block, start: blockStart)
        }

        resolvePending(force: false)
        scheduleLiveEmbeddings()
    }

    /// Fingerprints speakers while recording: whenever a slot has accumulated enough new
    /// single-speaker audio inside the rolling buffer, embed it and emit the result.
    private func scheduleLiveEmbeddings() {
        guard let fingerprinter, diarFrames > 0 else { return }
        let bufferStart = Double(audioOffset) / Double(Self.sampleRate)
        let ranges = exclusiveSpeechRanges()
        for (slot, all) in ranges {
            guard !embeddingInFlight.contains(slot) else { continue }
            let total = all.reduce(0) { $0 + $1.duration }
            guard total - (embeddedSeconds[slot] ?? 0) >= Self.liveEmbeddingStep else { continue }
            let usable = all.filter { $0.start >= bufferStart }
            let usableSeconds = usable.reduce(0) { $0 + $1.duration }
            guard usableSeconds >= VoiceFingerprinter.minSeconds else { continue }
            embeddedSeconds[slot] = total
            embeddingInFlight.insert(slot)
            // Copy the audio the fingerprinter needs so the buffer can keep rolling.
            let lo = audioOffset
            let audioCopy = audio
            let offsetRanges = usable.map { TimeRange(start: $0.start - bufferStart, end: $0.end - bufferStart) }
            Task { [weak self] in
                var result: [Float]? = nil
                do {
                    result = try await fingerprinter.embed(sessionAudio: audioCopy, ranges: offsetRanges)
                } catch {
                    AppLog.write("live embedding failed for slot \(slot): \(error)")
                }
                _ = lo
                await self?.liveEmbeddingFinished(slot: slot, embedding: result)
            }
        }
    }

    private func liveEmbeddingFinished(slot: Int, embedding: [Float]?) {
        embeddingInFlight.remove(slot)
        if let embedding { continuation.yield(.speakerEmbedding(slot: slot, embedding: embedding)) }
    }

    func finish() async {
        guard !finished else { return }
        finished = true
        // Flush open speech
        if speechActive {
            closeSegment(end: totalSamples)
            speechActive = false
        }
        do {
            for result in try diarizer.finishStream() {
                probs.append(contentsOf: result.probabilities)
                diarFrames += result.frameCount
            }
        } catch {
            continuation.yield(.warning("Diarization (finish): \(error.localizedDescription)"))
        }
        await waitForAsr()
        resolvePending(force: true)
        continuation.finish()
    }

    // MARK: - VAD / segmentation

    private func processVadBlock(_ block: [Float], start: Int) async {
        let blockSeconds = Double(block.count) / Double(Self.sampleRate)
        let blockEnd = start + block.count
        var probability: Float = 0
        do {
            let r = try await vad.processStreamingChunk(block, state: vadState)
            vadState = r.state
            probability = r.probability
        } catch {
            continuation.yield(.warning("VAD: \(error.localizedDescription)"))
            return
        }
        continuation.yield(.vad(probability))

        if !speechActive {
            if probability >= config.speechStart {
                speechActive = true
                silenceSeconds = 0
                segmentStart = max(audioOffset, start - Int(config.padding * Double(Self.sampleRate)))
                lastSpeechEnd = blockEnd
            }
            return
        }

        if probability >= config.speechEnd {
            silenceSeconds = 0
            lastSpeechEnd = blockEnd
        } else {
            silenceSeconds += blockSeconds
        }

        let segmentSeconds = Double(blockEnd - segmentStart) / Double(Self.sampleRate)
        if silenceSeconds >= config.minSilence {
            let end = min(totalSamples, lastSpeechEnd + Int(config.padding * Double(Self.sampleRate)))
            closeSegment(end: end)
            speechActive = false
        } else if segmentSeconds >= config.maxSegment {
            closeSegment(end: blockEnd)
            segmentStart = blockEnd
            silenceSeconds = 0
        }
    }

    private func closeSegment(end: Int) {
        let start = max(segmentStart, audioOffset)
        guard end > start else { return }
        let minSamples = Int(0.4 * Double(Self.sampleRate))
        guard end - start >= minSamples else { return }
        let lo = start - audioOffset
        let hi = min(audio.count, end - audioOffset)
        guard hi > lo else { return }
        let samples = Array(audio[lo..<hi])
        asrQueue.append(AsrJob(start: start, samples: samples))
        scheduleDrain()
    }

    private func scheduleDrain() {
        guard !asrRunning, asrDrainTask == nil else { return }
        asrDrainTask = Task { [weak self] in
            await self?.drainAsr()
        }
    }

    /// Waits until every queued ASR job has been transcribed.
    private func waitForAsr() async {
        while true {
            if let task = asrDrainTask {
                await task.value
                asrDrainTask = nil
            }
            if asrQueue.isEmpty && !asrRunning { return }
            scheduleDrain()
            if asrDrainTask == nil { await Task.yield() }
        }
    }

    private func trimAudioBuffer() {
        if audio.count > keepSamples {
            let drop = audio.count - keepSamples / 2
            // never drop audio that an open segment still needs
            let safeDrop = speechActive ? min(drop, max(0, segmentStart - audioOffset)) : drop
            guard safeDrop > 0 else { return }
            audio.removeFirst(safeDrop)
            audioOffset += safeDrop
        }
    }

    // MARK: - ASR

    private func drainAsr() async {
        guard !asrRunning else { return }
        asrRunning = true
        defer {
            asrRunning = false
            asrDrainTask = nil
        }
        while !asrQueue.isEmpty {
            let job = asrQueue.removeFirst()
            let startSeconds = Double(job.start) / Double(Self.sampleRate)
            do {
                var state = TdtDecoderState.make()
                let result = try await asr.transcribe(job.samples, decoderState: &state)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                var words: [Word] = []
                if let timings = result.tokenTimings, !timings.isEmpty {
                    for w in buildWordTimings(from: timings) {
                        words.append(Word(text: w.word, start: startSeconds + w.startTime, end: startSeconds + w.endTime))
                    }
                }
                if words.isEmpty {
                    let endSeconds = startSeconds + Double(job.samples.count) / Double(Self.sampleRate)
                    words = [Word(text: text, start: startSeconds, end: endSeconds)]
                }
                let seg = TranscriptSegment(
                    start: words.first!.start, end: words.last!.end, speaker: nil, attributed: false, words: words)
                pendingAttribution.append(seg)
                continuation.yield(.transcribed(seg))
            } catch {
                continuation.yield(.warning("ASR: \(error.localizedDescription)"))
            }
        }
        resolvePending(force: false)
    }

    // MARK: - Attribution

    private var diarSeconds: Double { Double(diarFrames) * Self.frameSeconds }

    private func resolvePending(force: Bool) {
        guard !pendingAttribution.isEmpty else { return }
        var remaining: [TranscriptSegment] = []
        var touchedSpeakers = Set<Int>()
        for seg in pendingAttribution {
            if !force && diarSeconds < seg.end + 0.1 {
                remaining.append(seg)
                continue
            }
            let attributed = attribute(seg)
            for s in attributed { if let sp = s.speaker { touchedSpeakers.insert(sp) } }
            continuation.yield(.attributed(replacing: seg.id, with: attributed))
        }
        pendingAttribution = remaining
        if !touchedSpeakers.isEmpty {
            var fractions: [Int: Double] = [:]
            for sp in touchedSpeakers { fractions[sp] = micFraction(for: sp) }
            continuation.yield(.speakerMicFraction(fractions))
        }
    }

    private func attribute(_ seg: TranscriptSegment) -> [TranscriptSegment] {
        var words = seg.words
        var previous: Int? = nil
        for i in words.indices {
            let sp = speaker(from: words[i].start, to: words[i].end) ?? previous
            words[i].speaker = sp
            if sp != nil { previous = sp }
        }
        // Words before the first attributed one inherit the first known speaker.
        if let first = words.first(where: { $0.speaker != nil })?.speaker {
            for i in words.indices where words[i].speaker == nil { words[i].speaker = first }
        }
        // Smooth isolated single-word speaker flips.
        if words.count >= 3 {
            for i in 1..<(words.count - 1) {
                if words[i].speaker != words[i - 1].speaker, words[i - 1].speaker == words[i + 1].speaker,
                    words[i].end - words[i].start < 0.4
                {
                    words[i].speaker = words[i - 1].speaker
                }
            }
        }
        // Split into runs.
        var out: [TranscriptSegment] = []
        var run: [Word] = []
        func flush() {
            guard let f = run.first, let l = run.last else { return }
            out.append(TranscriptSegment(start: f.start, end: l.end, speaker: f.speaker, attributed: true, words: run))
            run = []
        }
        for w in words {
            if let last = run.last, last.speaker != w.speaker { flush() }
            run.append(w)
        }
        flush()
        return out
    }

    /// Speaker slot with the most activity over [start, end], searching ±0.3 s if none is active.
    private func speaker(from start: Double, to end: Double) -> Int? {
        if let s = bestSpeaker(from: start, to: end) { return s }
        return bestSpeaker(from: start - 0.3, to: end + 0.3)
    }

    private func bestSpeaker(from start: Double, to end: Double) -> Int? {
        let f0 = max(0, Int(start / Self.frameSeconds))
        let f1 = min(diarFrames, max(f0 + 1, Int(end / Self.frameSeconds)))
        guard f1 > f0 else { return nil }
        var score = [Float](repeating: 0, count: numSpeakers)
        for f in f0..<f1 {
            let base = f * numSpeakers
            for s in 0..<numSpeakers {
                let p = probs[base + s]
                if p > 0.5 { score[s] += p }
            }
        }
        var best = -1
        var bestScore: Float = 0
        for s in 0..<numSpeakers where score[s] > bestScore {
            best = s
            bestScore = score[s]
        }
        return best >= 0 ? best : nil
    }

    /// Fraction of this speaker's active time during which the microphone dominated the mix.
    private func micFraction(for speaker: Int) -> Double {
        var active = 0
        var mic = 0
        let chunkFrames = 10  // 100 ms chunks vs 10 ms frames
        for f in 0..<diarFrames where probs[f * numSpeakers + speaker] > 0.5 {
            active += 1
            let c = f / chunkFrames
            if c < micDominant.count, micDominant[c] { mic += 1 }
        }
        return active > 0 ? Double(mic) / Double(active) : 0
    }

    /// Time ranges where exactly one speaker is active, per speaker slot (for voice fingerprints).
    func exclusiveSpeechRanges(minDuration: Double = 0.6) -> [Int: [TimeRange]] {
        var out: [Int: [TimeRange]] = [:]
        var runStart = [Int?](repeating: nil, count: numSpeakers)
        for f in 0...diarFrames {
            var exclusive: Int? = nil
            if f < diarFrames {
                var count = 0
                for s in 0..<numSpeakers where probs[f * numSpeakers + s] > 0.5 {
                    count += 1
                    exclusive = s
                }
                if count != 1 { exclusive = nil }
            }
            for s in 0..<numSpeakers {
                if exclusive == s {
                    if runStart[s] == nil { runStart[s] = f }
                } else if let st = runStart[s] {
                    let range = TimeRange(start: Double(st) * Self.frameSeconds, end: Double(f) * Self.frameSeconds)
                    if range.duration >= minDuration { out[s, default: []].append(range) }
                    runStart[s] = nil
                }
            }
        }
        return out
    }

    /// Streaming diarizer output (10 ms frames × numSpeakers) for the offline re-pass mapping.
    func diarizationProbabilities() -> (probs: [Float], frames: Int, numSpeakers: Int) {
        (probs, diarFrames, numSpeakers)
    }

    // MARK: - Diagnostics

    func diarizationSegments() -> [Nemotron3Segment] {
        Nemotron3Diarizer.segments(probabilities: probs, frameCount: diarFrames, numSpeakers: numSpeakers)
    }
}
