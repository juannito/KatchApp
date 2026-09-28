import Foundation

struct Word: Codable, Identifiable, Sendable {
    var id = UUID()
    var text: String
    var start: Double
    var end: Double
    var speaker: Int?
}

struct TranscriptSegment: Codable, Identifiable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var speaker: Int?          // arrival-ordered speaker slot (0..7), nil = unknown
    var attributed: Bool       // false while waiting for diarization
    var words: [Word]

    var text: String {
        words.map(\.text).joined(separator: " ")
    }
}

struct TimeRange: Codable, Sendable, Hashable {
    var start: Double
    var end: Double
    var duration: Double { end - start }
}

struct SessionDocument: Codable {
    var id: UUID
    var title: String? = nil
    var project: String? = nil
    var startedAt: Date
    var endedAt: Date?
    var micEnabled: Bool
    var systemAudioEnabled: Bool
    var speakerNames: [Int: String]
    var speakerMicFraction: [Int: Double]
    var speakerContacts: [Int: String] = [:]     // slot -> contact id
    var speakerEmbeddings: [Int: [Float]] = [:]  // slot -> CAM++ voice embedding
    var platform: String? = nil                  // bundle id of the meeting app (Zoom, Teams…)
    var platformName: String? = nil
    var segments: [TranscriptSegment]

    init(
        id: UUID, title: String? = nil, project: String? = nil, startedAt: Date, endedAt: Date?,
        micEnabled: Bool, systemAudioEnabled: Bool, speakerNames: [Int: String], speakerMicFraction: [Int: Double],
        speakerContacts: [Int: String] = [:], speakerEmbeddings: [Int: [Float]] = [:], segments: [TranscriptSegment]
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.micEnabled = micEnabled
        self.systemAudioEnabled = systemAudioEnabled
        self.speakerNames = speakerNames
        self.speakerMicFraction = speakerMicFraction
        self.speakerContacts = speakerContacts
        self.speakerEmbeddings = speakerEmbeddings
        self.segments = segments
    }

    enum CodingKeys: String, CodingKey {
        case id, title, project, startedAt, endedAt, micEnabled, systemAudioEnabled, speakerNames, speakerMicFraction
        case speakerContacts, speakerEmbeddings, platform, platformName, segments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        project = try c.decodeIfPresent(String.self, forKey: .project)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt)
        micEnabled = try c.decode(Bool.self, forKey: .micEnabled)
        systemAudioEnabled = try c.decode(Bool.self, forKey: .systemAudioEnabled)
        speakerNames = try c.decodeIfPresent([Int: String].self, forKey: .speakerNames) ?? [:]
        speakerMicFraction = try c.decodeIfPresent([Int: Double].self, forKey: .speakerMicFraction) ?? [:]
        speakerContacts = try c.decodeIfPresent([Int: String].self, forKey: .speakerContacts) ?? [:]
        speakerEmbeddings = try c.decodeIfPresent([Int: [Float]].self, forKey: .speakerEmbeddings) ?? [:]
        platform = try c.decodeIfPresent(String.self, forKey: .platform)
        platformName = try c.decodeIfPresent(String.self, forKey: .platformName)
        segments = try c.decodeIfPresent([TranscriptSegment].self, forKey: .segments) ?? []
    }

    /// Time ranges where only this speaker talks, derived from the transcript segments.
    /// Used to compute a voice fingerprint for sessions recorded without one.
    func speechRanges(for slot: Int, minDuration: Double = 0.8) -> [TimeRange] {
        let mine = segments.filter { $0.speaker == slot && $0.attributed }
        let others = segments.filter { $0.speaker != slot && $0.attributed }
        return mine.compactMap { seg in
            let overlaps = others.contains { $0.start < seg.end && seg.start < $0.end }
            guard !overlaps, seg.end - seg.start >= minDuration else { return nil }
            return TimeRange(start: seg.start, end: seg.end)
        }
    }

    /// Names to display: linked contact name wins over the custom per-session name.
    func effectiveNames(contactNames: [String: String]) -> [Int: String] {
        var names = speakerNames
        for (slot, cid) in speakerContacts {
            if let n = contactNames[cid] { names[slot] = n }
        }
        return names
    }
}

enum SpeakerLabel {
    static func defaultName(for slot: Int?) -> String {
        guard let slot else { return L("Speaker ?") }
        return L("Speaker %d", slot + 1)
    }

    static func name(for slot: Int?, names: [Int: String]) -> String {
        guard let slot, let custom = names[slot], !custom.trimmingCharacters(in: .whitespaces).isEmpty else {
            return defaultName(for: slot)
        }
        return custom
    }
}

enum TimeFormat {
    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600
        let m = (s % 3600) / 60
        let sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}

extension SessionDocument {
    var displayTitle: String {
        if let t = title?.trimmingCharacters(in: .whitespaces), !t.isEmpty { return t }
        return L("Meeting")
    }

    var duration: TimeInterval {
        segments.last.map(\.end) ?? (endedAt?.timeIntervalSince(startedAt) ?? 0)
    }

    /// Consecutive segments from the same speaker merged into turns.
    var turns: [TranscriptSegment] {
        Self.mergeTurns(segments)
    }

    static func mergeTurns(_ segments: [TranscriptSegment], maxGap: Double = 1.5) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        for seg in segments {
            if var last = out.last, last.speaker == seg.speaker, last.attributed == seg.attributed,
                seg.start - last.end <= maxGap
            {
                last.words.append(contentsOf: seg.words)
                last.end = max(last.end, seg.end)
                out[out.count - 1] = last
            } else {
                out.append(seg)
            }
        }
        return out
    }

    /// Full export: header, summary (when available) and the transcript.
    func exportMarkdown(summary: MeetingSummary?) -> String {
        var md = markdown()
        guard let summary else { return md }
        // Insert the summary before the transcript heading.
        let marker = "## \(L("Transcript"))"
        if let r = md.range(of: marker) {
            md.replaceSubrange(r.lowerBound..<r.lowerBound, with: summary.markdown() + "\n")
        } else {
            md += "\n" + summary.markdown()
        }
        return md
    }

    func markdown() -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        df.locale = Locale(identifier: L10n.current)
        var md = "# \(displayTitle) — \(df.string(from: startedAt))\n\n"
        let sources = [micEnabled ? L("microphone") : nil, systemAudioEnabled ? L("system audio") : nil]
            .compactMap { $0 }.joined(separator: " + ")
        md += "\(L("Sources")): \(sources)\n"
        if let platformName { md += "\(L("Platform")): \(platformName)\n" }
        md += "\n"
        let slots = Set(segments.compactMap(\.speaker)).sorted()
        if !slots.isEmpty {
            md += "## \(L("Speakers"))\n\n"
            for slot in slots {
                md += "- \(SpeakerLabel.name(for: slot, names: speakerNames))"
                if let f = speakerMicFraction[slot], f > 0.6 { md += " _\(L("(local microphone)"))_" }
                md += "\n"
            }
            md += "\n"
        }
        md += "## \(L("Transcript"))\n\n"
        for turn in turns {
            let name = SpeakerLabel.name(for: turn.speaker, names: speakerNames)
            md += "**[\(TimeFormat.clock(turn.start))] \(name):** \(turn.text)\n\n"
        }
        return md
    }
}
