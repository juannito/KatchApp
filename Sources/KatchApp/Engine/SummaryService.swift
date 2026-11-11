import Foundation
import SwiftUI

struct ChatMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    var role: String          // "user" | "assistant"
    var text: String
    var date = Date()
    /// Assistant turns that rewrote the minutes.
    var changedSummary = false
}

/// Runs summaries in the background and persists them next to each session.
@MainActor
final class SummaryService: ObservableObject {
    nonisolated static let jsonFile = "summary.json"
    nonisolated static let markdownFile = "summary.md"
    nonisolated static let chatFile = "summary-chat.json"
    nonisolated static let historyFolder = "summary-history"

    @Published private(set) var inProgress: Set<String> = []   // session folder paths
    @Published private(set) var errors: [String: String] = [:]  // folder path -> message
    @Published private(set) var version = 0                     // bump when a summary is written
    @Published private(set) var chats: [String: [ChatMessage]] = [:]
    @Published private(set) var chatBusy: Set<String> = []
    @Published private(set) var chatErrors: [String: String] = [:]

    let settings: SummarySettings

    init(settings: SummarySettings) {
        self.settings = settings
    }

    func isRunning(_ folder: URL) -> Bool { inProgress.contains(folder.path) }
    func error(for folder: URL) -> String? { errors[folder.path] }

    nonisolated static func read(at folder: URL) -> MeetingSummary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(jsonFile)) else { return nil }
        return try? decoder.decode(MeetingSummary.self, from: data)
    }

    /// Writes the summary; the one being replaced is first kept in `summary-history/`, so a
    /// regenerate, a manual edit or a chat change can always be undone.
    nonisolated static func write(_ summary: MeetingSummary, to folder: URL) throws {
        snapshotCurrent(at: folder)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(summary).write(to: folder.appendingPathComponent(jsonFile), options: .atomic)
        try summary.markdown().write(to: folder.appendingPathComponent(markdownFile), atomically: true, encoding: .utf8)
    }

    nonisolated static func snapshotCurrent(at folder: URL) {
        let fm = FileManager.default
        let current = folder.appendingPathComponent(jsonFile)
        guard fm.fileExists(atPath: current.path) else { return }
        let dir = folder.appendingPathComponent(historyFolder, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        try? fm.copyItem(at: current, to: dir.appendingPathComponent(f.string(from: Date()) + ".json"))
    }

    /// Previous versions, newest first.
    nonisolated static func history(at folder: URL) -> [(url: URL, summary: MeetingSummary)] {
        let dir = folder.appendingPathComponent(historyFolder, isDirectory: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? decoder.decode(MeetingSummary.self, from: $0) }.map { (url, $0) } }
    }

    /// Saves a hand-edited summary.
    func saveEdited(_ summary: MeetingSummary, folder: URL) {
        var s = summary
        s.edited = true
        do {
            try Self.write(s, to: folder)
            AppLog.write("summary edited by hand: \(folder.lastPathComponent)")
            version += 1
        } catch {
            errors[folder.path] = error.localizedDescription
        }
    }

    /// Puts an older version back as the current one (the current one goes to history first).
    func restore(_ summary: MeetingSummary, folder: URL) {
        do {
            try Self.write(summary, to: folder)
            AppLog.write("summary restored from history: \(folder.lastPathComponent)")
            version += 1
        } catch {
            errors[folder.path] = error.localizedDescription
        }
    }

    // MARK: - Chat

    /// Reads the saved conversation into `chats`. Call from `.task`, never from a view body
    /// (it publishes).
    func loadChat(_ folder: URL) {
        guard chats[folder.path] == nil else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        chats[folder.path] = (try? Data(contentsOf: folder.appendingPathComponent(Self.chatFile)))
            .flatMap { try? decoder.decode([ChatMessage].self, from: $0) } ?? []
    }

    func messages(for folder: URL) -> [ChatMessage] { chats[folder.path] ?? [] }

    func isChatting(_ folder: URL) -> Bool { chatBusy.contains(folder.path) }
    func chatError(for folder: URL) -> String? { chatErrors[folder.path] }

    private func persistChat(_ folder: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(chats[folder.path] ?? []) {
            try? data.write(to: folder.appendingPathComponent(Self.chatFile), options: .atomic)
        }
    }

    func clearChat(folder: URL) {
        chats[folder.path] = []
        persistChat(folder)
    }

    /// Sends one message. The model re-reads the transcript and the current minutes and may
    /// answer with a rewritten summary, which replaces the current one (history keeps the old).
    func sendChat(folder: URL, contactNames: [String: String], text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isChatting(folder), !isRunning(folder) else { return }
        guard let summarizer = settings.makeSummarizer(), settings.isConfigured else {
            chatErrors[folder.path] = SummaryError.notConfigured.localizedDescription
            return
        }
        guard let doc = SessionStore.readDocument(at: folder), let current = Self.read(at: folder) else { return }
        loadChat(folder)
        var thread = messages(for: folder)
        thread.append(ChatMessage(role: "user", text: trimmed))
        chats[folder.path] = thread
        persistChat(folder)
        chatBusy.insert(folder.path)
        chatErrors[folder.path] = nil
        // Earlier assistant turns are replayed in the JSON shape the contract asks for, so the
        // model keeps answering in that shape.
        // The list must start with a user turn (Anthropic rejects anything else), so a window that
        // begins mid-exchange drops its leading assistant replies.
        let window = Array(thread.suffix(20).drop { $0.role != "user" })
        let history: [ChatTurn] = window.map { m in
            if m.role == "assistant" {
                let reply = (try? JSONSerialization.data(withJSONObject: ["reply": m.text, "updated_minutes": NSNull()]))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? m.text
                return ChatTurn(role: "assistant", content: reply)
            }
            return ChatTurn(role: "user", content: m.text)
        }
        let transcript = PromptBuilder.transcriptText(doc, names: doc.effectiveNames(contactNames: contactNames))
        let title = doc.displayTitle
        let instructions = settings.instructions
        AppLog.write("summary chat: \(folder.lastPathComponent) via \(summarizer.providerName)/\(summarizer.modelName)")
        Task {
            do {
                let result = try await summarizer.refine(
                    transcript: transcript, current: current, meetingTitle: title, history: history, instructions: instructions)
                var changed = false
                if let updated = result.updated {
                    try Self.write(updated, to: folder)
                    changed = true
                    version += 1
                }
                chats[folder.path, default: []].append(ChatMessage(role: "assistant", text: result.reply, changedSummary: changed))
                persistChat(folder)
                AppLog.write("summary chat done: \(folder.lastPathComponent) changed=\(changed)")
            } catch {
                AppLog.write("summary chat FAILED: \(folder.lastPathComponent): \(error)")
                chatErrors[folder.path] = error.localizedDescription
            }
            chatBusy.remove(folder.path)
        }
    }

    /// Called after a session is saved; runs only when auto-summary is on.
    func generateIfAuto(folder: URL, contactNames: [String: String]) {
        guard settings.autoSummary, settings.isConfigured else { return }
        generate(folder: folder, contactNames: contactNames)
    }

    func generate(folder: URL, contactNames: [String: String]) {
        guard !isRunning(folder), !isChatting(folder) else { return }
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
