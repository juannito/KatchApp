import Foundation

struct SummaryRequest {
    let instructions: String
    let transcript: String       // "[00:12] Name: text" lines
    let meetingTitle: String
    let meetingDate: Date
}

enum SummaryError: LocalizedError {
    case notConfigured
    case http(Int, String)
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return L("Summary provider is not configured. Open Settings > Summary.")
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(300))"
        case .badResponse(let why): return L("The model returned something unexpected: %@", why)
        case .network(let why): return why
        }
    }
}

protocol Summarizer: Sendable {
    var providerName: String { get }
    var modelName: String { get }
    func complete(system: String, user: String) async throws -> String
}

extension Summarizer {
    func summarize(_ request: SummaryRequest) async throws -> MeetingSummary {
        let system = request.instructions + "\n\n" + PromptBuilder.formatContract
        let user = PromptBuilder.userMessage(request)
        let raw = try await complete(system: system, user: user)
        var parsed = try PromptBuilder.parse(raw)
        parsed.generatedAt = Date()
        parsed.provider = providerName
        parsed.model = modelName
        return parsed
    }
}

enum PromptBuilder {
    static let formatContract = """
        Respond with a single JSON object and nothing else (no markdown fences, no commentary), with exactly these keys:
        {"summary": string, "decisions": [string], "action_items": [{"task": string, "owner": string|null, "due": string|null}], "follow_ups": [string]}
        Use empty arrays when there is nothing to report. Owners must be names that appear in the transcript, or null.
        """

    static func userMessage(_ r: SummaryRequest) -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        return "Meeting: \(r.meetingTitle)\nDate: \(df.string(from: r.meetingDate))\n\nTranscript:\n\(r.transcript)"
    }

    static func transcriptText(_ doc: SessionDocument, names: [Int: String]) -> String {
        doc.turns.map { turn in
            "[\(TimeFormat.clock(turn.start))] \(SpeakerLabel.name(for: turn.speaker, names: names)): \(turn.text)"
        }.joined(separator: "\n")
    }

    /// Tolerant JSON extraction: strips <think> blocks and code fences, then takes the outermost {...}.
    static func parse(_ raw: String) throws -> MeetingSummary {
        var text = raw
        if let r = text.range(of: "</think>") { text = String(text[r.upperBound...]) }
        text = text.replacingOccurrences(of: "```json", with: "```")
        if let open = text.firstIndex(of: "{"), let close = text.lastIndex(of: "}"), open < close {
            text = String(text[open...close])
        }
        guard let data = text.data(using: .utf8) else { throw SummaryError.badResponse("empty") }
        struct Wire: Decodable {
            var summary: String?
            var decisions: [String]?
            var action_items: [WireItem]?
            var follow_ups: [String]?
        }
        struct WireItem: Decodable {
            var task: String?
            var owner: String?
            var due: String?
        }
        do {
            let w = try JSONDecoder().decode(Wire.self, from: data)
            return MeetingSummary(
                summary: w.summary ?? "",
                decisions: w.decisions ?? [],
                actionItems: (w.action_items ?? []).compactMap { i in
                    guard let t = i.task, !t.isEmpty else { return nil }
                    return ActionItem(task: t, owner: i.owner, due: i.due)
                },
                followUps: w.follow_ups ?? [],
                generatedAt: Date(), provider: "", model: "")
        } catch {
            throw SummaryError.badResponse(String(raw.prefix(200)))
        }
    }
}

// MARK: - HTTP helper

enum HTTPJSON {
    static func post(_ url: URL, headers: [String: String], body: [String: Any], timeout: TimeInterval = 300) async throws -> [String: Any] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw SummaryError.network(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw SummaryError.http(code, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SummaryError.badResponse("not a JSON object")
        }
        return json
    }
}

// MARK: - Providers

/// Ollama chat API (http://localhost:11434/api/chat).
struct OllamaSummarizer: Summarizer {
    let baseURL: String
    let model: String
    var providerName: String { "Ollama" }
    var modelName: String { model }

    func complete(system: String, user: String) async throws -> String {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat") else {
            throw SummaryError.notConfigured
        }
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": "json",
            "think": false,
            "options": ["temperature": 0.2, "num_ctx": 32768],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        var json: [String: Any]
        do {
            json = try await HTTPJSON.post(url, headers: [:], body: body, timeout: 900)
        } catch SummaryError.http(let code, let text) where code == 400 && text.lowercased().contains("think") {
            // Models without a thinking mode reject the `think` flag.
            body["think"] = nil
            json = try await HTTPJSON.post(url, headers: [:], body: body, timeout: 900)
        }
        guard let msg = json["message"] as? [String: Any], let content = msg["content"] as? String else {
            throw SummaryError.badResponse("no message.content")
        }
        return content
    }
}

/// OpenAI-compatible chat completions (OpenAI, LM Studio, OpenRouter, vLLM…).
struct OpenAICompatibleSummarizer: Summarizer {
    let baseURL: String
    let apiKey: String
    let model: String
    var providerName: String { "OpenAI-compatible" }
    var modelName: String { model }

    func complete(system: String, user: String) async throws -> String {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions") else {
            throw SummaryError.notConfigured
        }
        var headers: [String: String] = [:]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        let json = try await HTTPJSON.post(url, headers: headers, body: body)
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first,
            let msg = first["message"] as? [String: Any], let content = msg["content"] as? String
        else { throw SummaryError.badResponse("no choices[0].message.content") }
        return content
    }
}

/// Anthropic Messages API (raw HTTP; no Swift SDK).
struct AnthropicSummarizer: Summarizer {
    let apiKey: String
    let model: String
    var providerName: String { "Anthropic" }
    var modelName: String { model }

    func complete(system: String, user: String) async throws -> String {
        guard !apiKey.isEmpty else { throw SummaryError.notConfigured }
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        let headers = [
            "x-api-key": apiKey,
            "anthropic-version": "2023-06-01",
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        let json = try await HTTPJSON.post(url, headers: headers, body: body, timeout: 600)
        if let stop = json["stop_reason"] as? String, stop == "refusal" {
            throw SummaryError.badResponse("refusal")
        }
        guard let content = json["content"] as? [[String: Any]] else { throw SummaryError.badResponse("no content") }
        let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined()
        guard !text.isEmpty else { throw SummaryError.badResponse("empty text") }
        return text
    }
}
