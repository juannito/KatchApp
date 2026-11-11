import CoreML
import FluidAudio
import Foundation

struct LoadedModels: @unchecked Sendable {
    let asrChoice: AsrModelChoice
    /// Parakeet (segment) ASR, nil when the streaming model is selected.
    let asr: AsrManager?
    /// Nemotron 3.5 streaming ASR shared weights, nil otherwise.
    let streamingAsr: SharedNemotronMultilingualModels?
    let vad: VadManager
    let diarizerModels: Nemotron3Models
    let diarizerConfig: Nemotron3Config
    let fingerprinter: VoiceFingerprinter?
}

enum ModelLoader {
    /// Diarizer preset. `low` = NVIDIA's reference streaming profile, 1.04 s latency.
    /// Override with MEETAI_DIAR_PRESET (fast, fast32, fast128, verylow, ultra, offline).
    static var diarizerConfig: Nemotron3Config {
        if let name = ProcessInfo.processInfo.environment["MEETAI_DIAR_PRESET"],
            let preset = Nemotron3Config.preset(named: name)
        {
            return preset
        }
        return .low
    }

    typealias Progress = @Sendable (_ step: String, _ fraction: Double) -> Void

    static func load(progress: @escaping Progress) async throws -> LoadedModels {
        let t0 = Date()
        defer { AppLog.write(String(format: "model load finished in %.1fs", Date().timeIntervalSince(t0))) }
        AppLog.write("model load started")
        // Per-step timings: a cold start is dominated by CoreML compiling for the Neural Engine.
        // (Loading the models concurrently was measured and is no faster: the compiler serialises.)
        var lap = Date()
        func lapLog(_ what: String) {
            AppLog.write(String(format: "  %@ loaded in %.1fs", what, Date().timeIntervalSince(lap)))
            lap = Date()
        }
        progress("Downloading VAD (Silero)…", 0)
        let vad = try await VadManager(config: VadConfig(), progressHandler: { p in
            progress("Downloading VAD (Silero)…", p.fractionCompleted)
        })

        lapLog("VAD")
        let choice = AsrModelChoice.current
        let asrStep = choice.isDownloaded ? "Loading ASR (\(choice.title))…" : "Downloading ASR (\(choice.title))…"
        progress(asrStep, 0)
        var asr: AsrManager? = nil
        var streaming: SharedNemotronMultilingualModels? = nil
        if let version = choice.parakeetVersion {
            let asrModels = try await AsrModels.downloadAndLoad(
                version: version,
                progressHandler: { p in progress(asrStep, p.fractionCompleted) })
            let manager = AsrManager(config: .default)
            try await manager.loadModels(asrModels)
            asr = manager
        } else {
            streaming = try await StreamingNemotronMultilingualAsrManager.downloadAndPreloadShared(
                languageCode: AsrModelChoice.nemotronLanguage, chunkMs: AsrModelChoice.nemotronChunkMs,
                progressHandler: { p in progress(asrStep, p.fractionCompleted) })
        }

        lapLog("ASR")
        progress("Downloading diarization (Nemotron 3)…", 0)
        let diar = try await Nemotron3Models.loadFromHuggingFace(
            config: diarizerConfig,
            progressHandler: { p in progress("Downloading diarization (Nemotron 3)…", p.fractionCompleted) })

        lapLog("diarizer")
        progress("Downloading voice ID (CAM++)…", 0)
        var fingerprinter: VoiceFingerprinter? = nil
        do {
            fingerprinter = try await VoiceFingerprinter.load()
        } catch {
            AppLog.write("voice fingerprint model unavailable: \(error)")
        }

        lapLog("voice ID")
        progress("Models ready", 1)
        AppLog.write("models ready (asr: \(choice.rawValue), diarizer preset: \(diarizerConfig.modelFileName), voice id: \(fingerprinter != nil))")
        return LoadedModels(
            asrChoice: choice, asr: asr, streamingAsr: streaming, vad: vad, diarizerModels: diar, diarizerConfig: diarizerConfig, fingerprinter: fingerprinter)
    }
}
