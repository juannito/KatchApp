import AppKit
import SwiftUI

/// Minutes panel for a saved session: read, copy, edit by hand, or refine through a chat.
struct SummaryView: View {
    @EnvironmentObject var service: SummaryService
    @EnvironmentObject var settings: SummarySettings
    @EnvironmentObject var contacts: ContactStore
    let folder: URL
    @State private var summary: MeetingSummary?
    @State private var confirmRegenerate = false
    @State private var copied = false
    @State private var showChat = false
    @State private var history: [(url: URL, summary: MeetingSummary)] = []

    // Hand editing works on a draft that only replaces the summary on Save.
    @State private var editing = false
    @State private var draft = MeetingSummary(summary: "", decisions: [], actionItems: [], followUps: [], generatedAt: Date(), provider: "", model: "")
    @State private var decisionsText = ""
    @State private var followUpsText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    toolbar
                    if let err = service.error(for: folder) {
                        Label(err, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    if !settings.isConfigured {
                        Text(L("Summary provider is not configured. Open Settings > Summary.")).foregroundStyle(.secondary)
                    }
                    if editing {
                        editor
                    } else if let s = summary {
                        reader(s)
                    } else if !service.isRunning(folder) {
                        Text(L("No summary yet.")).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showChat, summary != nil, !editing {
                Divider()
                SummaryChatPanel(folder: folder, contactNames: contactNames)
                    .frame(maxHeight: 340)
            }
        }
        .confirmationDialog(L("Regenerate the summary?"), isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button(L("Regenerate")) { generate() }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("The current summary, including your edits, will be replaced by a new one from %@. The old one stays in the version history.", settings.provider.title))
        }
        .onAppear { reload() }
        .onChange(of: service.version) { _, _ in reload() }
    }

    /// A chat turn in flight will overwrite the summary when it lands, so hand edits wait for it.
    private var chatting: Bool { service.isChatting(folder) }

    private var contactNames: [String: String] {
        Dictionary(uniqueKeysWithValues: contacts.contacts.map { ($0.id, $0.name) })
    }

