import SwiftUI

enum SpeakerPalette {
    static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
    static func color(for slot: Int?) -> Color {
        guard let slot, slot >= 0 else { return .gray }
        return colors[slot % colors.count]
    }
}

/// Scrollable list of speaker turns; auto-scrolls to the bottom as turns arrive.
struct TranscriptListView: View {
    let turns: [TranscriptSegment]
    let names: [Int: String]
    var emptyText: String = ""
    var emptyDetail: String? = nil
    var autoScroll = true

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if turns.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(emptyText).font(.title3).foregroundStyle(.secondary)
                            if let emptyDetail {
                                Text(emptyDetail)
                                    .font(.callout)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: 560, alignment: .leading)
                            }
                        }
                        .padding(.top, 40)
                    }
                    ForEach(turns) { turn in
                        TurnRow(turn: turn, name: SpeakerLabel.name(for: turn.speaker, names: names))
                            .id(turn.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: turns.count) { _, _ in
                if autoScroll { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
        }
    }
}

struct TurnRow: View {
    let turn: TranscriptSegment
    let name: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(turn.attributed ? SpeakerPalette.color(for: turn.speaker) : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(turn.attributed ? name : "…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(turn.attributed ? SpeakerPalette.color(for: turn.speaker) : .secondary)
                    Text(TimeFormat.clock(turn.start))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Text(turn.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(turn.attributed ? .primary : .secondary)
            }
        }
    }
}

struct SpeakerRowModel: Identifiable {
    var id: Int { slot }
    let slot: Int
    let customName: String
    let contactName: String?
    let contact: Contact?
    let isLikelyMe: Bool
}

/// Speaker list with inline renaming and optional contact linking.
struct SpeakersPanel: View {
    let rows: [SpeakerRowModel]
    let contacts: [Contact]
    let onRename: (Int, String) -> Void
    let onLink: ((Int, String?) -> Void)?
    var onCreateContact: ((Int, String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Speakers")).font(.headline)
            if rows.isEmpty {
                Text(L("They appear as they speak."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                SpeakerRow(
                    row: row, contacts: contacts,
                    onRename: { onRename(row.slot, $0) },
                    onLink: onLink.map { link in { link(row.slot, $0) } },
                    onCreateContact: onCreateContact.map { create in { create(row.slot, $0) } })
            }
            Spacer()
            Text(L("Click a name to rename it and press Enter. Saved to transcript.md and transcript.json."))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct SpeakerRow: View {
    let row: SpeakerRowModel
    let contacts: [Contact]
    let onRename: (String) -> Void
    let onLink: ((String?) -> Void)?
    var onCreateContact: ((String) -> Void)? = nil
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let c = row.contact {
                    AvatarView(contact: c, size: 18)
                } else {
                    Circle().fill(SpeakerPalette.color(for: row.slot)).frame(width: 12, height: 12)
                }
                if let contactName = row.contactName {
                    Text(contactName).font(.body.weight(.medium)).lineLimit(1)
                    Spacer()
                } else {
                    TextField(SpeakerLabel.defaultName(for: row.slot), text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { onRename(draft) }
                        .onAppear { draft = row.customName }
                }
                if row.isLikelyMe {
                    Image(systemName: "mic.fill")
                        .foregroundStyle(.secondary)
                        .help(L("This voice comes through your microphone: probably you."))
                }
                if let onLink {
                    Menu {
                        if row.contact != nil {
                            Button(L("No contact")) { onLink(nil) }
                            Divider()
                        }
                        if let onCreateContact, row.contact == nil {
                            let proposed = draft.trimmingCharacters(in: .whitespaces).isEmpty
                                ? SpeakerLabel.defaultName(for: row.slot) : draft.trimmingCharacters(in: .whitespaces)
                            Button(L("Create contact “%@”", proposed)) { onCreateContact(proposed) }
                            if !contacts.isEmpty { Divider() }
                        }
                        ForEach(contacts) { c in
                            Button(c.name) { onLink(c.id) }
                        }
                    } label: {
                        Image(systemName: row.contact == nil ? "person.crop.circle" : "person.crop.circle.fill")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                    .help(L("Contact"))
                }
            }
        }
    }
}
