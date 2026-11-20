import Foundation

struct TranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double
    var languageCode: String? = nil
    var languageSummary: String? = nil
    var engine: String? = nil
    var latencyMs: Int? = nil

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
        languageCode: String? = nil,
        languageSummary: String? = nil,
        engine: String? = nil,
        latencyMs: Int? = nil
    ) {
        guard !text.isEmpty else { return }
        let record = TranscriptionRecord(
            id: UUID(),
            date: Date(),
            text: text,
            durationSeconds: durationSeconds,
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
