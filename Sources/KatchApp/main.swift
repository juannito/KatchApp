import AppKit
import Foundation
import SwiftUI

let arguments = CommandLine.arguments
if arguments.count >= 3, arguments[1] == "--selftest" {
    let path = arguments[2]
    Task {
        let code = await SelfTest.run(path: path)
        exit(code)
    }
    dispatchMain()
} else if arguments.count >= 3, arguments[1] == "--import" {
    // KatchApp --import <audio file>: runs RecordingSession.importAudio headlessly and prints the result.
    let url = URL(fileURLWithPath: arguments[2])
    Task { @MainActor in
        let models = try await ModelLoader.load { step, _ in print("[import] \(step)") }
        let store = SessionStore()
        let contacts = ContactStore(rootURL: store.rootURL)
        let session = RecordingSession()
        session.attach(models: models, store: store, contacts: contacts, meetingApps: MeetingAppRegistry())
        await session.importAudio(url: url)
        print("[import] status=\(session.status) segments=\(session.segments.count) speakers=\(session.speakerSlots.count) folder=\(session.sessionFolder?.path ?? "-")")
        for seg in SessionDocument.mergeTurns(session.segments) {
            print("  [\(TimeFormat.clock(seg.start))] \(SpeakerLabel.name(for: seg.speaker, names: [:])): \(seg.text)")
        }
        if session.pendingSave != nil { session.discard(); print("[import] discarded test session") }
        exit(0)
    }
    dispatchMain()
} else if arguments.count >= 2, arguments[1] == "--audio-processes" {
    for p in AudioProcesses.list() {
        print("\(p.pid)\t\(p.isRunningInput ? "MIC" : "   ")\t\(p.isRunningOutput ? "OUT" : "   ")\t\(p.bundleID)\t\(p.name)")
    }
    exit(0)
} else if arguments.count >= 3, arguments[1] == "--summarize" {
    // KatchApp --summarize <session folder> [ollama model]
    let folder = URL(fileURLWithPath: arguments[2], isDirectory: true)
    let model = arguments.count >= 4 ? arguments[3] : "llama3.2"
    Task {
        let code = await SelfTest.summarize(folder: folder, ollamaModel: model)
        exit(code)
    }
    dispatchMain()
} else {
    Migration.runIfNeeded()
    AppLog.write("launch \(Bundle.main.bundleIdentifier ?? "cli") \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")")
    KatchAppMain.main()
}