    private func reload() {
        summary = SummaryService.read(at: folder)
        history = SummaryService.history(at: folder)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            if service.isRunning(folder) {
                ProgressView().controlSize(.small)
                Text(L("Generating summary…")).foregroundStyle(.secondary)
            } else if summary == nil {
                Button(L("Generate summary")) { generate() }
                    .disabled(!settings.isConfigured)
            } else if editing {
                Button(L("Save")) { commitEdit() }.keyboardShortcut(.return, modifiers: .command)
                Button(L("Cancel")) { editing = false }
            } else {
                Button { copy() } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .help(L("Copy the summary"))
                Button { startEditing() } label: { Image(systemName: "pencil") }
                    .disabled(chatting)
                    .help(L("Edit the summary"))
                Button { showChat.toggle() } label: {
                    Image(systemName: showChat ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                }
                .help(L("Refine the summary in a chat"))
                if !history.isEmpty {
                    Menu {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, h in
                            Button(historyLabel(h.summary)) {
                                service.restore(h.summary, folder: folder)
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(chatting)
                    .help(L("Previous versions"))
                }
                Button { confirmRegenerate = true } label: { Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90") }
                    .disabled(!settings.isConfigured || chatting)
                    .help(L("Regenerate the summary"))
            }
            Spacer()
            if let summary {
                Text("\(summary.provider) · \(summary.model)\(summary.edited == true ? " · " + L("edited") : "")")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.bordered)
    }

    private func historyLabel(_ s: MeetingSummary) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        let who = s.edited == true ? L("edited") : s.model
        return L("Restore version from %@ (%@)", f.string(from: s.generatedAt), who)
    }

    private func copy() {
        guard let summary else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary.markdown(), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func generate() {
        service.generate(folder: folder, contactNames: contactNames)
    }

    // MARK: - Reading

    @ViewBuilder
    private func reader(_ s: MeetingSummary) -> some View {
        section(L("Summary")) { Text(s.summary).textSelection(.enabled) }
        section(L("Decisions")) { bullets(s.decisions) }
        section(L("Action items")) {
            if s.actionItems.isEmpty {
                Text(L("Nothing to report.")).foregroundStyle(.secondary)
            } else {
                ForEach(s.actionItems) { a in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.square").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.task).textSelection(.enabled)
                            HStack(spacing: 10) {
                                if let o = a.owner, !o.isEmpty { Label(o, systemImage: "person") }
                                if let d = a.due, !d.isEmpty { Label(d, systemImage: "calendar") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        section(L("Follow-ups")) { bullets(s.followUps) }
    }

    // MARK: - Editing

    private func startEditing() {
        guard let summary else { return }
        draft = summary
        decisionsText = summary.decisions.joined(separator: "\n")
        followUpsText = summary.followUps.joined(separator: "\n")
        editing = true
    }

    private func commitEdit() {
        func lines(_ text: String) -> [String] {
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        var result = draft
        result.decisions = lines(decisionsText)
        result.followUps = lines(followUpsText)
        result.actionItems = draft.actionItems.filter { !$0.task.trimmingCharacters(in: .whitespaces).isEmpty }
        if result != summary { service.saveEdited(result, folder: folder) }
        editing = false
    }

    @ViewBuilder
    private var editor: some View {
        section(L("Summary")) { textBox($draft.summary, minHeight: 140) }
        section(L("Decisions")) {
            textBox($decisionsText, minHeight: 80)
            Text(L("One per line.")).font(.caption).foregroundStyle(.tertiary)
        }
        section(L("Action items")) {
            ForEach($draft.actionItems) { $item in
                HStack(alignment: .top, spacing: 8) {
                    TextField(L("Task"), text: $item.task, axis: .vertical)
                    TextField(L("Owner"), text: optional($item.owner)).frame(width: 120)
                    TextField(L("Due"), text: optional($item.due)).frame(width: 100)
                    Button {
                        draft.actionItems.removeAll { $0.id == item.id }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                }
                .textFieldStyle(.roundedBorder)
            }
            Button { draft.actionItems.append(ActionItem(task: "", owner: nil, due: nil)) } label: {
                Label(L("Add action item"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
        section(L("Follow-ups")) {
            textBox($followUpsText, minHeight: 80)
            Text(L("One per line.")).font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func textBox(_ text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body)
            .frame(minHeight: minHeight)
            .padding(4)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    @ViewBuilder
    private func bullets(_ items: [String]) -> some View {
        if items.isEmpty {
            Text(L("Nothing to report.")).foregroundStyle(.secondary)
        } else {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                    Text(item).textSelection(.enabled)
                }
            }
        }
    }
}

/// Conversation with the model about one summary: "change X", "that owner is wrong", "did they
/// really decide Y?". The model re-reads the transcript and may rewrite the minutes.
struct SummaryChatPanel: View {
    @EnvironmentObject var service: SummaryService
    let folder: URL
    let contactNames: [String: String]
    @State private var input = ""

    var body: some View {
        let messages = service.messages(for: folder)
        let busy = service.isChatting(folder)
        VStack(alignment: .leading, spacing: 8) {
            Color.clear.frame(height: 0).task(id: folder) { service.loadChat(folder) }
            HStack {
                Label(L("Refine the summary"), systemImage: "bubble.left.and.bubble.right").font(.headline)
                Spacer()
                if !messages.isEmpty {
                    Button(L("Clear chat")) { service.clearChat(folder: folder) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if messages.isEmpty {
                            Text(L("Tell the model what to fix, e.g. “the owner of the second action item is Eduardo” or “we did not decide to postpone”. It re-reads the transcript and updates the summary when needed."))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(messages) { m in bubble(m).id(m.id) }
                        if busy {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(L("Thinking…")).foregroundStyle(.secondary)
                            }
                            .id("busy")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
                }
                .onChange(of: busy) { _, now in
                    if now { withAnimation { proxy.scrollTo("busy", anchor: .bottom) } }
                }
            }
            if let err = service.chatError(for: folder) {
                Label(err, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(L("Message"), text: $input, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .disabled(busy || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
    }

    private func send() {
        let text = input
        guard !service.isChatting(folder) else { return }
        input = ""
        service.sendChat(folder: folder, contactNames: contactNames, text: text)
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        let mine = m.role == "user"
        VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            Text(m.text)
                .textSelection(.enabled)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(mine ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            if m.changedSummary {
                Label(L("Summary updated"), systemImage: "checkmark.circle").font(.caption2).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}
