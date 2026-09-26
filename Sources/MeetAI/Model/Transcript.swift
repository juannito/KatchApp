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

struct SessionDocument: Codable {
    var id: UUID
    var title: String? = nil
    var startedAt: Date
    var endedAt: Date?
    var micEnabled: Bool
    var systemAudioEnabled: Bool
    var speakerNames: [Int: String]
    var speakerMicFraction: [Int: Double]
    var segments: [TranscriptSegment]
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

    func markdown() -> String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        df.locale = Locale(identifier: L10n.current)
        var md = "# \(displayTitle) — \(df.string(from: startedAt))\n\n"
        let sources = [micEnabled ? L("microphone") : nil, systemAudioEnabled ? L("system audio") : nil]
            .compactMap { $0 }.joined(separator: " + ")
        md += "\(L("Sources")): \(sources)\n\n"
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
