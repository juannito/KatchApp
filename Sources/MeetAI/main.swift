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
} else {
    AppLog.write("launch \(Bundle.main.bundleIdentifier ?? "cli") \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")")
    MeetAIApp.main()
}
