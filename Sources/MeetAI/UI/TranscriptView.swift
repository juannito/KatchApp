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

/// Speaker list with inline renaming. `onRename` is called on submit.
struct SpeakersPanel: View {
    let slots: [Int]
    let names: [Int: String]
    let micFraction: [Int: Double]
    let showMicHint: Bool
    let onRename: (Int, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Speakers")).font(.headline)
            if slots.isEmpty {
                Text(L("They appear as they speak."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(slots, id: \.self) { slot in
                SpeakerRow(
                    slot: slot,
                    name: names[slot] ?? "",
                    isLikelyMe: showMicHint && (micFraction[slot] ?? 0) > 0.6,
                    onRename: { onRename(slot, $0) })
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
    let slot: Int
    let name: String
    let isLikelyMe: Bool
    let onRename: (String) -> Void
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(SpeakerPalette.color(for: slot)).frame(width: 12, height: 12)
            TextField(SpeakerLabel.defaultName(for: slot), text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onRename(draft) }
                .onAppear { draft = name }
            if isLikelyMe {
                Image(systemName: "mic.fill")
                    .foregroundStyle(.secondary)
                    .help(L("This voice comes through your microphone: probably you."))
            }
        }
    }
}
