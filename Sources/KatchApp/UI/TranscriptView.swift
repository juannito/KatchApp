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
    /// Search term to highlight inside turns (case/accent-insensitive).
    var highlight: String = ""
    /// Turn to scroll to and emphasise (search navigation).
    var focusID: UUID? = nil
    /// Playback position in seconds; the turn and word under it are highlighted.
    var playhead: Double? = nil
    /// Called when a turn is clicked (seek).
    var onSelectTurn: ((TranscriptSegment) -> Void)? = nil

    private var playingTurnID: UUID? {
        guard let t = playhead else { return nil }
        return turns.first { t >= $0.start && t < $0.end + 0.3 }?.id
    }

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
                        TurnRow(
                            turn: turn, name: SpeakerLabel.name(for: turn.speaker, names: names),
                            highlight: highlight, isFocused: turn.id == focusID,
                            playhead: turn.id == playingTurnID ? playhead : nil)
                        .id(turn.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { onSelectTurn?(turn) }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: turns.count) { _, _ in
                if autoScroll { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: focusID) { _, id in
                if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
            .onChange(of: playingTurnID) { _, id in
                if let id, playhead != nil { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
            .onAppear {
                if let focusID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { proxy.scrollTo(focusID, anchor: .center) }
                }
            }
        }
    }
}

struct TurnRow: View {
    let turn: TranscriptSegment
    let name: String
    var highlight: String = ""
    var isFocused = false
    /// Playback position inside this turn, or nil when it is not the current turn.
    var playhead: Double? = nil

    private var attributedText: AttributedString {
        var attr = AttributedString(turn.text)
        if let t = playhead {
            // Karaoke: words already spoken are primary, the current word is accented, the rest dim.
            // Map each word to its character range in the joined text (words are joined with single spaces).
            let text = turn.text
            var cursor = text.startIndex
            for (i, w) in turn.words.enumerated() {
                guard let end = text.index(cursor, offsetBy: w.text.count, limitedBy: text.endIndex) else { break }
                if let lo = AttributedString.Index(cursor, within: attr), let hi = AttributedString.Index(end, within: attr) {
                    if t >= w.start && t < w.end {
                        attr[lo..<hi].foregroundColor = .accentColor
                        attr[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
                    } else if t < w.start {
                        attr[lo..<hi].foregroundColor = .secondary
                    }
                }
                cursor = end
                if i < turn.words.count - 1, cursor < text.endIndex { cursor = text.index(after: cursor) }
            }
        }
        let q = highlight.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return attr }
        let text = turn.text
        var searchRange = text.startIndex..<text.endIndex
        while let r = text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
            if let lo = AttributedString.Index(r.lowerBound, within: attr),
                let hi = AttributedString.Index(r.upperBound, within: attr)
            {
                attr[lo..<hi].backgroundColor = isFocused ? .orange.opacity(0.7) : .yellow.opacity(0.45)
                attr[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
            }
            searchRange = r.upperBound..<text.endIndex
        }
        return attr
    }

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
                Text(attributedText)
                    .font(.body)
                    .textSelection(.enabled)
                    .foregroundStyle(turn.attributed ? .primary : .secondary)
            }
        }
        .padding(6)
        .background(isFocused || playhead != nil ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .padding(-6)
    }
}

struct SpeakerRowModel: Identifiable {
    var id: Int { slot }
    let slot: Int
    let customName: String
    let contactName: String?
    let contact: Contact?
    let isLikelyMe: Bool
    var suggestion: (name: String, score: Float, contactID: String)? = nil
}

/// Speaker list with inline renaming and optional contact linking.
struct SpeakersPanel: View {
    let rows: [SpeakerRowModel]
    let contacts: [Contact]
    let onRename: (Int, String) -> Void
    let onLink: ((Int, String?) -> Void)?
    var onCreateContact: ((Int, String) -> Void)? = nil
    var onConfirmSuggestion: ((Int, String) -> Void)? = nil

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
                    onCreateContact: onCreateContact.map { create in { create(row.slot, $0) } },
                    onConfirmSuggestion: onConfirmSuggestion.map { confirm in { confirm(row.slot, $0) } })
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
    var onConfirmSuggestion: ((String) -> Void)? = nil
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
            if let sg = row.suggestion, row.contact == nil, let onConfirmSuggestion {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.magnifyingglass").foregroundStyle(.secondary)
                    Text(L("Looks like %@ (%d%%)", sg.name, Int((sg.score * 100).rounded()))).font(.caption)
                    Button(L("Confirm")) { onConfirmSuggestion(sg.contactID) }.controlSize(.mini)
                }
                .padding(.leading, 20)
            }
        }
    }
}
