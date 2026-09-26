import CoreML
import FluidAudio
import Foundation

struct LoadedModels: @unchecked Sendable {
    let asr: AsrManager
    let vad: VadManager
    let diarizerModels: Nemotron3Models
    let diarizerConfig: Nemotron3Config
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
        progress("Downloading VAD (Silero)…", 0)
        let vad = try await VadManager(config: VadConfig(), progressHandler: { p in
            progress("Downloading VAD (Silero)…", p.fractionCompleted)
        })

        progress("Downloading ASR (Parakeet TDT 0.6B v3)…", 0)
        let asrModels = try await AsrModels.downloadAndLoad(
            version: .v3,
            progressHandler: { p in progress("Downloading ASR (Parakeet TDT 0.6B v3)…", p.fractionCompleted) })
        let asr = AsrManager(config: .default)
        try await asr.loadModels(asrModels)

        progress("Downloading diarization (Nemotron 3)…", 0)
        let diar = try await Nemotron3Models.loadFromHuggingFace(
            config: diarizerConfig,
            progressHandler: { p in progress("Downloading diarization (Nemotron 3)…", p.fractionCompleted) })

        progress("Models ready", 1)
        AppLog.write("models ready (diarizer preset: \(diarizerConfig.modelFileName))")
        return LoadedModels(asr: asr, vad: vad, diarizerModels: diar, diarizerConfig: diarizerConfig)
    }
}
