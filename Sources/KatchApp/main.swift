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
