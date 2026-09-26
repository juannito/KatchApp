import Foundation

/// Edit these to personalise the About window.
enum AppInfo {
    static let name = "KatchApp"
    static let author = "Juan (@juannito) — freelance product designer & vibe coder"
    static let repositoryURL = URL(string: "https://github.com/juannito/KatchApp")!
    static let coffeeURL = URL(string: "https://buymeacoffee.com/juannito")!
    static let bioEN = "Freelance product designer & vibe coder. I design digital products end to end and build them with AI as my copilot. If KatchApp helps you, buy me a coffee."
    static let bioES = "Freelance product designer y vibe coder. Diseño productos digitales de punta a punta y los construyo con IA como copiloto. Si KatchApp te sirve, invitame un café."
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    struct Credit: Identifiable {
        let id = UUID()
        let name: String
        let role: String
        let license: String
        let url: URL
    }

    static let credits: [Credit] = [
        Credit(name: "FluidAudio", role: "CoreML inference (ASR, diarization, VAD)", license: "Apache-2.0",
            url: URL(string: "https://github.com/FluidInference/FluidAudio")!),
        Credit(name: "NVIDIA Parakeet TDT 0.6B v3", role: "Speech recognition, 25 languages", license: "CC-BY-4.0",
            url: URL(string: "https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3")!),
        Credit(name: "NVIDIA Nemotron 3 Diarization", role: "Streaming speaker diarization", license: "OpenMDW-1.1",
            url: URL(string: "https://huggingface.co/nvidia/Nemotron-3-Diarization")!),
        Credit(name: "Silero VAD", role: "Voice activity detection", license: "MIT",
            url: URL(string: "https://github.com/snakers4/silero-vad")!),
        Credit(name: "AudioCap", role: "Core Audio process tap reference", license: "MIT",
            url: URL(string: "https://github.com/insidegui/AudioCap")!),
    ]
}
