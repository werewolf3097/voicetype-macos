import Foundation

struct MeetingRecapOutput {
    let recapMarkdown: String
    let actionItems: [MeetingActionItem]
}

enum MeetingRecapGenerator {
    static func generate(
        for meeting: MeetingRecord,
        anthropicApiKey: String
    ) async -> MeetingRecapOutput {
        let trimmedKey = anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty, !meeting.segments.isEmpty || !meeting.rawNotes.isEmpty {
            do {
                return try await ClaudeClient(apiKey: trimmedKey).generateMeetingRecap(for: meeting)
            } catch {
                // Fall back to local recap builder if Claude fails
            }
        }
        return LocalRecapBuilder.build(for: meeting)
    }
}

enum LocalRecapBuilder {
    private static let actionKeywords: [String] = [
        "нужно", "надо", "сделаю", "сделать", "отправлю", "отправить", "подготовлю", "подготовить",
        "проверю", "проверить", "напишу", "написать", "созвонимся", "договорились", "задача",
        "дедлайн", "к пятнице", "к понедельнику", "завтра", "сегодня", "назначим", "скину",
        "посмотрю", "обновлю", "исправлю", "добавлю", "kerak", "qilaman", "yuboraman", "todo", "action"
    ]

    static func build(for meeting: MeetingRecord) -> MeetingRecapOutput {
        var sections: [String] = []
        let headings = meeting.template.sectionHeadings

        // 1. Overview / Gapi summary / Talk-time breakdown
        let overviewHeading = headings.first ?? "Резюме встречи"
        var overviewLines: [String] = ["## \(overviewHeading)"]

        if let gapiSummary = meeting.gapiSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !gapiSummary.isEmpty {
            overviewLines.append(gapiSummary)
            overviewLines.append("")
        }

        let speakerStats = buildSpeakerStats(for: meeting)
        if !speakerStats.isEmpty {
            overviewLines.append("**Участники и активность:** " + speakerStats)
        }

        let totalWords = meeting.segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        if totalWords > 0 {
            overviewLines.append("**Объём обсуждения:** \(totalWords) слов (\(meeting.segments.count) реплик)")
        }
        sections.append(overviewLines.joined(separator: "\n"))

        // 2. User's raw notes (Granola anchor)
        let cleanNotes = meeting.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanNotes.isEmpty {
            var noteLines: [String] = ["## Заметки и контекст"]
            let lines = cleanNotes.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                if trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") {
                    noteLines.append(trimmed)
                } else {
                    noteLines.append("- \(trimmed)")
                }
            }
            sections.append(noteLines.joined(separator: "\n"))
        }

        // 3. Key discussion points from segments
        let keyPointsHeading = headings.count > 1 ? headings[1] : "Ключевые тезисы"
        let highlights = extractKeySegments(from: meeting, maxCount: 8)
        if !highlights.isEmpty {
            var pointLines: [String] = ["## \(keyPointsHeading)"]
            for seg in highlights {
                let ts = MeetingRecord.formatTimestamp(seg.start)
                let speaker = meeting.displayName(for: seg.speaker)
                pointLines.append("- `[\(ts)]` **\(speaker):** \(seg.text.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            sections.append(pointLines.joined(separator: "\n"))
        }

        // 4. Extract Action Items from both user notes and transcript
        let actionItems = extractActionItems(from: meeting)
        if !actionItems.isEmpty {
            let nextStepsHeading = headings.last ?? "Следующие шаги"
            var stepLines: [String] = ["## \(nextStepsHeading)"]
            for item in actionItems {
                let assigneePrefix = item.assignee.map { "**\($0):** " } ?? ""
                let tsSuffix = item.timestamp.map { " `[\(MeetingRecord.formatTimestamp($0))]`" } ?? ""
                stepLines.append("- \(assigneePrefix)\(item.text)\(tsSuffix)")
            }
            sections.append(stepLines.joined(separator: "\n"))
        }

        if sections.isEmpty {
            sections.append("_Речь на встрече не обнаружена или запись была слишком короткой._")
        }

        return MeetingRecapOutput(
            recapMarkdown: sections.joined(separator: "\n\n"),
            actionItems: actionItems
        )
    }

    private static func buildSpeakerStats(for meeting: MeetingRecord) -> String {
        guard !meeting.segments.isEmpty else { return "" }
        var durationsBySpeaker: [Int: Double] = [:]
        var wordsBySpeaker: [Int: Int] = [:]

        for seg in meeting.segments {
            let spk = seg.speaker ?? 0
            let dur = max(0, (seg.end ?? 0) - (seg.start ?? 0))
            durationsBySpeaker[spk, default: 0] += dur
            wordsBySpeaker[spk, default: 0] += seg.text.split(whereSeparator: \.isWhitespace).count
        }

        let totalWords = max(1, wordsBySpeaker.values.reduce(0, +))
        let sortedSpeakers = wordsBySpeaker.keys.sorted()
        return sortedSpeakers.map { spk in
            let name = meeting.displayName(for: spk)
            let pct = Int((Double(wordsBySpeaker[spk] ?? 0) / Double(totalWords) * 100).rounded())
            return "\(name) (\(pct)%)"
        }.joined(separator: ", ")
    }

    private static func extractKeySegments(from meeting: MeetingRecord, maxCount: Int) -> [GapiTranscription.Segment] {
        let meaningful = meeting.segments.filter {
            $0.text.split(whereSeparator: \.isWhitespace).count >= 5
        }
        guard !meaningful.isEmpty else {
            return Array(meeting.segments.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.prefix(maxCount))
        }
        if meaningful.count <= maxCount {
            return meaningful
        }
        // Pick well-distributed substantive segments across the meeting timeline
        var picked: [GapiTranscription.Segment] = []
        let step = Double(meaningful.count - 1) / Double(max(1, maxCount - 1))
        for i in 0..<maxCount {
            let idx = min(meaningful.count - 1, Int((Double(i) * step).rounded()))
            picked.append(meaningful[idx])
        }
        return picked
    }

    static func extractActionItems(from meeting: MeetingRecord) -> [MeetingActionItem] {
        var items: [MeetingActionItem] = []
        var seen = Set<String>()

        // 1. Check raw notes for explicit checkboxes or "TODO:" lines
        for line in meeting.rawNotes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let prefixes = ["- [ ] ", "* [ ] ", "[] ", "TODO:", "Задача:", "Action:"]
            for prefix in prefixes where trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty && seen.insert(text.lowercased()).inserted {
                    items.append(MeetingActionItem(text: text))
                }
            }
        }

        // 2. Scan transcript segments for commitment / action keywords
        for seg in meeting.segments {
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = text.lowercased()
            guard text.count >= 12 else { continue }
            if actionKeywords.contains(where: { lower.contains($0) }) {
                let speaker = meeting.displayName(for: seg.speaker)
                let key = lower
                if seen.insert(key).inserted {
                    items.append(
                        MeetingActionItem(
                            text: text,
                            completed: false,
                            assignee: speaker,
                            timestamp: seg.start
                        )
                    )
                }
            }
            if items.count >= 8 { break }
        }

        return items
    }
}
