import Foundation

struct DictionaryEntry: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var heard: String
    var written: String

    init(id: UUID = UUID(), heard: String, written: String) {
        self.id = id
        self.heard = heard
        self.written = written
    }
}

final class DictionaryStore: ObservableObject {
    @Published private(set) var entries: [DictionaryEntry] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("VoiceType", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("dictionary.json")
        }
        load()
    }

    func add(heard: String, written: String) {
        let cleanHeard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWritten = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHeard.isEmpty, !cleanWritten.isEmpty else { return }

        if let idx = entries.firstIndex(where: { $0.heard.caseInsensitiveCompare(cleanHeard) == .orderedSame }) {
            entries[idx].heard = cleanHeard
            entries[idx].written = cleanWritten
        } else {
            entries.insert(DictionaryEntry(heard: cleanHeard, written: cleanWritten), at: 0)
        }
        save()
    }

    func update(id: UUID, heard: String, written: String) {
        let cleanHeard = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanWritten = written.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanHeard.isEmpty, !cleanWritten.isEmpty else { return }
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].heard = cleanHeard
        entries[idx].written = cleanWritten
        save()
    }

    func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    func apply(to text: String) -> String {
        Self.apply(entries: entries, to: text)
    }

    static func apply(entries: [DictionaryEntry], to text: String) -> String {
        guard !text.isEmpty, !entries.isEmpty else { return text }

        let sorted = entries
            .map { (heard: $0.heard.trimmingCharacters(in: .whitespacesAndNewlines),
                    written: $0.written.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.heard.isEmpty && !$0.written.isEmpty }
            .sorted { $0.heard.count > $1.heard.count }

        var output = text
        for entry in sorted {
            let escaped = NSRegularExpression.escapedPattern(for: entry.heard)
            let pattern = "(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(output.startIndex..<output.endIndex, in: output)
            let template = NSRegularExpression.escapedTemplate(for: entry.written)
            output = regex.stringByReplacingMatches(in: output, options: [], range: range, withTemplate: template)
        }
        return output
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        entries = (try? JSONDecoder().decode([DictionaryEntry].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
