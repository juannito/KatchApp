import SwiftUI

/// Checklist of questions to get answered in the meeting. Written before (or during) the
/// recording; each check stores the recording time so the summary can compare it with the transcript.
struct QuestionsPanel: View {
    @EnvironmentObject var session: RecordingSession
    @State private var draft = ""

    private var checkedCount: Int { session.questions.filter { $0.checkedAt != nil }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("Questions")).font(.headline)
                Spacer()
                if !session.questions.isEmpty {
                    Text("\(checkedCount)/\(session.questions.count)")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            if session.questions.isEmpty {
                Text(L("Write what you want answered; check each one as it is."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(session.questions) { q in QuestionRow(question: q) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField(L("Add a question…"), text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
                // A pasted list arrives with line breaks: one question per line.
                .onChange(of: draft) { _, text in
                    if text.contains(where: \.isNewline) { commit() }
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func commit() {
        session.addQuestions(from: draft)
        draft = ""
    }
}

private struct QuestionRow: View {
    @EnvironmentObject var session: RecordingSession
    let question: MeetingQuestion
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { session.toggleQuestion(question.id) } label: {
                Image(systemName: question.checkedAt == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(question.checkedAt == nil ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(!session.canCheckQuestions)
            .help(session.canCheckQuestions ? L("Mark as answered") : L("You can check questions while recording"))
            VStack(alignment: .leading, spacing: 1) {
                Text(question.text)
                    .strikethrough(question.checkedAt != nil)
                    .foregroundStyle(question.checkedAt == nil ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let t = question.checkedAt {
                    Text(TimeFormat.clock(t)).font(.caption2).monospacedDigit().foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button { session.removeQuestion(question.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
                .opacity(hovering ? 1 : 0)
                .help(L("Remove question"))
        }
        .onHover { hovering = $0 }
    }
}
