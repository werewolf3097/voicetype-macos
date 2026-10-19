import AppKit
import Foundation

enum MeetingTemplate: String, CaseIterable, Identifiable, Codable {
    case general = "Общая встреча"
    case oneOnOne = "1-на-1"
    case standup = "Стендап / Дейли"
    case sales = "Звонок с клиентом"
    case interview = "Интервью"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .general: return "person.3"
        case .oneOnOne: return "person.2"
        case .standup: return "bolt.horizontal"
        case .sales: return "briefcase"
        case .interview: return "person.text.rectangle"
        }
    }

    var sectionHeadings: [String] {
        switch self {
        case .general:
            return ["Резюме встречи", "Ключевые тезисы", "Принятые решения", "Следующие шаги"]
        case .oneOnOne:
            return ["Главное из 1-на-1", "Прогресс и успехи", "Блокеры и вопросы", "Договорённости и рост"]
        case .standup:
            return ["Что сделано", "В работе сегодня", "Блокеры и риски", "Экшен-айтемы"]
        case .sales:
            return ["Контекст и запрос клиента", "Ключевые боли и требования", "Обсуждённое предложение и бюджет", "Следующие шаги"]
        case .interview:
            return ["Профиль кандидата", "Сильные стороны и опыт", "Зоны риска и вопросы", "Итоговый вердикт и следующие шаги"]
        }
    }
}

struct MeetingActionItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var text: String
    var completed: Bool = false
    var assignee: String? = nil
    var timestamp: Double? = nil
}

enum MeetingStatus: Codable, Equatable {
    case recording
    case transcribing
    case summarizing
    case ready
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case kind, message
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "recording": self = .recording
        case "transcribing": self = .transcribing
        case "summarizing": self = .summarizing
        case "ready": self = .ready
        case "error":
            let msg = (try? container.decode(String.self, forKey: .message)) ?? "Ошибка"
            self = .error(msg)
        default:
            self = .ready
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .recording:
            try container.encode("recording", forKey: .kind)
        case .transcribing:
            try container.encode("transcribing", forKey: .kind)
        case .summarizing:
            try container.encode("summarizing", forKey: .kind)
        case .ready:
            try container.encode("ready", forKey: .kind)
        case .error(let msg):
            try container.encode("error", forKey: .kind)
            try container.encode(msg, forKey: .message)
        }
    }
}

