import AppKit
import Foundation
import ServiceManagement
import SwiftUI

enum CaptureMode: String, CaseIterable, Identifiable {
    case meetingApp, allSystemAudio
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meetingApp: return L("Only the meeting app (recommended)")
        case .allSystemAudio: return L("All system audio (music, notifications, everything)")
        }
    }
}

struct MeetingApp: Identifiable, Hashable {
    let bundleID: String
    var name: String
    var isMeetingApp: Bool
    var isKnown: Bool
    var isRunning: Bool
    var id: String { bundleID }
}

/// Which apps count as "meeting apps": a built-in list plus whatever the user marks.
/// Names can be overridden (for unknown apps the process name is used until renamed).
@MainActor
final class MeetingAppRegistry: ObservableObject {
    static let known: [String: String] = [
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.microsoft.teams": "Microsoft Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.hnc.Discord": "Discord",
        "com.apple.FaceTime": "FaceTime",
        "net.whatsapp.WhatsApp": "WhatsApp",
        "com.skype.skype": "Skype",
        "Cisco-Systems.Spark": "Webex",
        "ru.keepcoder.Telegram": "Telegram",
        "org.whispersystems.signal-desktop": "Signal",
        "com.google.Chrome": "Google Chrome (Meet)",
        "com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan": "Google Meet",
        "com.apple.Safari": "Safari (Meet)",
        "company.thebrowser.Browser": "Arc (Meet)",
        "org.mozilla.firefox": "Firefox (Meet)",
        "com.brave.Browser": "Brave (Meet)",
        "com.microsoft.edgemac": "Edge (Meet)",
        "com.loom.desktop": "Loom",
        "com.around.Around": "Around",
    ]

    private let namesKey = "meetingApps.names"
    private let extraKey = "meetingApps.extra"
    private let disabledKey = "meetingApps.disabled"

    @Published var customNames: [String: String] { didSet { UserDefaults.standard.set(customNames, forKey: namesKey) } }
    @Published var extra: Set<String> { didSet { UserDefaults.standard.set(Array(extra), forKey: extraKey) } }
    @Published var disabled: Set<String> { didSet { UserDefaults.standard.set(Array(disabled), forKey: disabledKey) } }
    @Published var captureMode: CaptureMode { didSet { UserDefaults.standard.set(captureMode.rawValue, forKey: "captureMode") } }
    @Published var autoDetect: Bool { didSet { UserDefaults.standard.set(autoDetect, forKey: "meetings.autoDetect") } }
    /// Processes seen with audio in this launch, so unknown apps can be marked in Settings.
    @Published private(set) var seen: [String: String] = [:]

    init() {
        let d = UserDefaults.standard
        customNames = d.dictionary(forKey: namesKey) as? [String: String] ?? [:]
        extra = Set(d.stringArray(forKey: extraKey) ?? [])
        disabled = Set(d.stringArray(forKey: disabledKey) ?? [])
        captureMode = CaptureMode(rawValue: d.string(forKey: "captureMode") ?? "") ?? .meetingApp
        autoDetect = d.object(forKey: "meetings.autoDetect") as? Bool ?? false
    }

    func isMeetingApp(_ bundleID: String) -> Bool {
        if disabled.contains(bundleID) { return false }
        return Self.known[bundleID] != nil || extra.contains(bundleID)
    }

    func name(for bundleID: String, fallback: String? = nil) -> String {
        customNames[bundleID] ?? Self.known[bundleID] ?? fallback ?? seen[bundleID] ?? bundleID
    }

    func rename(_ bundleID: String, to name: String) {
        let t = name.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { customNames[bundleID] = nil } else { customNames[bundleID] = t }
    }

    func setMeetingApp(_ bundleID: String, _ value: Bool) {
        if Self.known[bundleID] != nil {
            if value { disabled.remove(bundleID) } else { disabled.insert(bundleID) }
        } else {
            if value { extra.insert(bundleID) } else { extra.remove(bundleID) }
        }
    }

    func noteSeen(_ processes: [AudioProcess]) {
        for p in processes where seen[p.bundleID] == nil && p.bundleID != Bundle.main.bundleIdentifier {
            seen[p.bundleID] = p.name
        }
    }

    /// Meeting apps among the given processes, most relevant first (mic in use, then playing audio).
    func meetingProcesses(in processes: [AudioProcess]) -> [AudioProcess] {
        processes.filter { isMeetingApp($0.bundleID) }
            .sorted { a, b in
                if a.isRunningInput != b.isRunningInput { return a.isRunningInput }
                if a.isRunningOutput != b.isRunningOutput { return a.isRunningOutput }
                return a.name < b.name
            }
    }

    /// Rows for Settings: every known app plus anything seen, with current state.
    func allApps() -> [MeetingApp] {
        let running = Set(AudioProcesses.list().map(\.bundleID))
        var ids = Set(Self.known.keys).union(extra).union(seen.keys).union(customNames.keys)
        ids.remove(Bundle.main.bundleIdentifier ?? "")
        return ids.map { id in
            MeetingApp(bundleID: id, name: name(for: id), isMeetingApp: isMeetingApp(id), isKnown: Self.known[id] != nil, isRunning: running.contains(id))
        }
        .sorted { a, b in
            if a.isRunning != b.isRunning { return a.isRunning }
            if a.isMeetingApp != b.isMeetingApp { return a.isMeetingApp }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                AppLog.write("launch at login failed: \(error)")
            }
            objectWillChange.send()
        }
    }
}

/// Polls Core Audio while idle: a meeting app using the microphone means a call is on.
@MainActor
final class MeetingDetector: ObservableObject {
    struct Detection: Identifiable, Equatable {
        let bundleID: String
        let name: String
        var id: String { bundleID }
    }

    @Published var detection: Detection?
    private var timer: Timer?
    private var ignored: Set<String> = []
    private let registry: MeetingAppRegistry
    private var isRecording: () -> Bool = { false }

    init(registry: MeetingAppRegistry) {
        self.registry = registry
    }

    func start(isRecording: @escaping () -> Bool) {
        self.isRecording = isRecording
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func ignoreCurrent() {
        if let d = detection { ignored.insert(d.bundleID) }
        detection = nil
    }

    private func tick() {
        let processes = AudioProcesses.list()
        registry.noteSeen(processes)
        let live = registry.meetingProcesses(in: processes).filter(\.isRunningInput)
        let liveIDs = Set(live.map(\.bundleID))
        // An ignored call is forgotten once that app releases the microphone.
        ignored = ignored.intersection(liveIDs)
        guard registry.autoDetect, !isRecording(), detection == nil else {
            if live.isEmpty { detection = nil }
            return
        }
        if let first = live.first(where: { !ignored.contains($0.bundleID) }) {
            detection = Detection(bundleID: first.bundleID, name: registry.name(for: first.bundleID, fallback: first.name))
            AppLog.write("meeting detected: \(first.bundleID)")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}
