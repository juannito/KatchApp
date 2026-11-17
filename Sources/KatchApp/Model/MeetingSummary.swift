import Foundation

struct ActionItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var task: String
    var owner: String?
    var due: String?

    enum CodingKeys: String, CodingKey { case task, owner, due }
}

enum QuestionStatus: String, Codable, Hashable {
    case answered, partial, unanswered
}

/// The model's verdict on one prepared question. `question` and `checkedAt` always come from the
/// session (what the person wrote and when they marked it); `status` and `answer` from the model.
struct QuestionAnswer: Codable, Identifiable, Hashable {
    var id = UUID()
    var question: String
    var status: QuestionStatus
    var answer: String?
    var checkedAt: TimeInterval?

    enum CodingKeys: String, CodingKey { case question, status, answer, checkedAt }

    /// The person marked it answered but the transcript does not fully back that up.
    var disagreesWithCheck: Bool { checkedAt != nil && status != .answered }
}

/// LLM-generated minutes for a session. Stored as summary.json + summary.md next to the transcript.
struct MeetingSummary: Codable, Hashable {
    var summary: String
    var decisions: [String]
    var actionItems: [ActionItem]
    var followUps: [String]
    /// Verdict per prepared question; nil when the session had none.
    var questions: [QuestionAnswer]?
    var generatedAt: Date
    var provider: String
    var model: String
    /// True once a person or the chat changed what the model first wrote.
    var edited: Bool?

    enum CodingKeys: String, CodingKey {
        case summary, decisions, actionItems = "action_items", followUps = "follow_ups", questions, generatedAt, provider, model, edited
    }

    func markdown() -> String {
        var md = "## \(L("Summary"))\n\n\(summary)\n\n"
        if !decisions.isEmpty {
            md += "## \(L("Decisions"))\n\n" + decisions.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if !actionItems.isEmpty {
            md += "## \(L("Action items"))\n\n"
            for a in actionItems {
                var line = "- [ ] \(a.task)"
                if let o = a.owner, !o.isEmpty { line += " — **\(o)**" }
                if let d = a.due, !d.isEmpty { line += " (\(d))" }
                md += line + "\n"
            }
            md += "\n"
        }
        if !followUps.isEmpty {
            md += "## \(L("Follow-ups"))\n\n" + followUps.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
        }
        if let questions, !questions.isEmpty {
            md += "## \(L("Questions"))\n\n"
            for q in questions {
                let icon = q.status == .answered ? "✅" : q.status == .partial ? "🟡" : "❌"
                var line = "- \(icon) **\(q.question)**"
                if let a = q.answer, !a.isEmpty { line += " — \(a)" }
                if let t = q.checkedAt {
                    line += " _(\(L("marked at %@", TimeFormat.clock(t)))\(q.disagreesWithCheck ? ", " + L("not fully answered") : ""))_"
                }
                md += line + "\n"
            }
            md += "\n"
        }
        md += "_\(provider) · \(model)\(edited == true ? " · " + L("edited") : "")_\n"
        return md
    }
}
