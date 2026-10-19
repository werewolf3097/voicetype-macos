import Foundation

struct TranscriptionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let durationSeconds: Double
    var languageCode: String? = nil
    var languageSummary: String? = nil

    var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

final class HistoryStore: ObservableObject {
    @Published private(set) var records: [TranscriptionRecord] = []

    private let maxRecords = 200
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceType", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(text: String, durationSeconds: Double, languageCode: String? = nil, languageSummary: String? = nil) {
        guard !text.isEmpty else { return }
        let record = TranscriptionRecord(
            id: UUID(),
            date: Date(),
            text: text,
            durationSeconds: durationSeconds,
            languageCode: languageCode,
            languageSummary: languageSummary
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
        var loaded = (try? decoder.decode([TranscriptionRecord].self, from: data)) ?? []
        var didMigrate = false
        for i in loaded.indices {
            if loaded[i].languageCode == "ru",
               loaded[i].text.range(of: "[А-Яа-яЁё]", options: .regularExpression) == nil {
                loaded[i] = TranscriptionRecord(
                    id: loaded[i].id,
                    date: loaded[i].date,
                    text: RussianTransliterator.convertSentence(loaded[i].text),
                    durationSeconds: loaded[i].durationSeconds,
                    languageCode: loaded[i].languageCode,
                    languageSummary: loaded[i].languageSummary
                )
                didMigrate = true
            }
        }
        records = loaded
        if didMigrate {
            save()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
