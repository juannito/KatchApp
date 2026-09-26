import Foundation
import SwiftUI

/// Runs summaries in the background and persists them next to each session.
@MainActor
final class SummaryService: ObservableObject {
    static let jsonFile = "summary.json"
    static let markdownFile = "summary.md"

    @Published private(set) var inProgress: Set<String> = []   // session folder paths
    @Published private(set) var errors: [String: String] = [:]  // folder path -> message
    @Published private(set) var version = 0                     // bump when a summary is written

    let settings: SummarySettings

    init(settings: SummarySettings) {
        self.settings = settings
    }

    func isRunning(_ folder: URL) -> Bool { inProgress.contains(folder.path) }
    func error(for folder: URL) -> String? { errors[folder.path] }

    static func read(at folder: URL) -> MeetingSummary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(jsonFile)) else { return nil }
        return try? decoder.decode(MeetingSummary.self, from: data)
    }

    static func write(_ summary: MeetingSummary, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(to: folder.appendingPathComponent(jsonFile), options: .atomic)
        try summary.markdown().write(to: folder.appendingPathComponent(markdownFile), atomically: true, encoding: .utf8)
    }

    /// Called after a session is saved; runs only when auto-summary is on.
    func generateIfAuto(folder: URL, contactNames: [String: String]) {
        guard settings.autoSummary, settings.isConfigured else { return }
        generate(folder: folder, contactNames: contactNames)
    }

    func generate(folder: URL, contactNames: [String: String]) {
        guard !isRunning(folder) else { return }
        guard let summarizer = settings.makeSummarizer(), settings.isConfigured else {
            errors[folder.path] = SummaryError.notConfigured.localizedDescription
            return
        }
        guard let doc = SessionStore.readDocument(at: folder) else { return }
        let names = doc.effectiveNames(contactNames: contactNames)
        let request = SummaryRequest(
            instructions: settings.instructions,
            transcript: PromptBuilder.transcriptText(doc, names: names),
            meetingTitle: doc.displayTitle,
            meetingDate: doc.startedAt)
        inProgress.insert(folder.path)
        errors[folder.path] = nil
        AppLog.write("summary started: \(folder.lastPathComponent) via \(summarizer.providerName)/\(summarizer.modelName)")
        Task {
            do {
                let summary = try await summarizer.summarize(request)
                try Self.write(summary, to: folder)
                AppLog.write("summary done: \(folder.lastPathComponent) (\(summary.actionItems.count) action items)")
                version += 1
            } catch {
                AppLog.write("summary FAILED: \(folder.lastPathComponent): \(error)")
                errors[folder.path] = error.localizedDescription
            }
            inProgress.remove(folder.path)
        }
    }
}
