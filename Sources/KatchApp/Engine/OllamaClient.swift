import AppKit
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

/// Makes sure a local Ollama server is answering, starting it when it is not. Concurrent callers
/// share one launch attempt.
actor OllamaLauncher {
    static let shared = OllamaLauncher()

    private var launching: Task<Bool, Never>?

    /// True when the server at `baseURL` answers. For a localhost URL that does not answer,
    /// launches Ollama.app (or `ollama serve`) and waits up to `wait` seconds for it.
    func ensureRunning(baseURL: String, wait: TimeInterval = 25) async -> Bool {
        if await Self.isReachable(baseURL) { return true }
        guard Self.isLocal(baseURL) else { return false }
        if let launching { return await launching.value }
        let task = Task { await Self.launchAndWait(baseURL: baseURL, wait: wait) }
        launching = task
        let ok = await task.value
        launching = nil
        return ok
    }

    static func isLocal(_ baseURL: String) -> Bool {
        guard let host = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host?.lowercased() else { return false }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    static func isReachable(_ baseURL: String) async -> Bool {
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let url = URL(string: root + "/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: req) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private static func launchAndWait(baseURL: String, wait: TimeInterval) async -> Bool {
        AppLog.write("ollama not reachable at \(baseURL), starting it")
        guard await launch() else {
            AppLog.write("ollama launch: no Ollama.app or ollama binary found")
            return false
        }
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if await isReachable(baseURL) {
                AppLog.write("ollama is up")
                return true
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        AppLog.write("ollama did not answer within \(Int(wait)) s after launch")
        return false
    }

    private static func launch() async -> Bool {
        let fm = FileManager.default
        let appPaths = ["/Applications/Ollama.app", NSHomeDirectory() + "/Applications/Ollama.app"]
        if let path = appPaths.first(where: { fm.fileExists(atPath: $0) }) {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.hides = true
            do {
                _ = try await NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
                return true
            } catch {
                AppLog.write("ollama app launch failed: \(error)")
            }
        }
        let binaries = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"]
        guard let bin = binaries.first(where: { fm.isExecutableFile(atPath: $0) }) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            AppLog.write("ollama serve failed: \(error)")
            return false
        }
    }
}
