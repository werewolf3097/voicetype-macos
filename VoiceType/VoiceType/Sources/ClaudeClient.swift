import Foundation

struct ClaudeError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct ClaudeClient {
    let apiKey: String
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let fastModel = "claude-haiku-4-5"
    private let recapModel = "claude-sonnet-4-6"

    private struct RequestBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct ResponseBody: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }

    func cleanup(
        transcription: GapiTranscription,
        style: CleanupStyle,
        uzbekStyle: UzbekStyle = .tashkent
    ) async throws -> String {
        let text = transcription.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        guard let baseSystemPrompt = style.systemPrompt else { return text }

        let systemPrompt = Self.buildSystemPrompt(
            base: baseSystemPrompt,
            transcription: transcription,
            uzbekStyle: uzbekStyle
        )
        let userContent = Self.buildUserPrompt(transcription: transcription)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: fastModel,
            max_tokens: 1024,
            system: systemPrompt,
            messages: [.init(role: "user", content: userContent)]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Claude API вернул ошибку"
            throw ClaudeError(message: message)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let resultText = decoded.content.compactMap(\.text).joined()
        return resultText.isEmpty ? text : resultText
    }

    private static func buildSystemPrompt(
        base: String,
        transcription: GapiTranscription,
        uzbekStyle: UzbekStyle
    ) -> String {
        let hasRussian = transcription.languageCode == "ru"
            || (transcription.languageShare?["ru"] ?? 0) > 0.05
            || transcription.segments.contains(where: { $0.languageCode == "ru" })

        var extra: [String] = [
            "Важная особенность движка распознавания (gapi.uz): акустическая модель всегда выводит буквы только латиницей (узбекская латиница), даже когда человек говорит по-русски."
        ]

        if let lang = transcription.languageCode {
            let shareInfo: String
            if let share = transcription.languageShare, !share.isEmpty {
                let parts = share.sorted { $0.value > $1.value }
                    .map { "\($0.key): \(Int(($0.value * 100).rounded()))%" }
                    .joined(separator: ", ")
                shareInfo = " (доли речи: \(parts))"
            } else {
                shareInfo = ""
            }
            extra.append("Аудио-детектор языка gapi определил основной язык записи: \(lang)\(shareInfo).")
        }

        if hasRussian {
            extra.append("Так как в записи обнаружена русская речь (код `ru`), записанная фонетической латиницей, обязательно восстанови русскую речь в стандартную русскую кириллицу (а узбекские фразы, если речь смешанная uz+ru, оставь на узбекской латинице).")
        }

        if uzbekStyle == .tashkent {
            extra.append("ВАЖНО ДЛЯ УЗБЕКСКОГО ЯЗЫКА: ни в коем случае НЕ переводи узбекскую речь в книжный литературный стиль (Adabiy til). Сохраняй и используй живой ташкентский разговорный диалект (Toshkent shevasi): формы на -vomman, -vosan, -votti, -vommiz, -vossiz, -votgan (например: qivommiz, kevotti, bo'votti, ishlavomman, etvotti, qatta, botta, shotta).")
        }

        return ([base] + extra).joined(separator: "\n\n")
    }

    private static func buildUserPrompt(transcription: GapiTranscription) -> String {
        let labeledSegments = transcription.segments.filter { $0.languageCode != nil && !$0.text.isEmpty }
        if labeledSegments.count > 1 {
            let lines = labeledSegments.map { seg in
                "[\(seg.languageCode ?? "?")] \(seg.text)"
            }.joined(separator: "\n")
            return "\(transcription.text)\n\n(Разбивка по фразам от детектора языка:\n\(lines))"
        }
        return transcription.text
    }

    func generateMeetingRecap(for meeting: MeetingRecord) async throws -> MeetingRecapOutput {
        let headings = meeting.template.sectionHeadings.map { "## \($0)" }.joined(separator: "\n")
        let systemPrompt = """
        Ты — ассистент для подведения итогов встреч в стиле Granola.ai.
        Твоя задача — объединить черновые заметки пользователя со встречи и диаризованный транскрипт разговора в чёткий, содержательный и структурированный Markdown-рекап на русском языке.

        Правила:
        1. Опирайся на заметки пользователя как на главный скелет важности (раскрывай его короткие тезисы фактами, цифрами и деталями из транскрипта).
        2. Используй следующие разделы Markdown (по шаблону «\(meeting.template.rawValue)»):
        \(headings)
        3. В конце ответа после разделителя `---ACTION_ITEMS---` выведи список конкретных задач/шагов (по одной задаче на строку в формате `- [Исполнитель] Текст задачи`, без лишнего текста).
        4. Если в транскрипте встречаются русские слова, записанные латиницей, обязательно переведи их в нормальную русскую кириллицу.
        """

        let transcriptLines = meeting.segments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(400)
            .map { seg in
                let ts = MeetingRecord.formatTimestamp(seg.start)
                let speaker = meeting.displayName(for: seg.speaker)
                return "[\(ts)] \(speaker): \(seg.text)"
            }
            .joined(separator: "\n")

        var userParts: [String] = [
            "Название встречи: \(meeting.title)",
            "Шаблон: \(meeting.template.rawValue)"
        ]
        if let gapiSum = meeting.gapiSummary, !gapiSum.isEmpty {
            userParts.append("Краткая сводка gapi:\n\(gapiSum)")
        }
        if !meeting.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userParts.append("Черновые заметки пользователя во время встречи:\n\(meeting.rawNotes)")
        }
        if !transcriptLines.isEmpty {
            userParts.append("Транскрипт встречи:\n\(transcriptLines)")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: recapModel,
            max_tokens: 2048,
            system: systemPrompt,
            messages: [.init(role: "user", content: userParts.joined(separator: "\n\n"))]
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Claude API вернул ошибку"
            throw ClaudeError(message: message)
        }

        let decoded = try JSONDecoder().decode(ResponseBody.self, from: data)
        let fullText = decoded.content.compactMap(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else {
            return LocalRecapBuilder.build(for: meeting)
        }

        let parts = fullText.components(separatedBy: "---ACTION_ITEMS---")
        let markdown = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        var actionItems: [MeetingActionItem] = []

        if parts.count > 1 {
            let lines = parts[1].components(separatedBy: .newlines)
            for line in lines {
                var cleaned = line.trimmingCharacters(in: .whitespaces)
                if cleaned.hasPrefix("- [ ]") {
                    cleaned = String(cleaned.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                } else if cleaned.hasPrefix("-") || cleaned.hasPrefix("*") {
                    cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                guard !cleaned.isEmpty else { continue }
                actionItems.append(MeetingActionItem(text: cleaned))
            }
        }

        if actionItems.isEmpty {
            actionItems = LocalRecapBuilder.extractActionItems(from: meeting)
        }

        return MeetingRecapOutput(recapMarkdown: markdown, actionItems: actionItems)
    }
}


