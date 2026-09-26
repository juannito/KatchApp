import AppKit
import Foundation
import SwiftUI

struct Contact: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var avatarFile: String?
    var embeddings: [[Float]]
    var createdAt: Date

    var centroid: [Float]? {
        guard let first = embeddings.first else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for e in embeddings where e.count == first.count {
            for i in 0..<sum.count { sum[i] += e[i] }
        }
        return VoiceFingerprinter.normalized(sum)
    }

    /// Best similarity between an embedding and this contact's voice samples.
    func similarity(to embedding: [Float]) -> Float {
        var best: Float = 0
        if let c = centroid { best = VoiceFingerprinter.cosine(c, embedding) }
        for e in embeddings { best = max(best, VoiceFingerprinter.cosine(e, embedding)) }
        return best
    }
}

struct ContactMatch: Hashable {
    let contactID: String
    let score: Float
}

/// contacts.json + avatars/ inside the sessions folder.
@MainActor
final class ContactStore: ObservableObject {
    static let fileName = "contacts.json"
    nonisolated static let avatarsFolder = "avatars"
    static let suggestThreshold: Float = 0.70  // synthetic voices score ~0.72 across speakers; calibrate with real voices
    static let maxEmbeddingsPerContact = 12

    @Published private(set) var contacts: [Contact] = []
    private(set) var rootURL: URL
    private var avatarCache: [String: NSImage] = [:]

    /// No disk access here (see SessionStore.init); call `reload()` once the window is up.
    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func setRoot(_ url: URL) {
        rootURL = url
        avatarCache = [:]
        reload()
    }

    private var fileURL: URL { rootURL.appendingPathComponent(Self.fileName) }
    private var avatarsURL: URL { rootURL.appendingPathComponent(Self.avatarsFolder, isDirectory: true) }

    func reload() {
        let url = fileURL
        let root = rootURL
        Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let list: [Contact]
            if let data = try? Data(contentsOf: url), let decoded = try? decoder.decode([Contact].self, from: data) {
                list = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            } else {
                list = []
            }
            await MainActor.run {
                guard self.rootURL == root else { return }
                self.contacts = list
            }
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(contacts).write(to: fileURL, options: .atomic)
        } catch {
            AppLog.write("contacts save failed: \(error)")
        }
    }

    func contact(_ id: String?) -> Contact? {
        guard let id else { return nil }
        return contacts.first { $0.id == id }
    }

    @discardableResult
    func create(name: String, embedding: [Float]? = nil) -> Contact {
        let c = Contact(
            id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespaces), avatarFile: nil,
            embeddings: embedding.map { [$0] } ?? [], createdAt: Date())
        contacts.append(c)
        contacts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
        AppLog.write("contact created: \(c.name)")
        return c
    }

    func rename(_ id: String, to name: String) {
        guard let i = contacts.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        contacts[i].name = trimmed
        contacts.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    func delete(_ id: String) {
        if let c = contact(id), let file = c.avatarFile {
            try? FileManager.default.removeItem(at: avatarsURL.appendingPathComponent(file))
        }
        contacts.removeAll { $0.id == id }
        avatarCache[id] = nil
        persist()
    }

    /// Adds a voice sample to a contact (keeps the most recent samples).
    func enroll(_ id: String, embedding: [Float]) {
        guard let i = contacts.firstIndex(where: { $0.id == id }) else { return }
        contacts[i].embeddings.append(embedding)
        if contacts[i].embeddings.count > Self.maxEmbeddingsPerContact {
            contacts[i].embeddings.removeFirst(contacts[i].embeddings.count - Self.maxEmbeddingsPerContact)
        }
        persist()
    }

    func bestMatch(for embedding: [Float]) -> ContactMatch? {
        var best: ContactMatch?
        for c in contacts where !c.embeddings.isEmpty {
            let s = c.similarity(to: embedding)
            if s >= Self.suggestThreshold, s > (best?.score ?? 0) {
                best = ContactMatch(contactID: c.id, score: s)
            }
        }
        return best
    }

    // MARK: - Avatars

    func avatar(for id: String) -> NSImage? {
        if let cached = avatarCache[id] { return cached }
        guard let c = contact(id), let file = c.avatarFile,
            let img = NSImage(contentsOf: avatarsURL.appendingPathComponent(file))
        else { return nil }
        avatarCache[id] = img
        return img
    }

    func chooseAvatar(for id: String) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }
        setAvatar(image, for: id)
    }

    func setAvatar(_ image: NSImage, for id: String) {
        guard let i = contacts.firstIndex(where: { $0.id == id }) else { return }
        guard let png = Self.pngData(image, side: 256) else { return }
        do {
            try FileManager.default.createDirectory(at: avatarsURL, withIntermediateDirectories: true)
            let file = "\(id).png"
            try png.write(to: avatarsURL.appendingPathComponent(file), options: .atomic)
            contacts[i].avatarFile = file
            avatarCache[id] = NSImage(data: png)
            persist()
        } catch {
            AppLog.write("avatar save failed: \(error)")
        }
    }

    private static func pngData(_ image: NSImage, side: CGFloat) -> Data? {
        let target = NSSize(width: side, height: side)
        let out = NSImage(size: target)
        out.lockFocus()
        let src = image.size
        let scale = max(target.width / src.width, target.height / src.height)
        let drawSize = NSSize(width: src.width * scale, height: src.height * scale)
        let origin = NSPoint(x: (target.width - drawSize.width) / 2, y: (target.height - drawSize.height) / 2)
        image.draw(in: NSRect(origin: origin, size: drawSize), from: .zero, operation: .copy, fraction: 1)
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
