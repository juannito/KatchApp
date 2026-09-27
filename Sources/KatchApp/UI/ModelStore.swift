import Foundation
import SwiftUI

@MainActor
final class ModelStore: ObservableObject {
    enum State: Equatable {
        case idle
        case loading(step: String, fraction: Double)
        case ready
        case failed(String)
    }

    @Published var state: State = .idle
    private(set) var models: LoadedModels?
    /// Models already loaded in this session, keyed by speech model, so switching back is instant.
    private var cache: [AsrModelChoice: LoadedModels] = [:]

    var isReady: Bool { state == .ready }

    func loadIfNeeded() async {
        guard case .idle = state else { return }
        if let cached = cache[AsrModelChoice.current] {
            models = cached
            state = .ready
            AppLog.write("models switched from cache (asr: \(cached.asrChoice.rawValue))")
            return
        }
        state = .loading(step: "Preparing models…", fraction: 0)
        do {
            let loaded = try await ModelLoader.load { [weak self] step, fraction in
                Task { @MainActor in
                    guard let self, case .loading = self.state else { return }
                    self.state = .loading(step: step, fraction: fraction)
                }
            }
            models = loaded
            cache[loaded.asrChoice] = loaded
            state = .ready
        } catch {
            AppLog.write("model load FAILED: \(error)")
            state = .failed(error.localizedDescription)
        }
    }

    func retry() async {
        state = .idle
        await loadIfNeeded()
    }

    /// Reloads every model (used after the user picks another speech model).
    func reload() async {
        models = nil
        state = .idle
        await loadIfNeeded()
    }
}
