import Foundation
import Security

enum SummaryProvider: String, CaseIterable, Identifiable {
    case none, ollama, openAI, anthropic
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return L("Off")
        case .ollama: return "Ollama (local)"
        case .openAI: return "OpenAI-compatible (OpenAI, LM Studio, OpenRouter…)"
        case .anthropic: return "Anthropic (Claude)"
        }
    }
}

/// Persisted summary configuration. API keys live in the Keychain.
@MainActor
final class SummarySettings: ObservableObject {
    static let defaultInstructions = """
        You write meeting minutes for the participants so they can organise themselves afterwards. \
        Be concrete and faithful to the transcript; never invent facts. Write in the language the meeting was held in. \
        Produce: a short summary (3-6 sentences), the decisions taken, action items with an owner whenever the transcript \
        makes it clear who committed to what (use the speaker names as given), a due date if one was mentioned, and follow-ups \
        (open questions, things to check later, promised deliveries between people).
        """

    @Published var provider: SummaryProvider { didSet { defaults.set(provider.rawValue, forKey: "summary.provider") } }
    @Published var autoSummary: Bool { didSet { defaults.set(autoSummary, forKey: "summary.auto") } }
    @Published var instructions: String { didSet { defaults.set(instructions, forKey: "summary.instructions") } }
    @Published var ollamaURL: String { didSet { defaults.set(ollamaURL, forKey: "summary.ollama.url") } }
    @Published var ollamaModel: String { didSet { defaults.set(ollamaModel, forKey: "summary.ollama.model") } }
    @Published var openAIBaseURL: String { didSet { defaults.set(openAIBaseURL, forKey: "summary.openai.url") } }
    @Published var openAIModel: String { didSet { defaults.set(openAIModel, forKey: "summary.openai.model") } }
    @Published var anthropicModel: String { didSet { defaults.set(anthropicModel, forKey: "summary.anthropic.model") } }
    @Published var openAIKey: String { didSet { Keychain.set(openAIKey, account: "openai") } }
    @Published var anthropicKey: String { didSet { Keychain.set(anthropicKey, account: "anthropic") } }

    private let defaults = UserDefaults.standard

    init() {
        provider = SummaryProvider(rawValue: defaults.string(forKey: "summary.provider") ?? "") ?? .none
        autoSummary = defaults.object(forKey: "summary.auto") as? Bool ?? false
        instructions = defaults.string(forKey: "summary.instructions") ?? Self.defaultInstructions
        ollamaURL = defaults.string(forKey: "summary.ollama.url") ?? "http://localhost:11434"
        ollamaModel = defaults.string(forKey: "summary.ollama.model") ?? "qwen3:8b"
        openAIBaseURL = defaults.string(forKey: "summary.openai.url") ?? "https://api.openai.com/v1"
        openAIModel = defaults.string(forKey: "summary.openai.model") ?? "gpt-4o"
        anthropicModel = defaults.string(forKey: "summary.anthropic.model") ?? "claude-opus-5"
        openAIKey = Keychain.get(account: "openai") ?? ""
        anthropicKey = Keychain.get(account: "anthropic") ?? ""
    }

    func resetInstructions() { instructions = Self.defaultInstructions }

    var isConfigured: Bool {
        switch provider {
        case .none: return false
        case .ollama: return !ollamaModel.isEmpty
        case .openAI: return !openAIKey.isEmpty || openAIBaseURL.contains("localhost") || openAIBaseURL.contains("127.0.0.1")
        case .anthropic: return !anthropicKey.isEmpty
        }
    }

    func makeSummarizer() -> Summarizer? {
        switch provider {
        case .none: return nil
        case .ollama: return OllamaSummarizer(baseURL: ollamaURL, model: ollamaModel)
        case .openAI: return OpenAICompatibleSummarizer(baseURL: openAIBaseURL, apiKey: openAIKey, model: openAIModel)
        case .anthropic: return AnthropicSummarizer(apiKey: anthropicKey, model: anthropicModel)
        }
    }
}

/// Minimal Keychain wrapper for API keys (generic passwords under service "MeetAI").
enum Keychain {
    static let service = "MeetAI"

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query
        add[kSecValueData as String] = value.data(using: .utf8)!
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { AppLog.write("keychain write failed (\(account)): \(status)") }
    }
}
