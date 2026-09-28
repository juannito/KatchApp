import FluidAudio
import SwiftUI

/// A saved session: transcript, speaker renaming/linking, title and project, persisted to disk.
struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var contacts: ContactStore
    @EnvironmentObject var modelStore: ModelStore
    let summary: SessionSummary
    @Binding var selection: SidebarSelection?
    var searchQuery: String = ""
    @State private var matchIndex = 0
    @State private var document: SessionDocument?
    @State private var title = ""
    @State private var loadFailed = false
    @State private var tab: Tab = .transcript
    @FocusState private var titleFocused: Bool
    @State private var folderSize: Int64 = 0
    @StateObject private var playback = PlaybackController()
    @State private var showDelete = false
    @State private var deleteConfirmation = ""
    @State private var deleteScope: DeleteScope = .audioOnly
    @State private var audioSize: Int64 = 0

    enum DeleteScope { case audioOnly, everything }
    private var hasAudio: Bool { audioSize > 0 }

    enum Tab: Hashable { case transcript, summary }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.current)
        f.dateStyle = .full
        f.timeStyle = .short
        return f
    }()

    private var contactNames: [String: String] {
        Dictionary(uniqueKeysWithValues: contacts.contacts.map { ($0.id, $0.name) })
    }

    private var query: String { searchQuery.trimmingCharacters(in: .whitespaces) }

    /// Turn ids containing the search term, in transcript order.
    private var matchIDs: [UUID] {
        guard !query.isEmpty, let doc = document else { return [] }
        let q = SessionSummary.fold(query)
        return doc.turns.filter { SessionSummary.fold($0.text).contains(q) }.map(\.id)
    }

    private var focusID: UUID? {
        let ids = matchIDs
        guard !ids.isEmpty else { return nil }
        return ids[min(max(matchIndex, 0), ids.count - 1)]
    }

    @ViewBuilder
    private var searchBar: some View {
        let ids = matchIDs
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            if ids.isEmpty {
                Text(L("No matches for “%@”", query)).foregroundStyle(.secondary)
            } else {
                Text(L("%d of %d matches for “%@”", min(matchIndex, ids.count - 1) + 1, ids.count, query))
            }
            Spacer()
            Button { matchIndex = (matchIndex - 1 + ids.count) % max(ids.count, 1) } label: { Image(systemName: "chevron.up") }
                .disabled(ids.count < 2)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button { matchIndex = (matchIndex + 1) % max(ids.count, 1) } label: { Image(systemName: "chevron.down") }
                .disabled(ids.count < 2)
                .keyboardShortcut("g", modifiers: [.command])
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    var body: some View {
        Group {
            if let doc = document {
                VStack(spacing: 0) {
                    header(doc)
                    Divider()
                    if !query.isEmpty, tab == .transcript {
                        searchBar
                        Divider()
                    }
                    HSplitView {
                        Group {
                            if tab == .summary {
                                SummaryView(folder: summary.folder)
                            } else {
                                VStack(spacing: 0) {
                                    TranscriptListView(
                                        turns: doc.turns, names: doc.effectiveNames(contactNames: contactNames),
                                        emptyText: L("This session has no text."), autoScroll: false,
                                        highlight: query, focusID: focusID,
                                        playhead: playback.isPlaying || playback.currentTime > 0 ? playback.currentTime : nil,
                                        onSelectTurn: { turn in playback.seek(to: turn.start, andPlay: true) })
                                    if playback.available {
                                        Divider()
                                        PlaybackBar(playback: playback)
                                    }
                                }
                            }
                        }
                        .frame(minWidth: 320)
                        SpeakersPanel(
                            rows: Set(doc.segments.compactMap(\.speaker)).sorted().map { slot in
                                let contact = contacts.contact(doc.speakerContacts[slot])
                                return SpeakerRowModel(
                                    slot: slot, customName: doc.speakerNames[slot] ?? "", contactName: contact?.name,
                                    contact: contact,
                                    isLikelyMe: doc.micEnabled && doc.systemAudioEnabled && (doc.speakerMicFraction[slot] ?? 0) > 0.6)
                            },
                            contacts: contacts.contacts,
                            onRename: { slot, name in
                                document?.speakerNames[slot] = name
                                persist()
                            },
                            onLink: { slot, contactID in link(slot: slot, to: contactID) },
                            onCreateContact: { slot, name in
                                let c = contacts.create(name: name)
                                link(slot: slot, to: c.id)
                            }
                        )
                        .frame(minWidth: 180, idealWidth: 240, maxWidth: 320)
                    }
                    Divider()
                    footer(doc)
                }
            } else if loadFailed {
                ContentUnavailableView(L("Could not read the session"), systemImage: "exclamationmark.triangle",
                    description: Text(summary.folder.path))
            } else {
                ProgressView()
            }
        }
        .task(id: summary.id) { load() }
        .onDisappear { playback.unload() }
        .sheet(isPresented: $showDelete) {
            VStack(alignment: .leading, spacing: 14) {
                Label(L("Delete “%@”", summary.title), systemImage: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.red)
                Picker("", selection: $deleteScope) {
                    Text(L("Only the audio (%@) — keep transcript, summary and speakers", ByteCountFormatter.string(fromByteCount: audioSize, countStyle: .file)))
                        .tag(DeleteScope.audioOnly)
                    Text(L("Everything (%@) — audio, transcript, summary", ByteCountFormatter.string(fromByteCount: folderSize, countStyle: .file)))
                        .tag(DeleteScope.everything)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .disabled(!hasAudio)
                Text(deleteScope == .audioOnly
                    ? L("Playback will no longer be available for this meeting. Voice fingerprints already saved to contacts are kept.")
                    : L("This cannot be undone and does not go through the Trash."))
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L("Type DELETE to confirm:")).font(.callout).foregroundStyle(.secondary)
                TextField("DELETE", text: $deleteConfirmation)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { if deleteConfirmation == "DELETE" { performDelete() } }
                HStack {
                    Button(L("Cancel")) { showDelete = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(deleteScope == .audioOnly ? L("Delete audio") : L("Delete everything"), role: .destructive) { performDelete() }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(deleteConfirmation != "DELETE")
                }
            }
            .padding(24)
            .frame(width: 460)
        }
        .onChange(of: query) { _, _ in matchIndex = max(matchIDs.count - 1, 0) }
        .onChange(of: document == nil) { _, _ in matchIndex = max(matchIDs.count - 1, 0) }
    }

    private func header(_ doc: SessionDocument) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(L("Title"), text: $title)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(titleFocused ? Color.secondary.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, -6)
                    .onSubmit {
                        document?.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title
                        persist()
                        titleFocused = false
                    }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused {
                            document?.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title
                            persist()
                        }
                    }
                Text("\(Self.dateFormatter.string(from: doc.startedAt)) · \(TimeFormat.clock(doc.duration)) · \(L("%d turns", doc.turns.count))\(doc.platformName.map { " · \($0)" } ?? "")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: $tab) {
                Text(L("Summary")).tag(Tab.summary)
                Text(L("Transcript")).tag(Tab.transcript)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            Menu {
                Button(L("No project")) { move(to: nil) }
                if !store.visibleProjects.isEmpty { Divider() }
                ForEach(store.visibleProjects, id: \.self) { p in
                    Button(p) { move(to: p) }
                }
            } label: {
                Label(summary.project ?? L("No project"), systemImage: "folder")
            }
            .fixedSize()
            Menu {
                Button(L("Copy transcript")) {
                    var d = doc
                    d.speakerNames = doc.effectiveNames(contactNames: contactNames)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(d.markdown(), forType: .string)
                }
                if let s = SummaryService.read(at: summary.folder) {
                    Button(L("Copy summary")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(s.markdown(), forType: .string)
                    }
                }
                Button(L("Download as Markdown…")) { exportMarkdown(doc) }
                Divider()
                if hasAudio {
                    Button(L("Open audio")) { NSWorkspace.shared.open(summary.folder.appendingPathComponent(SessionStore.audioFile)) }
                }
                Button(L("Show in Finder")) { store.reveal(summary.folder) }
                Divider()
                Button(L("Delete…"), role: .destructive) {
                    deleteConfirmation = ""
                    deleteScope = hasAudio ? .audioOnly : .everything
                    showDelete = true
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Actions"))
        }
        .padding(16)
    }

    private func footer(_ doc: SessionDocument) -> some View {
        HStack(spacing: 12) {
            Text(summary.folder.path)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(ByteCountFormatter.string(fromByteCount: folderSize, countStyle: .file))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .help(L("Size on disk (audio, transcript, summary)"))
            if !hasAudio {
                Text(L("Audio deleted")).font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func load() {
        if let doc = SessionStore.readDocument(at: summary.folder) {
            document = doc
            title = doc.title ?? ""
        } else {
            loadFailed = true
        }
        let folder = summary.folder
        tab = SummaryService.read(at: folder) != nil ? .summary : .transcript
        playback.load(url: folder.appendingPathComponent(SessionStore.audioFile))
        refreshSizes()
    }

    private func refreshSizes() {
        let folder = summary.folder
        Task.detached {
            let size = SessionStore.folderSize(folder)
            let audio = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(SessionStore.audioFile).path)[.size] as? Int64) ?? 0
            await MainActor.run {
                folderSize = size
                audioSize = audio
            }
        }
    }

    /// Save sheet with summary (if any) followed by the transcript, speaker names resolved.
    private func exportMarkdown(_ doc: SessionDocument) {
        var d = doc
        d.speakerNames = doc.effectiveNames(contactNames: contactNames)
        let text = d.exportMarkdown(summary: SummaryService.read(at: summary.folder))
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let safeTitle = doc.displayTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(df.string(from: doc.startedAt)) \(safeTitle).md"
        panel.title = L("Download as Markdown…")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            AppLog.write("exported markdown: \(url.lastPathComponent)")
        } catch {
            AppLog.write("markdown export failed: \(error)")
        }
    }

    private func performDelete() {
        guard deleteConfirmation == "DELETE" else { return }
        showDelete = false
        switch deleteScope {
        case .everything:
            store.deletePermanently(summary)
            selection = .live
        case .audioOnly:
            playback.unload()
            store.deleteAudio(summary)
            refreshSizes()
        }
    }

    private func persist() {
        guard let doc = document else { return }
        store.save(doc, to: summary.folder)
    }

    /// Links a speaker slot to a contact and enrolls its voice, computing the fingerprint from
    /// audio.wav when the session predates voice recognition.
    private func link(slot: Int, to contactID: String?) {
        document?.speakerContacts[slot] = contactID
        persist()
        guard let contactID else { return }
        if let e = document?.speakerEmbeddings[slot] {
            contacts.enroll(contactID, embedding: e)
            return
        }
        guard let fp = modelStore.models?.fingerprinter, let doc = document else { return }
        let ranges = doc.speechRanges(for: slot)
        guard !ranges.isEmpty else { return }
        let audioURL = summary.folder.appendingPathComponent(SessionStore.audioFile)
        Task {
            guard let audio = try? AudioConverter().resampleAudioFile(audioURL) else { return }
            do {
                if let e = try await fp.embed(sessionAudio: audio, ranges: ranges) {
                    document?.speakerEmbeddings[slot] = e
                    contacts.enroll(contactID, embedding: e)
                    persist()
                    AppLog.write("voice fingerprint computed from transcript ranges for slot \(slot) (\(ranges.count) ranges)")
                }
            } catch {
                AppLog.write("on-demand fingerprint failed: \(error)")
            }
        }
    }

    private func move(to project: String?) {
        guard project != summary.project else { return }
        if let moved = store.move(sessionFolder: summary.folder, toProject: project) {
            let id = project.map { "\($0)/\(moved.lastPathComponent)" } ?? moved.lastPathComponent
            selection = .session(id)
        }
    }
}
