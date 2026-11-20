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
    case queued(String)
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
        case "queued":
            let msg = (try? container.decode(String.self, forKey: .message)) ?? "Ожидает подключения сервера распознавания"
            self = .queued(msg)
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
        case .queued(let msg):
            try container.encode("queued", forKey: .kind)
            try container.encode(msg, forKey: .message)
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
    var sysAudioFileName: String? = nil
    var transcriptionEngine: String? = nil
    var obsidianFileName: String? = nil
    var exportedFileName: String? = nil
    var status: MeetingStatus
    var progressSeconds: Double?

    func displayName(for speaker: Int?) -> String {
        guard let speaker else { return "Спикер" }
        if let custom = speakerNames[speaker], !custom.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return custom
        }
        if speaker == 0 {
            return "Вы"
        }
        if stereoParties {
            return "Собеседники"
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
        let url = baseDirectory
            .appendingPathComponent(meeting.id.uuidString, isDirectory: true)
            .appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func sysAudioFileURL(for meeting: MeetingRecord) -> URL? {
        guard let name = meeting.sysAudioFileName else { return nil }
        let url = baseDirectory
            .appendingPathComponent(meeting.id.uuidString, isDirectory: true)
            .appendingPathComponent(name)
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
            speakerNames: audioSource == .micAndSystem ? [0: "Вы", 1: "Собеседники"] : [:],
            languageCode: nil,
            languageSummary: nil,
            gapiSummary: nil,
            audioFileName: nil,
            sysAudioFileName: nil,
            transcriptionEngine: nil,
            obsidianFileName: nil,
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
        var updated = meetings[idx]
        if updated.status == .ready || !updated.recapMarkdown.isEmpty {
            if let exportedName = writeMarkdownFile(for: updated),
               exportedName != (updated.exportedFileName ?? updated.obsidianFileName) {
                meetings[idx].exportedFileName = exportedName
                updated = meetings[idx]
            }
        }
        save()
    }

    func delete(_ id: UUID) {
        meetings.removeAll { $0.id == id }
        let dir = baseDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        save()
    }

    func revealMarkdownInFinder(_ meeting: MeetingRecord) {
        _ = writeMarkdownFile(for: meeting)
        let url = markdownFileURL(for: meeting.id)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealAudioInFinder(_ meeting: MeetingRecord) {
        let urls = [audioFileURL(for: meeting), sysAudioFileURL(for: meeting)].compactMap { $0 }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    struct AudioStorageStats: Equatable {
        let meetingsWithAudioCount: Int
        let totalBytes: Int64
        let expiredMeetingsCount: Int
        let expiredBytes: Int64
    }

    private func existingAudioFileURLs(for meeting: MeetingRecord) -> [URL] {
        let dir = baseDirectory.appendingPathComponent(meeting.id.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        var candidateNames: Set<String> = [
            "mic.wav",
            "sys.wav",
            "mic_raw.wav",
            "sys_raw.wav",
            "stereo_gapi.wav"
        ]
        if let name = meeting.audioFileName, !name.isEmpty { candidateNames.insert(name) }
        if let sysName = meeting.sysAudioFileName, !sysName.isEmpty { candidateNames.insert(sysName) }

        return candidateNames.compactMap { name in
            let url = dir.appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    private func isAudioExpired(
        _ meeting: MeetingRecord,
        retention: MeetingAudioRetention,
        now: Date
    ) -> Bool {
        // Никогда не удаляем аудио для активных, стоящих в очереди или завершившихся с ошибкой встреч,
        // чтобы пользователь всегда мог повторить расшифровку.
        guard meeting.status == .ready else { return false }
        guard let days = retention.retentionDays else { return false }
        if days <= 0 {
            return true
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now)
            ?? now.addingTimeInterval(-TimeInterval(days) * 86_400)
        return meeting.date < cutoff
    }

    func audioStorageStats(retention: MeetingAudioRetention, now: Date = Date()) -> AudioStorageStats {
        var meetingsWithAudioCount = 0
        var totalBytes: Int64 = 0
        var expiredMeetingsCount = 0
        var expiredBytes: Int64 = 0

        for meeting in meetings {
            let urls = existingAudioFileURLs(for: meeting)
            guard !urls.isEmpty else { continue }
            var meetingBytes: Int64 = 0
            for url in urls {
                if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                    meetingBytes += Int64(size)
                }
            }
            meetingsWithAudioCount += 1
            totalBytes += meetingBytes
            if isAudioExpired(meeting, retention: retention, now: now) {
                expiredMeetingsCount += 1
                expiredBytes += meetingBytes
            }
        }

        return AudioStorageStats(
            meetingsWithAudioCount: meetingsWithAudioCount,
            totalBytes: totalBytes,
            expiredMeetingsCount: expiredMeetingsCount,
            expiredBytes: expiredBytes
        )
    }

    @discardableResult
    func cleanupExpiredAudio(retention: MeetingAudioRetention, now: Date = Date()) -> Int {
        guard retention.retentionDays != nil else { return 0 }
        var cleanedCount = 0

        for idx in meetings.indices {
            guard isAudioExpired(meetings[idx], retention: retention, now: now) else { continue }
            let urls = existingAudioFileURLs(for: meetings[idx])
            let hadMetadata = meetings[idx].audioFileName != nil || meetings[idx].sysAudioFileName != nil
            guard !urls.isEmpty || hadMetadata else { continue }

            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
            meetings[idx].audioFileName = nil
            meetings[idx].sysAudioFileName = nil
            cleanedCount += 1
        }

        if cleanedCount > 0 {
            save()
        }
        return cleanedCount
    }

    enum ExportDestination {
        case none
        case folder(URL)
        case webhook(URL)
    }

    func exportedFileURL(for meeting: MeetingRecord) -> URL? {
        guard case .folder(let folder) = Self.resolvedExportDestination() else { return nil }
        let fileName = meeting.exportedFileName ?? meeting.obsidianFileName ?? Self.makeExportFileName(for: meeting)
        return folder.appendingPathComponent(fileName)
    }

    func revealInExportFolder(_ meeting: MeetingRecord) {
        if let exportedName = writeMarkdownFile(for: meeting),
           let idx = meetings.firstIndex(where: { $0.id == meeting.id }),
           (meetings[idx].exportedFileName ?? meetings[idx].obsidianFileName) != exportedName {
            meetings[idx].exportedFileName = exportedName
            save()
        }
        if let url = exportedFileURL(for: meeting),
           FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            revealMarkdownInFinder(meeting)
        }
    }

    @discardableResult
    func writeMarkdownFile(for meeting: MeetingRecord) -> String? {
        let md = fullExportMarkdown(for: meeting)
        let url = markdownFileURL(for: meeting.id)
        try? md.data(using: .utf8)?.write(to: url, options: .atomic)

        let existingExported = meeting.exportedFileName ?? meeting.obsidianFileName
        guard meeting.status == .ready,
              case .folder(let folderURL) = Self.resolvedExportDestination() else {
            return existingExported
        }

        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let targetFileName = Self.makeExportFileName(for: meeting)
        let targetURL = folderURL.appendingPathComponent(targetFileName)

        if let prevName = existingExported,
           !prevName.isEmpty,
           prevName != targetFileName {
            let prevURL = folderURL.appendingPathComponent(prevName)
            try? FileManager.default.removeItem(at: prevURL)
        }

        do {
            try md.data(using: .utf8)?.write(to: targetURL, options: .atomic)
            return targetFileName
        } catch {
            return existingExported
        }
    }

    func sendExportWebhookIfNeeded(for meeting: MeetingRecord) async {
        guard meeting.status == .ready,
              case .webhook(let webhookURL) = Self.resolvedExportDestination() else {
            return
        }

        let payload: [String: Any] = [
            "id": meeting.id.uuidString,
            "title": meeting.title,
            "date": ISO8601DateFormatter().string(from: meeting.date),
            "template": meeting.template.rawValue,
            "durationSeconds": meeting.durationSeconds,
            "recapMarkdown": meeting.recapMarkdown,
            "markdown": fullExportMarkdown(for: meeting),
            "actionItems": meeting.actionItems.map { item in
                [
                    "text": item.text,
                    "completed": item.completed
                ] as [String: Any]
            }
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try? await URLSession.shared.data(for: request)
    }

    func fullExportMarkdown(for meeting: MeetingRecord) -> String {
        let yamlDateFormatter = DateFormatter()
        yamlDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        yamlDateFormatter.dateFormat = "yyyy-MM-dd"

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateStyle = .long
        formatter.timeStyle = .short

        let escapedTitle = meeting.title
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let engineLabel = (meeting.transcriptionEngine ?? "whisper-windows")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let mins = Int((meeting.durationSeconds / 60).rounded())
        var parts: [String] = []
        parts.append("---")
        parts.append("voicetype_id: \(meeting.id.uuidString)")
        parts.append("title: \"\(escapedTitle)\"")
        parts.append("date: \(yamlDateFormatter.string(from: meeting.date))")
        parts.append("source: voicetype")
        parts.append("engine: \"\(engineLabel)\"")
        parts.append("---")
        parts.append("")
        parts.append("# \(meeting.title)")
        parts.append("- **Дата:** \(formatter.string(from: meeting.date))")
        parts.append("- **Длительность:** \(max(1, mins)) мин (\(Int(meeting.durationSeconds.rounded())) сек)")
        parts.append("- **Шаблон:** \(meeting.template.rawValue)")
        if let lang = meeting.languageSummary {
            parts.append("- **Язык речи:** \(lang)")
        }
        if let engine = meeting.transcriptionEngine, !engine.isEmpty {
            parts.append("- **Транскрибация:** \(engine)")
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
                parts.append("- **[\(ts)] [\(speaker)]:** \(seg.text)")
            }
            parts.append("")
        }

        return parts.joined(separator: "\n")
    }

    static func resolvedExportDestination(from rawInput: String? = nil) -> ExportDestination {
        let raw = (rawInput
            ?? UserDefaults.standard.string(forKey: "exportDestination")
            ?? UserDefaults.standard.string(forKey: "obsidianRecapsFolder")
            ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .none }

        let lowered = raw.lowercased()
        if (lowered.hasPrefix("http://") || lowered.hasPrefix("https://")),
           let url = URL(string: raw),
           url.host != nil {
            return .webhook(url)
        }

        let expanded = (raw as NSString).expandingTildeInPath
        return .folder(URL(fileURLWithPath: expanded, isDirectory: true))
    }

    static func makeExportFileName(for meeting: MeetingRecord) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd_HH-mm"
        let prefix = df.string(from: meeting.date)
        let slug = slugifyTitle(meeting.title)
        return "\(prefix)_\(slug)_vt.md"
    }

    private static func slugifyTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics
        var result = ""
        var lastWasDash = false
        for scalar in trimmed.unicodeScalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasDash = false
            } else if !lastWasDash {
                result.append("-")
                lastWasDash = true
            }
        }
        let cleaned = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if cleaned.isEmpty {
            return "vstrecha"
        }
        if cleaned.count > 80 {
            return String(cleaned.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }
        return cleaned
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var loaded = try? decoder.decode([MeetingRecord].self, from: data) else { return }
        var didRecover = false

        for i in loaded.indices {
            if loaded[i].status == .recording || loaded[i].status == .transcribing {
                let dir = baseDirectory.appendingPathComponent(loaded[i].id.uuidString, isDirectory: true)
                let micURL = dir.appendingPathComponent("mic.wav")
                let micRawURL = dir.appendingPathComponent("mic_raw.wav")
                let sysURL = dir.appendingPathComponent("sys.wav")
                let sysRawURL = dir.appendingPathComponent("sys_raw.wav")

                if !FileManager.default.fileExists(atPath: micURL.path),
                   FileManager.default.fileExists(atPath: micRawURL.path) {
                    try? FileManager.default.moveItem(at: micRawURL, to: micURL)
                }
                if !FileManager.default.fileExists(atPath: sysURL.path),
                   FileManager.default.fileExists(atPath: sysRawURL.path) {
                    try? FileManager.default.moveItem(at: sysRawURL, to: sysURL)
                }

                let existingAudioURL: URL? = {
                    if let name = loaded[i].audioFileName {
                        let u = dir.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: u.path) { return u }
                    }
                    if FileManager.default.fileExists(atPath: micURL.path) { return micURL }
                    return nil
                }()

                if let audioURL = existingAudioURL,
                   let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
                   let size = (attrs[.size] as? NSNumber)?.int64Value,
                   size > 32_000 {
                    loaded[i].audioFileName = audioURL.lastPathComponent
                    if FileManager.default.fileExists(atPath: sysURL.path),
                       let sysAttrs = try? FileManager.default.attributesOfItem(atPath: sysURL.path),
                       let sysSize = (sysAttrs[.size] as? NSNumber)?.int64Value,
                       sysSize > 3_200 {
                        loaded[i].sysAudioFileName = sysURL.lastPathComponent
                        loaded[i].stereoParties = true
                    }
                    let estimatedDur = Double(max(0, size - 44)) / 32_000.0
                    if loaded[i].durationSeconds <= 0 {
                        loaded[i].durationSeconds = estimatedDur
                    }
                    loaded[i].status = .queued("Запись восстановлена после перезапуска и ждёт расшифровки")
                } else {
                    loaded[i].status = .error("Запись была прервана при закрытии приложения.")
                }
                didRecover = true
            }
        }

        meetings = loaded
        if didRecover {
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(meetings) else { return }
        try? data.write(to: indexFileURL, options: .atomic)
    }
}
