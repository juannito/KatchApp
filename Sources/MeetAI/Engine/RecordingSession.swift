import AppKit
import AVFoundation
import FluidAudio
import Foundation
import SwiftUI

@MainActor
final class RecordingSession: ObservableObject {
    enum Status: Equatable {
        case idle
        case recording
        case finishing
        case analyzing
    }

    @Published var status: Status = .idle
    @Published var segments: [TranscriptSegment] = []
    @Published var speakerNames: [Int: String] = [:]
    @Published var speakerMicFraction: [Int: Double] = [:]
    @Published var elapsed: TimeInterval = 0
    @Published var micLevel: Float = 0
    @Published var sysLevel: Float = 0
    @Published var vadProbability: Float = 0
    @Published var message: String?
    @Published var sessionFolder: URL?
    @Published var micEnabled = true
    @Published var systemAudioEnabled = true
    /// Set after `stop()`: the UI shows the save sheet.
    @Published var pendingSave: SessionDocument?
    /// Voice-recognition suggestions per speaker slot (live while recording, refined on stop).
    @Published var speakerSuggestions: [Int: ContactMatch] = [:]
    /// Contacts confirmed during the recording (slot -> contact id); prefilled in the save sheet.
    @Published var liveLinks: [Int: String] = [:]
    private var liveEmbeddings: [Int: [Float]] = [:]
    /// Set when a capture permission is missing; the UI offers a shortcut to System Settings.
    @Published var permissionHelp: PermissionKind?

    enum PermissionKind {
        case microphone, systemAudio

        var settingsURL: URL {
            switch self {
            case .microphone:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            case .systemAudio:
                return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
            }
        }
    }

    func openPermissionSettings() {
        guard let kind = permissionHelp else { return }
        NSWorkspace.shared.open(kind.settingsURL)
    }

    private var models: LoadedModels?
    private weak var store: SessionStore?
    private weak var contacts: ContactStore?
    private weak var meetingApps: MeetingAppRegistry?
    @Published private(set) var platformName: String?
    private var platformTimer: Timer?
    private var engine: TranscriptionEngine?
    private var mic: MicCapture?
    private var tap: SystemAudioTap?
    private var mixBus: MixBus?
    private var wav: WavWriter?
    private var chunkContinuation: AsyncStream<MixedChunk>.Continuation?
    private var feederTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var timer: Timer?
    private var startedAt = Date()
    private var document: SessionDocument?

    var isRecording: Bool { status == .recording }
    var speakerSlots: [Int] { Set(segments.compactMap(\.speaker)).sorted() }
    var voiceRecognitionAvailable: Bool { models?.fingerprinter != nil }

    func attach(models: LoadedModels, store: SessionStore, contacts: ContactStore, meetingApps: MeetingAppRegistry) {
        self.models = models
        self.store = store
        self.contacts = contacts
        self.meetingApps = meetingApps
    }

    /// Looks for a meeting app with audio and tags the session with it (first hit wins).
    private func detectPlatform() {
        guard var doc = document, doc.platform == nil, let meetingApps else { return }
        let processes = AudioProcesses.list()
        meetingApps.noteSeen(processes)
        guard let app = meetingApps.meetingProcesses(in: processes).first(where: { $0.isRunningInput || $0.isRunningOutput })
        else { return }
        doc.platform = app.bundleID
        doc.platformName = meetingApps.name(for: app.bundleID, fallback: app.name)
        document = doc
        platformName = doc.platformName
        AppLog.write("platform: \(app.bundleID) (\(doc.platformName ?? ""))")
    }

    // MARK: - Start

