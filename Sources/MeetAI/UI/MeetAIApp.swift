import SwiftUI

struct MeetAIApp: App {
    @StateObject private var modelStore = ModelStore()
    @StateObject private var session = RecordingSession()
    @StateObject private var sessionStore: SessionStore
    @StateObject private var contacts: ContactStore
    @StateObject private var language = AppLanguage()
    @Environment(\.openWindow) private var openWindow

    init() {
        // SwiftPM executables launch as background processes; promote to a regular app
        // with a Dock icon and a focused window.
        NSApplication.shared.setActivationPolicy(.regular)
        // Never restore windows from a previous run: with restoration on, killing the app while
        // the About/Settings window was open relaunched it without the main window.
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        let store = SessionStore()
        _sessionStore = StateObject(wrappedValue: store)
        _contacts = StateObject(wrappedValue: ContactStore(rootURL: store.rootURL))
    }

    var body: some Scene {
        WindowGroup("MeetAI") {
            ContentView()
                .id(language.code)  // rebuild the UI when the language changes
                .environmentObject(modelStore)
                .environmentObject(session)
                .environmentObject(sessionStore)
                .environmentObject(contacts)
                .environmentObject(language)
                .frame(minWidth: 760, minHeight: 520)
                .task {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    await modelStore.loadIfNeeded()
                    if let models = modelStore.models {
                        session.attach(models: models, store: sessionStore, contacts: contacts)
                    }
                }
                .onReceive(sessionStore.$rootURL) { url in
                    if contacts.rootURL != url { contacts.setRoot(url) }
                }
        }
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
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
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .id(language.code)
                .environmentObject(sessionStore)
                .environmentObject(language)
        }
    }
}
