import FluidAudio
import Foundation

/// Speech-recognition models the user can pick. All share the Parakeet TDT pipeline
/// (word timestamps, 15 s window), so they are interchangeable at runtime.
enum AsrModelChoice: String, CaseIterable, Identifiable {
    case parakeetV3, parakeetUltra, parakeetRedux, parakeetV2, nemotronStreaming

    static let defaultsKey = "asrModel"
    var id: String { rawValue }

    static var current: AsrModelChoice {
        get {
            if let env = ProcessInfo.processInfo.environment["KATCHAPP_ASR"], let c = AsrModelChoice(rawValue: env) { return c }
            return AsrModelChoice(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .parakeetV3
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    /// Parakeet family version, nil for the streaming model (different pipeline).
    var parakeetVersion: AsrModelVersion? {
        switch self {
        case .parakeetV3: return .v3
        case .parakeetUltra: return .ultra
        case .parakeetRedux: return .redux
        case .parakeetV2: return .v2
        case .nemotronStreaming: return nil
        }
    }

    var isStreaming: Bool { self == .nemotronStreaming }
    /// Nemotron variant and chunk tier (1.12 s keeps punctuation reliable on long sessions).
    /// "auto" selects the full-vocabulary variant with automatic language detection; the Latin-only
    /// variant ("en-US" etc.) lost punctuation and casing in auto mode during testing.
    static var nemotronLanguage: String { ProcessInfo.processInfo.environment["KATCHAPP_NEMOTRON_LANG"] ?? "auto" }
    static let nemotronChunkMs = 1120

    var title: String {
        switch self {
        case .parakeetV3: return "Parakeet TDT 0.6B v3"
        case .parakeetUltra: return "Parakeet Ultra"
        case .parakeetRedux: return "Parakeet Redux"
        case .parakeetV2: return "Parakeet TDT 0.6B v2"
        case .nemotronStreaming: return "Nemotron 3.5 ASR Streaming"
        }
    }

    var shortName: String {
        switch self {
        case .parakeetV3: return "Parakeet v3"
        case .parakeetUltra: return "Parakeet Ultra"
        case .parakeetRedux: return "Parakeet Redux"
        case .parakeetV2: return "Parakeet v2"
        case .nemotronStreaming: return "Nemotron 3.5"
        }
    }

    var summary: String {
        switch self {
        case .parakeetV3: return L("Balanced default. 25 languages, word timestamps.")
        case .parakeetUltra: return L("Most accurate. Same 25 languages and speed as v3, larger download.")
        case .parakeetRedux: return L("Lightest download. Same 25 languages; slightly less accurate. Best for tight disk or 8 GB Macs.")
        case .parakeetV2: return L("English only. A bit more accurate than v3 on English.")
        case .nemotronStreaming: return L("Live streaming: text appears every second while people talk, no need to wait for a pause. Slightly less accurate than Parakeet v3.")
        }
    }

    var languages: String {
        switch self {
        case .parakeetV2: return L("English")
        case .nemotronStreaming: return L("~40 languages, auto-detected")
        default: return L("25 languages (English, Spanish, Portuguese, French, German, Italian…)")
        }
    }

    /// Approximate on-disk size of the model folder.
    var sizeMB: Int {
        switch self {
        case .parakeetV3: return 480
        case .parakeetUltra: return 640
        case .parakeetRedux: return 220
        case .parakeetV2: return 480
        case .nemotronStreaming: return 600
        }
    }

    var license: String {
        switch self {
        case .parakeetUltra, .parakeetRedux: return "CC-BY-4.0 (moondream post-training)"
        case .nemotronStreaming: return "OpenMDW-1.1"
        default: return "CC-BY-4.0"
        }
    }

    /// Hugging Face repo id (FluidAudio keeps its registry internal, so mirror the names here).
    var repoID: String {
        switch self {
        case .parakeetV3: return "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        case .parakeetUltra: return "FluidInference/parakeet-ultra-coreml"
        case .parakeetRedux: return "FluidInference/parakeet-redux-coreml"
        case .parakeetV2: return "FluidInference/parakeet-tdt-0.6b-v2-coreml"
        case .nemotronStreaming: return "FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML"
        }
    }

    var repoURL: URL { URL(string: "https://huggingface.co/\(repoID)")! }

    var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models/\(repoID.split(separator: "/").last!)", isDirectory: true)
        if isStreaming {
            let lang = StreamingNemotronMultilingualAsrManager.languageDirectory(for: Self.nemotronLanguage)
            return base.appendingPathComponent("\(lang)/\(Self.nemotronChunkMs)ms", isDirectory: true)
        }
        return base
    }

    /// Models shown in Settings (v2 is wired but not offered yet).
    static let offered: [AsrModelChoice] = [.parakeetV3, .nemotronStreaming, .parakeetUltra, .parakeetRedux]

    var isDownloaded: Bool {
        if isStreaming { return FileManager.default.fileExists(atPath: folderURL.appendingPathComponent("encoder.mlmodelc").path) }
        return AsrModels.modelsExist(at: folderURL)
    }

    var downloadedSize: Int64 {
        SessionStore.folderSize(folderURL)
    }

    func deleteDownload() throws {
        try FileManager.default.removeItem(at: folderURL)
    }
}