    func start() async {
        guard status == .idle, let models, let store else { return }
        guard micEnabled || systemAudioEnabled else {
            message = L("Enable at least one audio source.")
            return
        }
        message = nil
        permissionHelp = nil
        pendingSave = nil
        speakerSuggestions = [:]
        liveLinks = [:]
        liveEmbeddings = [:]
        segments = []
        speakerNames = [:]
        speakerMicFraction = [:]
        elapsed = 0
        startedAt = Date()

        if micEnabled {
            let ok = await MicCapture.requestPermission()
            if !ok {
                message = L("No microphone permission. Enable it in System Settings > Privacy & Security > Microphone.")
                permissionHelp = .microphone
                AppLog.write("microphone permission denied (status: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue))")
                return
            }
        }

        let folder: URL
        do {
            folder = try store.makeSessionFolder(date: startedAt)
            sessionFolder = folder
            wav = try WavWriter(url: folder.appendingPathComponent(SessionStore.audioFile))
        } catch {
            message = L("Could not create the session folder: %@", error.localizedDescription)
            return
        }

        document = SessionDocument(
            id: UUID(), startedAt: startedAt, endedAt: nil, micEnabled: micEnabled,
            systemAudioEnabled: systemAudioEnabled, speakerNames: [:], speakerMicFraction: [:], segments: [])
        platformName = nil

        // Which processes to tap: the meeting app(s) if present (and the setting says so), else everything.
        var tapProcesses: [AudioObjectID] = []
        if let meetingApps {
            let processes = AudioProcesses.list()
            meetingApps.noteSeen(processes)
            let meeting = meetingApps.meetingProcesses(in: processes)
            if meetingApps.captureMode == .meetingApp, !meeting.isEmpty {
                tapProcesses = meeting.map(\.objectID)
                AppLog.write("tapping only: \(meeting.map(\.bundleID))")
            }
        }
        detectPlatform()

        let engine = TranscriptionEngine(models: models)
        self.engine = engine

        let (stream, continuation) = AsyncStream<MixedChunk>.makeStream(bufferingPolicy: .unbounded)
        chunkContinuation = continuation
        feederTask = Task.detached(priority: .userInitiated) {
            for await chunk in stream {
                await engine.push(chunk)
            }
            await engine.finish()
        }
        eventTask = Task { [weak self] in
            for await event in engine.events {
                self?.handle(event)
            }
        }

        let bus = MixBus(micEnabled: micEnabled, sysEnabled: systemAudioEnabled)
        let output: (MixedChunk) -> Void = { [weak self] chunk in
            guard let self else { return }
            self.wav?.write(chunk.samples)
            self.chunkContinuation?.yield(chunk)
            Task { @MainActor in self.updateLevels(chunk) }
        }
        bus.output = output
        mixBus = bus

        var started = false
        if systemAudioEnabled {
            let tap = SystemAudioTap(processes: tapProcesses) { [weak self] samples in self?.mixBus?.pushSys(samples) }
            do {
                try tap.start()
                self.tap = tap
                started = true
            } catch {
                AppLog.write("system audio tap failed: \(error.localizedDescription)")
                message = error.localizedDescription
                permissionHelp = .systemAudio
                if !micEnabled {
                    cleanupCapture()
                    return
                }
                systemAudioEnabled = false
                let micOnly = MixBus(micEnabled: true, sysEnabled: false)
                micOnly.output = output
                mixBus = micOnly
            }
        }
        if micEnabled {
            let mic = MicCapture()
            do {
                try mic.start { [weak self] samples in self?.mixBus?.pushMic(samples) }
                self.mic = mic
                started = true
            } catch {
                AppLog.write("mic capture failed: \(error.localizedDescription)")
                message = error.localizedDescription
                if !started {
                    cleanupCapture()
                    return
                }
            }
        }
        guard started else { return }

        status = .recording
        AppLog.write("recording started (mic: \(micEnabled), system: \(systemAudioEnabled)) -> \(folder.path)")
        platformTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.detectPlatform() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
                if Int(self.elapsed) % 30 == 0 { self.autosave() }
            }
        }
    }

    // MARK: - Stop

    func stop() async {
        guard status == .recording, let engine else { return }
        status = .finishing
        timer?.invalidate()
        timer = nil
        platformTimer?.invalidate()
        platformTimer = nil
        mic?.stop()
        tap?.stop()
        chunkContinuation?.finish()
        await feederTask?.value
        await eventTask?.value
        let ranges = await engine.exclusiveSpeechRanges()
        await wav?.finish()
        cleanupCapture()

        var doc = currentDocument()
        doc.endedAt = Date()
        document = doc
        autosave()
        AppLog.write("recording stopped: \(segments.count) segments, \(speakerSlots.count) speakers")

        status = .analyzing
        var embeddings = await computeEmbeddings(ranges: ranges)
        for (slot, e) in liveEmbeddings where embeddings[slot] == nil { embeddings[slot] = e }
        doc.speakerEmbeddings = embeddings
        document = doc
        var suggestions = speakerSuggestions
        if let contacts {
            for (slot, emb) in doc.speakerEmbeddings where liveLinks[slot] == nil {
                if let m = contacts.bestMatch(for: emb) { suggestions[slot] = m }
            }
        }
        speakerSuggestions = suggestions
        status = .idle
        pendingSave = doc
    }

    private func computeEmbeddings(ranges: [Int: [TimeRange]]) async -> [Int: [Float]] {
        guard let fp = models?.fingerprinter, let folder = sessionFolder else { return [:] }
        let audioURL = folder.appendingPathComponent(SessionStore.audioFile)
        guard let audio = try? AudioConverter().resampleAudioFile(audioURL) else { return [:] }
        var out: [Int: [Float]] = [:]
        for slot in speakerSlots {
            guard let r = ranges[slot], !r.isEmpty else { continue }
            do {
                if let e = try await fp.embed(sessionAudio: audio, ranges: r) { out[slot] = e }
            } catch {
                AppLog.write("embedding failed for speaker \(slot): \(error)")
            }
        }
        AppLog.write("voice embeddings: \(out.count)/\(speakerSlots.count) speakers")
        return out
    }

    /// User confirmed the save sheet.
    func confirmSave(title: String, project: String?, links: [Int: String]) {
        guard var doc = pendingSave, var folder = sessionFolder, let store else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        doc.title = trimmed.isEmpty ? nil : trimmed
        doc.segments = segments
        doc.speakerNames = speakerNames
        doc.speakerMicFraction = speakerMicFraction
        doc.speakerContacts = links
        doc.project = project
        for (slot, cid) in links {
            if let e = doc.speakerEmbeddings[slot] { contacts?.enroll(cid, embedding: e) }
        }
        if let moved = store.move(sessionFolder: folder, toProject: project) {
            folder = moved
            sessionFolder = moved
        }
        document = doc
        store.save(doc, to: folder)
        if let project { UserDefaults.standard.set(project, forKey: "lastProject") } else {
            UserDefaults.standard.removeObject(forKey: "lastProject")
        }
        AppLog.write("session saved: \(folder.lastPathComponent) title=\(doc.displayTitle) project=\(project ?? "-") links=\(links.count)")
        pendingSave = nil
        speakerSuggestions = [:]
    }

    /// Creates a contact for a speaker slot, seeded with its voice embedding.
    func createContact(named name: String, forSlot slot: Int) -> String? {
        guard let contacts else { return nil }
        let c = contacts.create(name: name, embedding: pendingSave?.speakerEmbeddings[slot])
        return c.id
    }

    /// User discarded the recording: the folder (audio + transcript) goes to the Trash.
    func discard() {
        if let folder = sessionFolder {
            try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            AppLog.write("session discarded: \(folder.lastPathComponent)")
        }
        store?.reload()
        pendingSave = nil
        speakerSuggestions = [:]
        sessionFolder = nil
        document = nil
        segments = []
        speakerNames = [:]
        speakerMicFraction = [:]
        elapsed = 0
    }

    private func cleanupCapture() {
        mic = nil
        tap = nil
        mixBus = nil
        chunkContinuation = nil
        feederTask = nil
        eventTask = nil
        wav = nil
        engine = nil
    }

    // MARK: - Events

    private func handle(_ event: TranscriptionEngine.Event) {
        switch event {
        case .transcribed(let seg):
            segments.append(seg)
        case .attributed(let id, let replacement):
            if let idx = segments.firstIndex(where: { $0.id == id }) {
                segments.replaceSubrange(idx...idx, with: replacement)
            } else {
                segments.append(contentsOf: replacement)
            }
        case .speakerMicFraction(let fractions):
            for (k, v) in fractions { speakerMicFraction[k] = v }
        case .speakerEmbedding(let slot, let embedding):
            liveEmbeddings[slot] = embedding
            guard liveLinks[slot] == nil, let contacts else { return }
            if let m = contacts.bestMatch(for: embedding), !liveLinks.values.contains(m.contactID) {
                speakerSuggestions[slot] = m
            } else {
                speakerSuggestions[slot] = nil
            }
        case .vad(let p):
            vadProbability = p
        case .warning(let text):
            AppLog.write("warning: \(text)")
            message = text
        }
    }

    private func updateLevels(_ chunk: MixedChunk) {
        micLevel = max(chunk.micRMS * 6, micLevel * 0.7)
        sysLevel = max(chunk.sysRMS * 6, sysLevel * 0.7)
    }

    // MARK: - Speakers

    func rename(speaker slot: Int, to name: String) {
        speakerNames[slot] = name
        if pendingSave == nil { autosave() }
    }

    func displayName(for slot: Int?) -> String {
        if let slot, let cid = liveLinks[slot], let c = contacts?.contact(cid) { return c.name }
        return SpeakerLabel.name(for: slot, names: speakerNames)
    }

    /// Accept a live suggestion (or any contact) for a speaker while recording.
    func linkLive(slot: Int, to contactID: String?) {
        if let contactID {
            liveLinks[slot] = contactID
            speakerSuggestions[slot] = nil
        } else {
            liveLinks[slot] = nil
        }
    }

    /// Names with live contact links applied (for the live transcript).
    var liveNames: [Int: String] {
        var names = speakerNames
        for (slot, cid) in liveLinks {
            if let c = contacts?.contact(cid) { names[slot] = c.name }
        }
        return names
    }

    // MARK: - Persistence

    private func currentDocument() -> SessionDocument {
        var doc = document ?? SessionDocument(
            id: UUID(), startedAt: startedAt, endedAt: nil, micEnabled: micEnabled,
            systemAudioEnabled: systemAudioEnabled, speakerNames: [:], speakerMicFraction: [:], segments: [])
        doc.segments = segments
        doc.speakerNames = speakerNames
        doc.speakerMicFraction = speakerMicFraction
        return doc
    }

    /// Writes the current state to disk (crash safety); does not touch the history list.
    private func autosave() {
        guard document != nil, let folder = sessionFolder else { return }
        let doc = currentDocument()
        document = doc
        do {
            try SessionStore.write(doc, to: folder)
        } catch {
            message = L("Could not save: %@", error.localizedDescription)
        }
    }

    func revealSessionFolder() {
        let url = sessionFolder ?? store?.rootURL ?? SessionStore.defaultRoot()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyTranscript() {
        let doc = currentDocument()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(doc.markdown(), forType: .string)
    }
}
