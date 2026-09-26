import AppKit
import Foundation
import SwiftUI

struct SessionSummary: Identifiable, Hashable {
    let id: String          // folder name
    let folder: URL
    let title: String
    let startedAt: Date
    let duration: TimeInterval
    let segmentCount: Int
    let speakerCount: Int
}

/// Sessions folder (user-configurable) + history of saved sessions.
@MainActor
final class SessionStore: ObservableObject {
    static let rootDefaultsKey = "sessionsRootPath"
    static let transcriptFile = "transcript.json"
    static let markdownFile = "transcript.md"
    static let audioFile = "audio.wav"

    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var rootURL: URL

    init() {
        rootURL = Self.storedRoot()
        reload()
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetAI", isDirectory: true)
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
        panel.message = L("Choose where MeetAI saves its sessions")
        panel.directoryURL = rootURL
        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url)
        }
    }

    // MARK: - Folders

    func makeSessionFolder(date: Date) throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let url = rootURL.appendingPathComponent(df.string(from: date), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - History

    func reload() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) else {
            sessions = []
            return
        }
        var found: [SessionSummary] = []
        for folder in entries {
            let json = folder.appendingPathComponent(Self.transcriptFile)
            guard fm.fileExists(atPath: json.path), let doc = Self.readDocument(at: folder) else { continue }
            found.append(SessionSummary(
                id: folder.lastPathComponent,
                folder: folder,
                title: doc.displayTitle,
                startedAt: doc.startedAt,
                duration: doc.duration,
                segmentCount: doc.segments.count,
                speakerCount: Set(doc.segments.compactMap(\.speaker)).count))
        }
        sessions = found.sorted { $0.startedAt > $1.startedAt }
    }

    static func readDocument(at folder: URL) -> SessionDocument? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(transcriptFile)) else { return nil }
        return try? decoder.decode(SessionDocument.self, from: data)
    }

    static func write(_ doc: SessionDocument, to folder: URL) throws {
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
