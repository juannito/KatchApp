import AppKit
import Foundation
import SwiftUI

struct SessionSummary: Identifiable, Hashable {
    let id: String          // path relative to the sessions root ("Project/2026-…" or "2026-…")
    let folder: URL
    let title: String
    let startedAt: Date
    let duration: TimeInterval
    let segmentCount: Int
    let speakerCount: Int
    let project: String?
    let contactIDs: Set<String>
    let platformName: String?
    /// Lowercased title + project + speaker names + transcript text, for the sidebar search.
    let searchText: String

    /// Case- and accent-insensitive; every word of the query must appear somewhere.
    func matches(_ query: String) -> Bool {
        let q = Self.fold(query)
        guard !q.isEmpty else { return true }
        return q.split(separator: " ").allSatisfy { searchText.contains($0) }
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Sessions folder (user-configurable), projects (subfolders) and the history list.
@MainActor
final class SessionStore: ObservableObject {
    nonisolated static let rootDefaultsKey = "sessionsRootPath"
    nonisolated static let transcriptFile = "transcript.json"
    nonisolated static let markdownFile = "transcript.md"
    nonisolated static let audioFile = "audio.wav"
    nonisolated static let projectsFile = "projects.json"
    nonisolated static let reservedFolders: Set<String> = [ContactStore.avatarsFolder]

    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var projects: [String] = []
    @Published private(set) var hiddenProjects: Set<String> = []
    /// Not persisted on purpose: hidden projects stay hidden after every launch.
    @Published var showHidden = false
    @Published private(set) var rootURL: URL

    private struct ProjectsFile: Codable {
        var hidden: [String]
    }

    /// No disk access here: the first read of ~/Documents can block on macOS's permission
    /// dialog, and that must happen after the window is on screen (see `reload()`).
    init() {
        rootURL = Self.storedRoot()
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("KatchApp", isDirectory: true)
    }

    private static func storedRoot() -> URL {
        if let path = UserDefaults.standard.string(forKey: rootDefaultsKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultRoot()
    }

    func setRoot(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.rootDefaultsKey)
        rootURL = url
        reload()
    }

    func resetRoot() {
        UserDefaults.standard.removeObject(forKey: Self.rootDefaultsKey)
        rootURL = Self.defaultRoot()
        reload()
    }

    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("Use this folder")
        panel.message = L("Choose where KatchApp saves its sessions")
        panel.directoryURL = rootURL
        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url)
        }
    }

    // MARK: - Projects

    var visibleProjects: [String] {
        showHidden ? projects : projects.filter { !hiddenProjects.contains($0) }
    }

    func isHidden(_ project: String?) -> Bool {
        guard let project else { return false }
        return hiddenProjects.contains(project)
    }

    func projectURL(_ project: String?) -> URL {
        guard let project, !project.isEmpty else { return rootURL }
        return rootURL.appendingPathComponent(project, isDirectory: true)
    }

    @discardableResult
    func createProject(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        guard !trimmed.isEmpty, !Self.reservedFolders.contains(trimmed) else { return nil }
        do {
            try FileManager.default.createDirectory(at: projectURL(trimmed), withIntermediateDirectories: true)
        } catch {
            AppLog.write("create project failed: \(error)")
            return nil
        }
        reload()
        return trimmed
    }

    func setHidden(_ project: String, _ hidden: Bool) {
        if hidden { hiddenProjects.insert(project) } else { hiddenProjects.remove(project) }
        persistProjects()
        reload()
    }

    private func persistProjects() {
        do {
            let data = try JSONEncoder().encode(ProjectsFile(hidden: hiddenProjects.sorted()))
            try data.write(to: rootURL.appendingPathComponent(Self.projectsFile), options: .atomic)
        } catch {
            AppLog.write("projects save failed: \(error)")
        }
    }

    // MARK: - Folders

    func makeSessionFolder(date: Date, project: String? = nil) throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = projectURL(project).appendingPathComponent(df.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Moves a session folder into another project (nil = root). Returns the new folder.
    func move(sessionFolder: URL, toProject project: String?) -> URL? {
        let target = projectURL(project).appendingPathComponent(sessionFolder.lastPathComponent, isDirectory: true)
        guard target.standardizedFileURL != sessionFolder.standardizedFileURL else { return sessionFolder }
        do {
            try FileManager.default.createDirectory(at: projectURL(project), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: sessionFolder, to: target)
            if var doc = Self.readDocument(at: target) {
                doc.project = project
                try Self.write(doc, to: target)
            }
        } catch {
            AppLog.write("move session failed: \(error)")
            return nil
        }
        reload()
        return target
    }

    // MARK: - History

    private struct Scan: Sendable {
        var sessions: [SessionSummary]
        var projects: [String]
        var hidden: Set<String>
    }

    /// Rescans the sessions folder on a background thread and publishes the result.
    func reload() {
        let root = rootURL
        Task.detached(priority: .userInitiated) {
            let scan = Self.scan(root: root)
            await MainActor.run {
                guard self.rootURL == root else { return }
                self.hiddenProjects = scan.hidden
                self.projects = scan.projects
                self.sessions = scan.sessions
            }
        }
    }

    nonisolated private static func scan(root: URL) -> Scan {
        let fm = FileManager.default
        var foundSessions: [SessionSummary] = []
        var foundProjects: [String] = []
        var hidden: Set<String> = []
        if let data = try? Data(contentsOf: root.appendingPathComponent(projectsFile)),
            let file = try? JSONDecoder().decode(ProjectsFile.self, from: data)
        {
            hidden = Set(file.hidden)
        }
        if let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) {
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                let name = entry.lastPathComponent
                if reservedFolders.contains(name) { continue }
                if let summary = summary(for: entry, project: nil) {
                    foundSessions.append(summary)
                } else {
                    foundProjects.append(name)
                    if let subs = try? fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: [.isDirectoryKey]) {
                        for sub in subs {
                            if let summary = summary(for: sub, project: name) { foundSessions.append(summary) }
                        }
                    }
                }
            }
        }
        return Scan(
            sessions: foundSessions.sorted { $0.startedAt > $1.startedAt },
            projects: foundProjects.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
            hidden: hidden)
    }

    /// Sessions visible under the current privacy setting, optionally filtered by project.
    func sessions(project filter: String??) -> [SessionSummary] {
        sessions.filter { s in
            if !showHidden, isHidden(s.project) { return false }
            switch filter {
            case .none: return true                      // all
            case .some(.none): return s.project == nil   // no project
            case .some(.some(let p)): return s.project == p
            }
        }
    }

    func sessions(withContact id: String) -> [SessionSummary] {
        sessions.filter { $0.contactIDs.contains(id) && (showHidden || !isHidden($0.project)) }
    }

    nonisolated private static func summary(for folder: URL, project: String?) -> SessionSummary? {
        let json = folder.appendingPathComponent(transcriptFile)
        guard FileManager.default.fileExists(atPath: json.path), let doc = readDocument(at: folder) else { return nil }
        let id = project.map { "\($0)/\(folder.lastPathComponent)" } ?? folder.lastPathComponent
        var text = [doc.displayTitle, project ?? "", doc.platformName ?? ""] + Array(doc.speakerNames.values)
        text.append(contentsOf: doc.segments.map(\.text))
        if let summary = try? String(contentsOf: folder.appendingPathComponent("summary.md"), encoding: .utf8) {
            text.append(summary)
        }
        return SessionSummary(
            id: id, folder: folder, title: doc.displayTitle, startedAt: doc.startedAt, duration: doc.duration,
            segmentCount: doc.segments.count, speakerCount: Set(doc.segments.compactMap(\.speaker)).count,
            project: project, contactIDs: Set(doc.speakerContacts.values), platformName: doc.platformName,
            searchText: SessionSummary.fold(text.joined(separator: " ")))
    }

    nonisolated static func readDocument(at folder: URL) -> SessionDocument? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(transcriptFile)) else { return nil }
        do {
            return try decoder.decode(SessionDocument.self, from: data)
        } catch {
            AppLog.write("cannot decode \(folder.lastPathComponent): \(error)")
            return nil
        }
    }

    nonisolated static func write(_ doc: SessionDocument, to folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(doc).write(to: folder.appendingPathComponent(transcriptFile), options: .atomic)
        try doc.markdown().write(to: folder.appendingPathComponent(markdownFile), atomically: true, encoding: .utf8)
    }

    func save(_ doc: SessionDocument, to folder: URL) {
        do {
            try Self.write(doc, to: folder)
            reload()
        } catch {
            AppLog.write("save failed: \(error)")
        }
    }

    /// Total size of a session folder (audio.wav dominates), in bytes.
    nonisolated static func folderSize(_ folder: URL) -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }

    /// Permanently deletes a session folder (audio, transcript, summary). Not recoverable.
    func deletePermanently(_ session: SessionSummary) {
        do {
            try FileManager.default.removeItem(at: session.folder)
            AppLog.write("session deleted permanently: \(session.id)")
        } catch {
            AppLog.write("permanent delete failed: \(error)")
        }
        reload()
    }

    /// Moves the session folder to the Trash (recoverable).
    func delete(_ session: SessionSummary) {
        do {
            try FileManager.default.trashItem(at: session.folder, resultingItemURL: nil)
        } catch {
            AppLog.write("trash failed: \(error)")
        }
        reload()
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
