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
            max_tokens: 4096,
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

    static func buildSystemPrompt(
        base: String,
        transcription: GapiTranscription,
        uzbekStyle: UzbekStyle,
        modifiers: CleanupModifiers = .default,
        targetAppName: String? = nil
    ) -> String {
        let hasRussian = transcription.languageCode == "ru"
            || (transcription.languageShare?["ru"] ?? 0) > 0.05
            || transcription.segments.contains(where: { $0.languageCode == "ru" })
        let hasUzbek = transcription.languageCode == "uz"
            || transcription.languageCode == "uz-khorezm"
            || (transcription.languageShare?["uz"] ?? 0) > 0.05
            || transcription.segments.contains { $0.languageCode == "uz" || $0.languageCode == "uz-khorezm" }

        var extra: [String] = [
            "Текст уже в письменной форме: русский записан кириллицей, узбекский — латиницей. Не транслитерируй заново и не переводи без явной инструкции. Не сокращай и не выкидывай факты, имена и названия. Аббревиатуры пиши целиком, как принято."
        ]

        if modifiers.compactMode {
            extra.append("Надстройка «Без воды»: убери повторы и лишние вводные фразы, передай смысл максимально компактно, сохраняя выбранный тон.")
        }

        if modifiers.structuredLists {
            extra.append("Надстройка «Списки и абзацы»: если в речи перечисляются пункты, шаги или задачи, оформи их аккуратным маркированным списком или логичными абзацами.")
        }

        if modifiers.preserveTechnicalTerms {
            extra.append("Надстройка «Код и термины»: не переводи и не искажай технические термины, названия сервисов, URL, пути к файлам, CLI-команды и идентификаторы вроде camelCase или snake_case.")
        }

        let trimmedCustom = modifiers.customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            extra.append("Дополнительная инструкция пользователя: \(trimmedCustom)")
        }

        if let targetAppName, !targetAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            extra.append("Контекст: текст будет вставлен в приложение «\(targetAppName)».")
        }

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
            extra.append("Язык записи: \(lang)\(shareInfo).")
        }

        if hasRussian && hasUzbek {
            extra.append("Смешанная речь: русские фразы оставь кириллицей, узбекские — латиницей.")
        }

        if hasUzbek && uzbekStyle == .tashkent {
            extra.append("Узбекские фразы оставь живым ташкентским диалектом (qivommiz, kevotti, qatta), не переводи их в книжный узбекский.")
        }

        return ([base] + extra).joined(separator: "\n\n")
    }

    static func buildUserPrompt(transcription: GapiTranscription) -> String {
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
        let prompts = Self.buildMeetingRecapPrompts(for: meeting)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = RequestBody(
            model: recapModel,
            max_tokens: 4096,
            system: prompts.system,
            messages: [.init(role: "user", content: prompts.user)]
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

        return Self.parseMeetingRecapResponse(fullText, for: meeting)
    }

    static func buildMeetingRecapPrompts(for meeting: MeetingRecord) -> (system: String, user: String) {
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
            .prefix(1500)
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
        return (system: systemPrompt, user: userParts.joined(separator: "\n\n"))
    }

    static func parseMeetingRecapResponse(_ fullText: String, for meeting: MeetingRecord) -> MeetingRecapOutput {
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


