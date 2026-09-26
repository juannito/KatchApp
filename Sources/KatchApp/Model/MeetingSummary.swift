import Foundation

struct ActionItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var task: String
    var owner: String?
    var due: String?

    enum CodingKeys: String, CodingKey { case task, owner, due }
}

/// LLM-generated minutes for a session. Stored as summary.json + summary.md next to the transcript.
struct MeetingSummary: Codable, Hashable {
    var summary: String
    var decisions: [String]
    var actionItems: [ActionItem]
    var followUps: [String]
    var generatedAt: Date
    var provider: String
    var model: String

    enum CodingKeys: String, CodingKey {
        case summary, decisions, actionItems = "action_items", followUps = "follow_ups", generatedAt, provider, model
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
        md += "_\(provider) · \(model)_\n"
        return md
    }
}
