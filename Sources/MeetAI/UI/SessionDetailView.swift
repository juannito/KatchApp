import SwiftUI

/// A saved session: transcript, speaker renaming/linking, title and project, persisted to disk.
struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    @EnvironmentObject var contacts: ContactStore
    let summary: SessionSummary
    @Binding var selection: SidebarSelection?
    @State private var document: SessionDocument?
    @State private var title = ""
    @State private var loadFailed = false

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

    var body: some View {
        Group {
            if let doc = document {
                VStack(spacing: 0) {
                    header(doc)
                    Divider()
                    HSplitView {
                        TranscriptListView(
                            turns: doc.turns, names: doc.effectiveNames(contactNames: contactNames),
                            emptyText: L("This session has no text."), autoScroll: false)
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
                            onLink: { slot, contactID in
                                document?.speakerContacts[slot] = contactID
                                if let contactID, let e = document?.speakerEmbeddings[slot] {
                                    contacts.enroll(contactID, embedding: e)
                                }
                                persist()
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
    }

    private func header(_ doc: SessionDocument) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                TextField(L("Title"), text: $title)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .onSubmit {
                        document?.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : title
                        persist()
                    }
                Text("\(Self.dateFormatter.string(from: doc.startedAt)) · \(TimeFormat.clock(doc.duration)) · \(L("%d turns", doc.turns.count))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
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
            Spacer()
            Button(L("Copy transcript")) {
                var d = doc
                d.speakerNames = doc.effectiveNames(contactNames: contactNames)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(d.markdown(), forType: .string)
            }
            Button(L("Open audio")) { NSWorkspace.shared.open(summary.folder.appendingPathComponent(SessionStore.audioFile)) }
            Button(L("Show in Finder")) { store.reveal(summary.folder) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func load() {
        if let doc = SessionStore.readDocument(at: summary.folder) {
            document = doc
            title = doc.title ?? ""
        } else {
            loadFailed = true
        }
    }

    private func persist() {
        guard let doc = document else { return }
        store.save(doc, to: summary.folder)
    }

    private func move(to project: String?) {
        guard project != summary.project else { return }
        if let moved = store.move(sessionFolder: summary.folder, toProject: project) {
            let id = project.map { "\($0)/\(moved.lastPathComponent)" } ?? moved.lastPathComponent
            selection = .session(id)
        }
    }
}
