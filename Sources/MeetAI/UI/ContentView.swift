import SwiftUI

enum SidebarSelection: Hashable {
    case live
    case session(String)
}

struct ContentView: View {
    @EnvironmentObject var modelStore: ModelStore
    @EnvironmentObject var session: RecordingSession
    @EnvironmentObject var store: SessionStore
    @State private var selection: SidebarSelection? = .live

    var body: some View {
        NavigationSplitView {
            SessionsSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            switch selection {
            case .session(let id):
                if let summary = store.sessions.first(where: { $0.id == id }) {
                    SessionDetailView(summary: summary)
                        .id(summary.id)
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
            SaveSheet(document: doc) { title in
                session.confirmSave(title: title)
                if let folder = session.sessionFolder {
                    selection = .session(folder.lastPathComponent)
                }
            } onDiscard: {
                session.discard()
                selection = .live
            }
        }
    }
}

extension SessionDocument: Identifiable {}

struct SessionsSidebar: View {
    @EnvironmentObject var session: RecordingSession
    @EnvironmentObject var store: SessionStore
    @Binding var selection: SidebarSelection?
    @State private var pendingDelete: SessionSummary?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.current)
        f.dateFormat = "EEE d MMM, HH:mm"
        return f
    }()

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
                if store.sessions.isEmpty {
                    Text(L("No saved sessions yet."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(store.sessions) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).lineLimit(1)
                        Text("\(Self.dateFormatter.string(from: s.startedAt)) · \(TimeFormat.clock(s.duration)) · \(L10n.speakers(s.speakerCount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarSelection.session(s.id))
                    .contextMenu {
                        Button(L("Show in Finder")) { store.reveal(s.folder) }
                        Button(L("Move to Trash"), role: .destructive) { pendingDelete = s }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("Reload history"))
            }
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
}

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
                    names: session.speakerNames,
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

    private var header: some View {
        HStack(spacing: 16) {
            RecordButton()
            VStack(alignment: .leading, spacing: 2) {
                Text(session.isRecording ? L("Recording") : (session.status == .finishing ? L("Finishing…") : L("Ready")))
                    .font(.headline)
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

    var body: some View {
        SpeakersPanel(
            slots: session.speakerSlots,
            names: session.speakerNames,
            micFraction: session.speakerMicFraction,
            showMicHint: session.micEnabled && session.systemAudioEnabled
        ) { slot, name in
            session.rename(speaker: slot, to: name)
        }
    }
}

struct SaveSheet: View {
    let document: SessionDocument
    let onSave: (String) -> Void
    let onDiscard: () -> Void
    @State private var title = ""

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.current)
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Save meeting")).font(.title2.weight(.semibold))
            Text("\(Self.dateFormatter.string(from: document.startedAt)) · \(TimeFormat.clock(document.duration)) · \(L("%d turns", document.segments.count))")
                .foregroundStyle(.secondary)
            TextField(L("Title (optional)"), text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSave(title) }
            HStack {
                Button(L("Discard"), role: .destructive) { onDiscard() }
                Spacer()
                Button(L("Save")) { onSave(title) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

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
        .disabled(!modelStore.isReady || session.status == .finishing)
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
