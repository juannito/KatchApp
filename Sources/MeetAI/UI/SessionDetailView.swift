import SwiftUI

/// Read-only view of a saved session, with speaker renaming and title editing persisted to disk.
struct SessionDetailView: View {
    @EnvironmentObject var store: SessionStore
    let summary: SessionSummary
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

    var body: some View {
        Group {
            if let doc = document {
                VStack(spacing: 0) {
                    header(doc)
                    Divider()
                    HSplitView {
                        TranscriptListView(
                            turns: doc.turns, names: doc.speakerNames, emptyText: L("This session has no text."),
                            autoScroll: false)
                        .frame(minWidth: 320)
                        SpeakersPanel(
                            slots: Set(doc.segments.compactMap(\.speaker)).sorted(),
                            names: doc.speakerNames,
                            micFraction: doc.speakerMicFraction,
                            showMicHint: doc.micEnabled && doc.systemAudioEnabled
                        ) { slot, name in
                            document?.speakerNames[slot] = name
                            persist()
                        }
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
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(doc.markdown(), forType: .string)
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
}
