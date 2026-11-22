import Foundation

enum InsertStatus: String, Codable, Equatable, Sendable {
    case inserted
    case clipboardOnly
    case failed
}

struct TranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double
    var status: InsertStatus
    var targetApp: String?
    var errorMessage: String?
    var style: CleanupStyle?
    var languageCode: String?
    var languageSummary: String?
    var engine: String?
    var latencyMs: Int?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        text: String,
        durationSeconds: Double,
        status: InsertStatus = .inserted,
        targetApp: String? = nil,
        errorMessage: String? = nil,
        style: CleanupStyle? = nil,
        languageCode: String? = nil,
        languageSummary: String? = nil,
        engine: String? = nil,
        latencyMs: Int? = nil
    ) {
        self.id = id
        self.date = date
        self.text = text
        self.durationSeconds = durationSeconds
        self.status = status
        self.targetApp = targetApp
        self.errorMessage = errorMessage
        self.style = style
        self.languageCode = languageCode
        self.languageSummary = languageSummary
        self.engine = engine
        self.latencyMs = latencyMs
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, text, durationSeconds
        case status, targetApp, errorMessage, style
        case languageCode, languageSummary, engine, latencyMs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        self.status = try container.decodeIfPresent(InsertStatus.self, forKey: .status) ?? .inserted
        self.targetApp = try container.decodeIfPresent(String.self, forKey: .targetApp)
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        if let rawStyle = try container.decodeIfPresent(String.self, forKey: .style) {
            self.style = CleanupStyle.fromStored(rawStyle)
        } else {
            self.style = nil
        }
        self.languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        self.languageSummary = try container.decodeIfPresent(String.self, forKey: .languageSummary)
        self.engine = try container.decodeIfPresent(String.self, forKey: .engine)
        self.latencyMs = try container.decodeIfPresent(Int.self, forKey: .latencyMs)
    }

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    var formattedLatency: String? {
        guard let latencyMs, latencyMs >= 0 else { return nil }
        if latencyMs < 1000 {
            return "\(latencyMs) мс"
        }
        return String(format: "%.1f с", Double(latencyMs) / 1000.0)
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []

    private let maxRecords = 200
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("VoiceType", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("history.json")
        }
        load()
    }

    func add(
        text: String,
        durationSeconds: Double,
        status: InsertStatus = .inserted,
        targetApp: String? = nil,
        errorMessage: String? = nil,
        style: CleanupStyle? = nil,
        languageCode: String? = nil,
        languageSummary: String? = nil,
        engine: String? = nil,
        latencyMs: Int? = nil
    ) {
        if text.isEmpty && status != .failed {
            return
        }
        let record = TranscriptionRecord(
            id: UUID(),
            date: Date(),
            text: text,
            durationSeconds: durationSeconds,
            status: status,
            targetApp: targetApp,
            errorMessage: errorMessage,
            style: style,
            languageCode: languageCode,
            languageSummary: languageSummary,
            engine: engine,
            latencyMs: latencyMs
        )
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
        save()
    }

    func update(id: UUID, transform: (inout TranscriptionRecord) -> Void) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        var updated = records[idx]
        transform(&updated)
        records[idx] = updated
        save()
    }

    func clear() {
        records.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([TranscriptionRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
