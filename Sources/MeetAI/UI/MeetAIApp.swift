import SwiftUI

struct MeetAIApp: App {
    @StateObject private var modelStore = ModelStore()
    @StateObject private var session = RecordingSession()
    @StateObject private var sessionStore = SessionStore()
    @StateObject private var language = AppLanguage()
    @Environment(\.openWindow) private var openWindow

    init() {
        // SwiftPM executables launch as background processes; promote to a regular app
        // with a Dock icon and a focused window.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("MeetAI") {
            ContentView()
                .id(language.code)  // rebuild the UI when the language changes
                .environmentObject(modelStore)
                .environmentObject(session)
                .environmentObject(sessionStore)
                .environmentObject(language)
                .frame(minWidth: 760, minHeight: 520)
                .task {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    await modelStore.loadIfNeeded()
                    if let models = modelStore.models { session.attach(models: models, store: sessionStore) }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button(L("About MeetAI")) { openWindow(id: "about") }
            }
        }

        Window(L("About MeetAI"), id: "about") {
            AboutView()
                .id(language.code)
                .environmentObject(language)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .id(language.code)
                .environmentObject(sessionStore)
                .environmentObject(language)
        }
    }
}
