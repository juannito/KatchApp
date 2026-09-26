import AppKit
import Foundation
import SwiftUI

@MainActor
final class RecordingSession: ObservableObject {
    enum Status: Equatable {
        case idle
        case recording
        case finishing
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
    /// Set after `stop()`: the UI shows the "guardar / descartar" sheet.
    @Published var pendingSave: SessionDocument?

    private var models: LoadedModels?
    private weak var store: SessionStore?
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

    func attach(models: LoadedModels, store: SessionStore) {
        self.models = models
        self.store = store
    }

    // MARK: - Start

    func start() async {
        guard status == .idle, let models, let store else { return }
        guard micEnabled || systemAudioEnabled else {
            message = L("Enable at least one audio source.")
            return
        }
        message = nil
        pendingSave = nil
        segments = []
        speakerNames = [:]
        speakerMicFraction = [:]
        elapsed = 0
        startedAt = Date()

        if micEnabled {
            let ok = await MicCapture.requestPermission()
            if !ok {
                message = L("No microphone permission. Enable it in System Settings > Privacy & Security > Microphone.")
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
            id: UUID(), title: nil, startedAt: startedAt, endedAt: nil, micEnabled: micEnabled,
            systemAudioEnabled: systemAudioEnabled, speakerNames: [:], speakerMicFraction: [:], segments: [])

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
            let tap = SystemAudioTap { [weak self] samples in self?.mixBus?.pushSys(samples) }
            do {
                try tap.start()
                self.tap = tap
                started = true
            } catch {
                AppLog.write("system audio tap failed: \(error.localizedDescription)")
                message = error.localizedDescription
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
        guard status == .recording else { return }
        status = .finishing
        timer?.invalidate()
        timer = nil
        mic?.stop()
        tap?.stop()
        chunkContinuation?.finish()
        await feederTask?.value
        await eventTask?.value
        wav?.close {}
        cleanupCapture()
        var doc = currentDocument()
        doc.endedAt = Date()
        document = doc
        autosave()
        AppLog.write("recording stopped: \(segments.count) segments, \(speakerSlots.count) speakers")
        status = .idle
        pendingSave = doc
    }

    /// User confirmed the save sheet.
    func confirmSave(title: String) {
        guard var doc = pendingSave, let folder = sessionFolder else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        doc.title = trimmed.isEmpty ? nil : trimmed
        doc.segments = segments
        doc.speakerNames = speakerNames
        doc.speakerMicFraction = speakerMicFraction
        document = doc
        store?.save(doc, to: folder)
        AppLog.write("session saved: \(folder.lastPathComponent) title=\(doc.displayTitle)")
        pendingSave = nil
    }

    /// User discarded the recording: the folder (audio + transcript) goes to the Trash.
    func discard() {
        if let folder = sessionFolder {
            try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            AppLog.write("session discarded: \(folder.lastPathComponent)")
        }
        store?.reload()
        pendingSave = nil
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
        SpeakerLabel.name(for: slot, names: speakerNames)
    }

    // MARK: - Persistence

    private func currentDocument() -> SessionDocument {
        var doc = document ?? SessionDocument(
            id: UUID(), title: nil, startedAt: startedAt, endedAt: nil, micEnabled: micEnabled,
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
