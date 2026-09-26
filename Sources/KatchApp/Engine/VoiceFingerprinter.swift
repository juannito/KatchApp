import FluidAudio
import Foundation

/// Speaker embeddings (CAM++, 192-d) for recognising people across sessions.
actor VoiceFingerprinter {
    private let embedder: CampPlusEmbedder
    static let chunkSeconds = 6.0
    static let maxSeconds = 36.0
    static let minSeconds = 2.5

    init(embedder: CampPlusEmbedder) {
        self.embedder = embedder
    }

    static func load() async throws -> VoiceFingerprinter {
        VoiceFingerprinter(embedder: try await CampPlusEmbedder.load())
    }

    /// Embeds the audio inside `ranges` (seconds) of a 16 kHz session recording.
    /// Returns nil when there is not enough clean speech.
    func embed(sessionAudio audio: [Float], ranges: [TimeRange]) async throws -> [Float]? {
        let sr = 16000.0
        var speech: [Float] = []
        for r in ranges.sorted(by: { ($0.end - $0.start) > ($1.end - $1.start) }) {
            let lo = max(0, Int(r.start * sr))
            let hi = min(audio.count, Int(r.end * sr))
            guard hi > lo else { continue }
            speech.append(contentsOf: audio[lo..<hi])
            if Double(speech.count) / sr >= Self.maxSeconds { break }
        }
        guard Double(speech.count) / sr >= Self.minSeconds else { return nil }
        let chunk = Int(Self.chunkSeconds * sr)
        var sum = [Float](repeating: 0, count: CampPlusEmbedder.embeddingDim)
        var count = 0
        var i = 0
        while i < speech.count {
            let end = min(speech.count, i + chunk)
            if Double(end - i) / sr < 1.5, count > 0 { break }
            let e = try await embedder.embed(audio: Array(speech[i..<end]))
            for k in 0..<sum.count { sum[k] += e[k] }
            count += 1
            i = end
        }
        guard count > 0 else { return nil }
        return Self.normalized(sum)
    }

    static func normalized(_ v: [Float]) -> [Float] {
        let norm = max(v.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-9)
        return v.map { $0 / norm }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        return CampPlusEmbedder.cosine(a, b)
    }
}
