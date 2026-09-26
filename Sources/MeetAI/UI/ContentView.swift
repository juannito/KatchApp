import SwiftUI

enum SidebarSelection: Hashable {
    case live
    case session(String)
    case contact(String)
}

struct ContentView: View {
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var session: RecordingSession
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var contacts: ContactStore
    @EnvironmentObject var summaryService: SummaryService
    @State private var selection: SidebarSelection? = .live
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            SessionsSidebar(selection: $selection, searchText: $searchText)
                .navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 360)
        } detail: {
            switch selection {
            case .session(let id):
                if let summary = store.sessions.first(where: { $0.id == id }) {
                    SessionDetailView(summary: summary, selection: $selection, searchQuery: searchText)
                        .id(summary.id)
                } else {
                    LiveView()
                }
            case .contact(let id):
                if let contact = contacts.contact(id) {
                    ContactDetailView(contact: contact, selection: $selection)
                        .id(contact.id)
                } else {
                    LiveView()
                }
            default:
                LiveView()
            }
        }
        .onChange(of: session.status) { _, status in
            if status == .recording { selection = .live }
        }
        .sheet(item: $session.pendingSave) { doc in
            SaveSheet(document: doc) { title, project, links in
                session.confirmSave(title: title, project: project, links: links)
                if let folder = session.sessionFolder {
                    let id = project.map { "\($0)/\(folder.lastPathComponent)" } ?? folder.lastPathComponent
                    selection = .session(id)
                    let names = Dictionary(uniqueKeysWithValues: contacts.contacts.map { ($0.id, $0.name) })
                    summaryService.generateIfAuto(folder: folder, contactNames: names)
                }
            } onDiscard: {
                session.discard()
                selection = .live
            }
        }
    }
}

extension SessionDocument: Identifiable {}

// MARK: - Sidebar

