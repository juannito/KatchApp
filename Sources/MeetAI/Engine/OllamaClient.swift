import Foundation

/// Minimal Ollama management client: list installed models and pull new ones with progress.
struct OllamaClient: Sendable {
    let baseURL: String

    private var root: String { baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }

    func installedModels() async throws -> [String] {
        guard let url = URL(string: root + "/api/tags") else { throw SummaryError.notConfigured }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SummaryError.network("tags failed")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let models = json["models"] as? [[String: Any]]
        else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    /// Streams `/api/pull` progress (0...1). Completes when Ollama reports "success".
    func pull(model: String, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        guard let url = URL(string: root + "/api/pull") else { throw SummaryError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 3600
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw SummaryError.http((response as? HTTPURLResponse)?.statusCode ?? 0, "pull failed")
        }
        var succeeded = false
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let err = json["error"] as? String { throw SummaryError.network(err) }
            let status = json["status"] as? String ?? ""
            if let total = json["total"] as? Double, total > 0 {
                let completed = json["completed"] as? Double ?? 0
                progress(completed / total, status)
            } else {
                progress(status == "success" ? 1 : 0, status)
            }
            if status == "success" { succeeded = true }
        }
        guard succeeded else { throw SummaryError.badResponse("pull ended without success") }
    }
}
