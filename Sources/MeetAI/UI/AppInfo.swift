import Foundation

/// Edit these to personalise the About window.
enum AppInfo {
    static let name = "MeetAI"
    static let author = "Juan (@juannito)"
    static let repositoryURL = URL(string: "https://github.com/juannito/openmeet")!
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