struct SessionsSidebar: View {
    @EnvironmentObject var session: RecordingSession
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var contacts: ContactStore
    @Binding var selection: SidebarSelection?
    @State private var pendingDelete: SessionSummary?
    @State private var showNewProject = false
    @State private var newProjectName = ""
    @Binding var searchText: String
    @State private var collapsed: Set<String> = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.current)
        f.dateFormat = "EEE d MMM, HH:mm"
        return f
    }()

    private var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }
    private var visibleSessions: [SessionSummary] { store.sessions(project: nil).filter { $0.matches(searchText) } }
    private var projectsToShow: [String] {
        store.projects.filter { store.showHidden || !store.isHidden($0) }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                Label {
                    Text(session.isRecording ? L("Recording…") : L("New meeting"))
                } icon: {
                    Image(systemName: session.isRecording ? "record.circle.fill" : "mic.circle")
                        .foregroundStyle(session.isRecording ? .red : .accentColor)
                }
                .tag(SidebarSelection.live)
            }
            Section(L("History")) {
                if isSearching {
                    let hits = visibleSessions
                    if hits.isEmpty {
                        Text(L("No results.")).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(hits) { s in sessionRow(s, showProject: true) }
                } else {
                    let loose = visibleSessions.filter { $0.project == nil }
                    if loose.isEmpty, projectsToShow.isEmpty {
                        Text(L("No saved sessions yet.")).font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(loose) { s in sessionRow(s, showProject: false) }
                    ForEach(projectsToShow, id: \.self) { p in
                        DisclosureGroup(isExpanded: Binding(
                            get: { !collapsed.contains(p) },
                            set: { if $0 { collapsed.remove(p) } else { collapsed.insert(p) } })
                        ) {
                            let inside = visibleSessions.filter { $0.project == p }
                            if inside.isEmpty {
                                Text(L("Empty")).font(.caption).foregroundStyle(.tertiary)
                            }
                            ForEach(inside) { s in sessionRow(s, showProject: false) }
                        } label: {
                            projectLabel(p)
                        }
                    }
                }
            }
            Section(L("Contacts")) {
                if contacts.contacts.isEmpty {
                    Text(L("No contacts yet. Link a speaker to a contact when saving a meeting."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(contacts.contacts.filter { !isSearching || SessionSummary.fold($0.name).contains(SessionSummary.fold(searchText)) }) { c in
                    HStack(spacing: 8) {
                        AvatarView(contact: c, size: 22)
                        Text(c.name).lineLimit(1)
                        if c.isMe {
                            Text(L("me")).font(.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.15), in: Capsule())
                        }
                    }
                    .tag(SidebarSelection.contact(c.id))
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: L("Search meetings"))
        .toolbar {
            ToolbarItem {
                Button { showNewProject = true } label: { Image(systemName: "folder.badge.plus") }
                    .help(L("New project…"))
            }
            ToolbarItem {
                Toggle(isOn: $store.showHidden) { Image(systemName: store.showHidden ? "eye" : "eye.slash") }
                    .toggleStyle(.button)
                    .help(L("Show hidden projects"))
            }
        }
        .alert(L("New project"), isPresented: $showNewProject) {
            TextField(L("Project name"), text: $newProjectName)
            Button(L("Create")) {
                _ = store.createProject(newProjectName)
                newProjectName = ""
            }
            Button(L("Cancel"), role: .cancel) { newProjectName = "" }
        }
        .alert(L("Move this session to the Trash?"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(L("Move to Trash"), role: .destructive) {
                if let s = pendingDelete {
                    store.delete(s)
                    if selection == .session(s.id) { selection = .live }
                }
                pendingDelete = nil
            }
            Button(L("Cancel"), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L("The transcript and audio of “%@” will be moved. You can recover them from the Trash.", pendingDelete?.title ?? ""))
        }
    }

    private func projectLabel(_ p: String) -> some View {
        let hidden = store.isHidden(p)
        return HStack(spacing: 6) {
            Image(systemName: hidden ? "folder.badge.minus" : "folder")
                .foregroundStyle(hidden ? Color.secondary : Color.accentColor)
            Text(p).fontWeight(.medium).foregroundStyle(hidden ? Color.secondary : Color.primary)
            if hidden {
                Image(systemName: "eye.slash").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            if hidden {
                Button(L("Unhide project")) { store.setHidden(p, false) }
            } else {
                Button(L("Hide project")) { store.setHidden(p, true) }
            }
            Button(L("Show in Finder")) { store.reveal(store.projectURL(p)) }
        }
    }

    private func sessionRow(_ s: SessionSummary, showProject: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.title).lineLimit(1)
            Text(subtitle(for: s, showProject: showProject))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(SidebarSelection.session(s.id))
        .contextMenu {
            Menu(L("Move to project")) {
                Button(L("No project")) { move(s, to: nil) }
                ForEach(store.visibleProjects, id: \.self) { p in
                    Button(p) { move(s, to: p) }
                }
            }
            Button(L("Show in Finder")) { store.reveal(s.folder) }
            Button(L("Move to Trash"), role: .destructive) { pendingDelete = s }
        }
    }

    private func subtitle(for s: SessionSummary, showProject: Bool) -> String {
        var parts = [Self.dateFormatter.string(from: s.startedAt), TimeFormat.clock(s.duration), L10n.speakers(s.speakerCount)]
        if showProject, let p = s.project { parts.append(p) }
        return parts.joined(separator: " · ")
    }

    private func move(_ s: SessionSummary, to project: String?) {
        if let moved = store.move(sessionFolder: s.folder, toProject: project) {
            let id = project.map { "\($0)/\(moved.lastPathComponent)" } ?? moved.lastPathComponent
            if selection == .session(s.id) { selection = .session(id) }
        }
    }
}

struct AvatarView: View {
    @EnvironmentObject var contacts: ContactStore
    let contact: Contact
    let size: CGFloat

    var body: some View {
        Group {
            if let img = contacts.avatar(for: contact.id) {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.25))
                    Text(initials).font(.system(size: size * 0.42, weight: .semibold))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        let parts = contact.name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}

// MARK: - Live view

struct LiveView: View {
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var session: RecordingSession

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                TranscriptListView(
                    turns: SessionDocument.mergeTurns(session.segments),
                    names: session.liveNames,
                    emptyText: session.isRecording ? L("Listening…") : L("Press “Record meeting” to start."),
                    emptyDetail: session.isRecording ? nil : L("Everything runs on your Mac: transcription (Parakeet TDT v3, English and Spanish) and speaker separation (Nemotron 3, up to 8 voices). Text shows up a few seconds after each pause, and the speaker is assigned about a second later.")
                )
                .frame(minWidth: 320)
                LiveSpeakersPanel()
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var statusText: String {
        switch session.status {
        case .recording: return L("Recording")
        case .finishing: return L("Finishing…")
        case .analyzing: return L("Analyzing voices…")
        case .idle: return L("Ready")
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            RecordButton()
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText).font(.headline)
                Text(TimeFormat.clock(session.elapsed))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(session.isRecording ? .primary : .secondary)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                Toggle(L("Microphone"), isOn: $session.micEnabled)
                Toggle(L("System audio (Zoom, Meet, Teams…)"), isOn: $session.systemAudioEnabled)
            }
            .toggleStyle(.checkbox)
            .disabled(session.isRecording)
            LevelMeters()
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ModelStatusView()
            Spacer()
            if let message = session.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                if session.permissionHelp != nil {
                    Button(L("Open System Settings")) { session.openPermissionSettings() }
                }
            }
            Button(L("Copy transcript")) { session.copyTranscript() }
                .disabled(session.segments.isEmpty)
            Button(L("Open sessions folder")) { session.revealSessionFolder() }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct LiveSpeakersPanel: View {
    @EnvironmentObject var session: RecordingSession
    @EnvironmentObject var contacts: ContactStore

    var body: some View {
        SpeakersPanel(
            rows: session.speakerSlots.map { slot in
                let contact = contacts.contact(session.liveLinks[slot])
                let suggestion = session.speakerSuggestions[slot].flatMap { m -> (name: String, score: Float, contactID: String)? in
                    guard let c = contacts.contact(m.contactID) else { return nil }
                    return (c.name, m.score, c.id)
                }
                return SpeakerRowModel(
                    slot: slot, customName: session.speakerNames[slot] ?? "", contactName: contact?.name, contact: contact,
                    isLikelyMe: session.micEnabled && session.systemAudioEnabled && (session.speakerMicFraction[slot] ?? 0) > 0.6,
                    suggestion: suggestion)
            },
            contacts: contacts.contacts,
            onRename: { slot, name in session.rename(speaker: slot, to: name) },
            onLink: { slot, cid in session.linkLive(slot: slot, to: cid) },
            onCreateContact: nil,
            onConfirmSuggestion: { slot, cid in session.linkLive(slot: slot, to: cid) }
        )
    }
}

// MARK: - Save sheet

struct SaveSheet: View {
    @EnvironmentObject var session: RecordingSession
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var contacts: ContactStore
    let document: SessionDocument
    let onSave: (String, String?, [Int: String]) -> Void
    let onDiscard: () -> Void

    @State private var title = ""
    @State private var project: String? = UserDefaults.standard.string(forKey: "lastProject")
    @State private var newProjectName = ""
    @State private var showNewProject = false
    @State private var links: [Int: String] = [:]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.current)
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    private var slots: [Int] { Set(document.segments.compactMap(\.speaker)).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Save meeting")).font(.title2.weight(.semibold))
            Text("\(Self.dateFormatter.string(from: document.startedAt)) · \(TimeFormat.clock(document.duration)) · \(L("%d turns", document.segments.count))")
                .foregroundStyle(.secondary)
            TextField(L("Title (optional)"), text: $title)
                .textFieldStyle(.roundedBorder)

            HStack {
                Picker(L("Project"), selection: $project) {
                    Text(L("No project")).tag(String?.none)
                    ForEach(store.visibleProjects, id: \.self) { p in Text(p).tag(String?.some(p)) }
                }
                .frame(maxWidth: 320)
                Button(L("New project…")) { showNewProject = true }
            }
            if showNewProject {
                HStack {
                    TextField(L("Project name"), text: $newProjectName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(createProject)
                    Button(L("Create"), action: createProject).disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if !slots.isEmpty {
                Divider()
                Text(L("Speakers")).font(.headline)
                Text(session.voiceRecognitionAvailable
                    ? L("Link speakers to contacts so MeetAI recognises them next time.")
                    : L("Voice recognition is unavailable (model not loaded)."))
                    .font(.caption).foregroundStyle(.secondary)
                if contacts.me == nil {
                    Text(L("Mark your own contact as “This is me” so meetings can suggest you automatically."))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(slots, id: \.self) { slot in
                    SaveSpeakerRow(slot: slot, links: $links)
                }
            }

            HStack {
                Button(L("Discard"), role: .destructive) { onDiscard() }
                Spacer()
                Button(L("Save")) { onSave(title, project, links) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 560)
        .onAppear {
            if let p = project, !store.visibleProjects.contains(p) { project = nil }
            links = session.liveLinks
        }
    }

    private func createProject() {
        if let created = store.createProject(newProjectName) {
            project = created
            newProjectName = ""
            showNewProject = false
        }
    }
}

struct SaveSpeakerRow: View {
    @EnvironmentObject var session: RecordingSession
    @EnvironmentObject var contacts: ContactStore
    let slot: Int
    @Binding var links: [Int: String]
    @State private var name = ""

    private var suggestion: ContactMatch? { session.speakerSuggestions[slot] }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Circle().fill(SpeakerPalette.color(for: slot)).frame(width: 12, height: 12)
                TextField(SpeakerLabel.defaultName(for: slot), text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onChange(of: name) { _, new in session.rename(speaker: slot, to: new) }
                Menu {
                    Button(L("No contact")) { links[slot] = nil }
                    if !contacts.contacts.isEmpty { Divider() }
                    ForEach(contacts.contacts) { c in
                        Button(c.name) { links[slot] = c.id }
                    }
                    Divider()
                    Button(L("Create contact “%@”", name.isEmpty ? SpeakerLabel.defaultName(for: slot) : name)) {
                        let contactName = name.isEmpty ? SpeakerLabel.defaultName(for: slot) : name
                        if let id = session.createContact(named: contactName, forSlot: slot) { links[slot] = id }
                    }
                } label: {
                    if let c = contacts.contact(links[slot]) {
                        Label(c.name, systemImage: "person.crop.circle.fill")
                    } else {
                        Label(L("No contact"), systemImage: "person.crop.circle")
                    }
                }
                .frame(width: 200)
                if (session.speakerMicFraction[slot] ?? 0) > 0.6, session.micEnabled, session.systemAudioEnabled {
                    Image(systemName: "mic.fill").foregroundStyle(.secondary)
                        .help(L("This voice comes through your microphone: probably you."))
                }
            }
            if links[slot] == nil, suggestion == nil, let me = contacts.me,
                (session.speakerMicFraction[slot] ?? 0) > 0.6, session.micEnabled, session.systemAudioEnabled,
                !links.values.contains(me.id)
            {
                HStack(spacing: 8) {
                    Image(systemName: "mic.fill").foregroundStyle(.secondary)
                    Text(L("This voice comes through your microphone. Is it you (%@)?", me.name)).font(.callout)
                    Button(L("Confirm")) {
                        links[slot] = me.id
                        if name.isEmpty { name = me.name }
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 20)
            }
            if let s = suggestion, links[slot] == nil, let c = contacts.contact(s.contactID) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(.secondary)
                    Text(L("Looks like %@ (%d%%)", c.name, Int((s.score * 100).rounded())))
                        .font(.callout)
                    Button(L("Confirm")) {
                        links[slot] = c.id
                        if name.isEmpty { name = c.name }
                    }
                    .controlSize(.small)
                }
                .padding(.leading, 20)
            }
        }
        .onAppear { name = session.speakerNames[slot] ?? "" }
    }
}

// MARK: - Shared controls

struct RecordButton: View {
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var session: RecordingSession

    var body: some View {
        Button {
            Task {
                if session.isRecording { await session.stop() } else { await session.start() }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 20))
                Text(session.isRecording ? L("Stop") : L("Record meeting"))
                    .font(.title3.weight(.semibold))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(session.isRecording ? .red : .accentColor)
        .controlSize(.large)
        .disabled(!modelStore.isReady || session.status == .finishing || session.status == .analyzing)
        .keyboardShortcut("r", modifiers: [.command])
    }
}

struct LevelMeters: View {
    @EnvironmentObject var session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            meter(label: L("Mic"), value: session.micLevel, enabled: session.micEnabled)
            meter(label: L("Sys."), value: session.sysLevel, enabled: session.systemAudioEnabled)
            meter(label: L("Voice"), value: session.vadProbability, enabled: true, tint: .green)
        }
        .frame(width: 160)
    }

    private func meter(label: String, value: Float, enabled: Bool, tint: Color = .accentColor) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).frame(width: 34, alignment: .trailing).foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(enabled ? tint : Color.secondary.opacity(0.3))
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, value))))
                }
            }
            .frame(height: 8)
        }
    }
}

struct ModelStatusView: View {
    @EnvironmentObject var modelStore: ModelStore

    var body: some View {
        switch modelStore.state {
        case .idle:
            Text(L("Models: pending")).font(.callout).foregroundStyle(.secondary)
        case .loading(let step, let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction).frame(width: 120)
                Text(L(step)).font(.callout).foregroundStyle(.secondary)
            }
        case .ready:
            Label(L("Models ready (Parakeet v3 + Nemotron 3, 100% local)"), systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .failed(let error):
            HStack(spacing: 8) {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Button(L("Retry")) { Task { await modelStore.retry() } }
            }
        }
    }
}