struct MeetingRecord: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    let date: Date
    var durationSeconds: Double
    var template: MeetingTemplate
    var audioSource: MeetingAudioSource
    var stereoParties: Bool
    var rawNotes: String
    var recapMarkdown: String
    var actionItems: [MeetingActionItem]
    var segments: [GapiTranscription.Segment]
    var speakerNames: [Int: String]
    var languageCode: String?
    var languageSummary: String?
    var gapiSummary: String?
    var audioFileName: String?
    var status: MeetingStatus
    var progressSeconds: Double?

    func displayName(for speaker: Int?) -> String {
        guard let speaker else { return "Спикер" }
        if let custom = speakerNames[speaker], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        if stereoParties {
            return speaker == 0 ? "Вы" : "Собеседник"
        }
        return "Спикер \(speaker + 1)"
    }

    static func formatTimestamp(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

@MainActor
final class MeetingsStore: ObservableObject {
    @Published private(set) var meetings: [MeetingRecord] = []

    let baseDirectory: URL
    private let indexFileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceType", isDirectory: true)
        let meetingsDir = appSupport.appendingPathComponent("meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: meetingsDir, withIntermediateDirectories: true)
        self.baseDirectory = meetingsDir
        self.indexFileURL = meetingsDir.appendingPathComponent("meetings.json")
        load()
    }

    func folderURL(for meetingID: UUID) -> URL {
        let dir = baseDirectory.appendingPathComponent(meetingID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func markdownFileURL(for meetingID: UUID) -> URL {
        folderURL(for: meetingID).appendingPathComponent("recap.md")
    }

    func audioFileURL(for meeting: MeetingRecord) -> URL? {
        guard let name = meeting.audioFileName else { return nil }
        let url = folderURL(for: meeting.id).appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    @discardableResult
    func createDraftMeeting(
        title: String = "",
        template: MeetingTemplate = .general,
        audioSource: MeetingAudioSource = .micAndSystem
    ) -> MeetingRecord {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM, HH:mm"
        let defaultTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Встреча \(formatter.string(from: Date()))"
            : title

        let record = MeetingRecord(
            id: UUID(),
            title: defaultTitle,
            date: Date(),
            durationSeconds: 0,
            template: template,
            audioSource: audioSource,
            stereoParties: audioSource == .micAndSystem,
            rawNotes: "",
            recapMarkdown: "",
            actionItems: [],
            segments: [],
            speakerNames: audioSource == .micAndSystem ? [0: "Вы", 1: "Собеседник"] : [:],
            languageCode: nil,
            languageSummary: nil,
            gapiSummary: nil,
            audioFileName: nil,
            status: .recording,
            progressSeconds: nil
        )
        _ = folderURL(for: record.id)
        meetings.insert(record, at: 0)
        save()
        return record
    }

    func meeting(withID id: UUID) -> MeetingRecord? {
        meetings.first(where: { $0.id == id })
    }

    func update(_ id: UUID, mutate: (inout MeetingRecord) -> Void) {
        guard let idx = meetings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&meetings[idx])
        let updated = meetings[idx]
        save()
        if updated.status == .ready || !updated.recapMarkdown.isEmpty {
            writeMarkdownFile(for: updated)
        }
    }

    func delete(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        let dir = baseDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        save()
    }

    func revealMarkdownInFinder(_ meeting: MeetingRecord) {
        writeMarkdownFile(for: meeting)
        let url = markdownFileURL(for: meeting.id)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealAudioInFinder(_ meeting: MeetingRecord) {
        guard let url = audioFileURL(for: meeting) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func writeMarkdownFile(for meeting: MeetingRecord) {
        let md = fullExportMarkdown(for: meeting)
        let url = markdownFileURL(for: meeting.id)
        try? md.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    func fullExportMarkdown(for meeting: MeetingRecord) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        let mins = Int((meeting.durationSeconds / 60).rounded())
        var parts: [String] = []
        parts.append("# \(meeting.title)")
        parts.append("- **Дата:** \(formatter.string(from: meeting.date))")
        parts.append("- **Длительность:** \(max(1, mins)) мин (\(Int(meeting.durationSeconds.rounded())) сек)")
        parts.append("- **Шаблон:** \(meeting.template.rawValue)")
        if let lang = meeting.languageSummary {
            parts.append("- **Язык речи:** \(lang)")
        }
        parts.append("")

        if !meeting.recapMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(meeting.recapMarkdown)
            parts.append("")
        }

        if !meeting.actionItems.isEmpty {
            parts.append("## Задачи (Action Items)")
            for item in meeting.actionItems {
                let check = item.completed ? "x" : " "
                let ts = item.timestamp.map { " `[\(MeetingRecord.formatTimestamp($0))]`" } ?? ""
                parts.append("- [\(check)] \(item.text)\(ts)")
            }
            parts.append("")
        }

        if !meeting.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("## Мои заметки со встречи")
            parts.append(meeting.rawNotes)
            parts.append("")
        }

        if !meeting.segments.isEmpty {
            parts.append("## Полный транскрипт")
            for seg in meeting.segments where !seg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ts = MeetingRecord.formatTimestamp(seg.start)
                let speaker = meeting.displayName(for: seg.speaker)
                parts.append("- **[\(ts)] \(speaker):** \(seg.text)")
            }
            parts.append("")
        }

        return parts.joined(separator: "\n")
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var loaded = try? decoder.decode([MeetingRecord].self, from: data) else { return }
        // If app was quit mid-recording, mark interrupted recordings gracefully
        for i in loaded.indices {
            if loaded[i].status == .recording {
                loaded[i].status = .error("Запись была прервана при закрытии приложения.")
            }
        }
        meetings = loaded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(meetings) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }
}
