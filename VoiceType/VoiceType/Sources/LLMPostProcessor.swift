import Foundation

enum LLMProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic = "Anthropic Claude"
    case openai = "OpenAI"
    case gemini = "Google Gemini"
    case openaiCompatible = "Другой (OpenAI-совм.)"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .openaiCompatible: return "Свой API"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-haiku-5-5"
        case .openai: return "gpt-5-mini"
        case .gemini: return "gemini-3.8-flash"
        case .openaiCompatible: return "openai/gpt-4o-mini"
        }
    }

    var recommendedModels: [(id: String, note: String)] {
        switch self {
        case .anthropic:
            return [
                ("claude-haiku-5-5", "Быстрая, для диктовки"),
                ("claude-sonnet-5-5", "Умнее, для сложных текстов"),
                ("claude-haiku-4-5", "Предыдущая Haiku"),
                ("claude-sonnet-4-6", "Предыдущая Sonnet")
            ]
        case .openai:
            return [
                ("gpt-5-mini", "Оптимальная по скорости и цене"),
                ("gpt-5-nano", "Самая быстрая и дешёвая"),
                ("gpt-4.1-mini", "Стабильная мини-модель"),
                ("gpt-4o-mini", "Классическая лёгкая модель")
            ]
        case .gemini:
            return [
                ("gemini-3.8-flash", "Актуальная быстрая Flash"),
                ("gemini-3.6-flash", "Стабильная Gemini 3.6"),
                ("gemini-3-flash-preview", "Preview-версия Gemini 3")
            ]
        case .openaiCompatible:
            return OpenAICompatiblePreset.allCases.map { ($0.suggestedModel, $0.rawValue) }
        }
    }

    var keyPortalURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openaiCompatible: return URL(string: "https://openrouter.ai/keys")!
        }
    }

    var modelsDocsURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://docs.anthropic.com/en/docs/about-claude/models")!
        case .openai: return URL(string: "https://platform.openai.com/docs/models")!
        case .gemini: return URL(string: "https://ai.google.dev/gemini-api/docs/models")!
        case .openaiCompatible: return URL(string: "https://openrouter.ai/models")!
        }
    }

    var keyHelpText: String {
        switch self {
        case .anthropic:
            return "Ключ выпускается в Anthropic Console. Подписка Claude Pro/Max не включает API — нужен отдельный API-баланс."
        case .openai:
            return "Ключ создаётся в OpenAI Platform. Обычная подписка ChatGPT Plus не даёт доступ к API."
        case .gemini:
            return "Ключ бесплатно создаётся в Google AI Studio (не требует подписки Gemini Advanced)."
        case .openaiCompatible:
            return "Ключ берётся в кабинете выбранного сервиса (OpenRouter, Groq, DeepSeek). Для локальных Ollama / LM Studio поле можно оставить пустым."
        }
    }

    var modelsHelpText: String {
        switch self {
        case .anthropic:
            return "Указывайте точный ID модели из документации Anthropic (например, claude-haiku-5-5). Можно выбрать из списка или загрузить по вашему ключу."
        case .openai:
            return "Для быстрой очистки речи лучше подходят мини-модели вроде gpt-5-mini или gpt-4.1-mini."
        case .gemini:
            return "Модели серии Flash и Hydrogen работают быстрее всего. Введите ID вручную или выберите актуальную модель в списке справа от поля."
        case .openaiCompatible:
            return "Имя модели зависит от провайдера: у OpenRouter формат «vendor/model», у Groq и Ollama — короткое имя модели."
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        case .openaiCompatible: return "API-ключ (необязательно для Ollama)"
        }
    }

    var requiresAPIKey: Bool {
        self != .openaiCompatible
    }
}

enum OpenAICompatiblePreset: String, CaseIterable, Identifiable, Sendable {
    case openrouter = "OpenRouter"
    case groq = "Groq"
    case deepseek = "DeepSeek"
    case ollama = "Ollama"
    case lmstudio = "LM Studio"

    var id: String { rawValue }

    var baseURL: String {
        switch self {
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .deepseek: return "https://api.deepseek.com/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .lmstudio: return "http://localhost:1234/v1"
        }
    }

    var suggestedModel: String {
        switch self {
        case .openrouter: return "openai/gpt-4o-mini"
        case .groq: return "llama-3.3-70b-versatile"
        case .deepseek: return "deepseek-chat"
        case .ollama: return "qwen2.5:7b"
        case .lmstudio: return "local-model"
        }
    }
}

struct LLMConfiguration: Equatable, Sendable {
    let provider: LLMProviderKind
    let apiKey: String
    let model: String
    let customBaseURL: String

    var trimmedKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? provider.defaultModel : trimmed
    }

    var normalizedCustomBaseURL: String {
        customBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isConfigured: Bool {
        switch provider {
        case .anthropic, .openai, .gemini:
            return !trimmedKey.isEmpty
        case .openaiCompatible:
            return (try? Self.openAICompatibleEndpoint(from: normalizedCustomBaseURL)) != nil
                && !resolvedModel.isEmpty
        }
    }

    var privacyCaption: String {
        switch provider {
        case .anthropic:
            return "Текст отправляется в Anthropic API. Без ключа текст вставляется как распознан."
        case .openai:
            return "Текст отправляется в OpenAI API. Без ключа текст вставляется как распознан."
        case .gemini:
            return "Текст отправляется в Google Gemini API. Без ключа текст вставляется как распознан."
        case .openaiCompatible:
            if let host = (try? Self.openAICompatibleEndpoint(from: normalizedCustomBaseURL))?.host, !host.isEmpty {
                return "Текст отправляется на \(host) (OpenAI-совместимый API). Без адреса и модели текст вставляется как распознан."
            }
            return "Текст отправляется на выбранный OpenAI-совместимый сервер. Без адреса и модели текст вставляется как распознан."
        }
    }

    static func openAICompatibleEndpoint(from raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LLMError.invalidConfiguration("Не указан адрес OpenAI-совместимого API.")
        }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        let clean = withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
        guard let url = URL(string: clean),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            throw LLMError.invalidConfiguration("Некорректный адрес сервера: \(trimmed)")
        }

        if clean.hasSuffix("/chat/completions") {
            return url
        }
        if clean.hasSuffix("/v1") {
            return url.appendingPathComponent("chat/completions")
        }
        return url.appendingPathComponent("v1/chat/completions")
    }
}

enum LLMError: Error, LocalizedError, Equatable {
    case invalidConfiguration(String)
    case httpError(statusCode: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let msg):
            return msg
        case .httpError(let code, let message):
            return "LLM API вернул ошибку \(code): \(message)"
        case .emptyResponse:
            return "LLM-сервис вернул пустой ответ."
        }
    }
}

struct LLMPostProcessor: Sendable {
    let config: LLMConfiguration
    private let session: URLSession

    init(config: LLMConfiguration, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    func cleanup(
        transcription: GapiTranscription,
        style: CleanupStyle,
        uzbekStyle: UzbekStyle = .tashkent,
        modifiers: CleanupModifiers = .default,
        targetAppName: String? = nil
    ) async throws -> String {
        let text = transcription.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        let resolvedStyle = modifiers.resolvedStyle(base: style, targetAppName: targetAppName)
        guard let basePrompt = resolvedStyle.systemPrompt else { return text }
        guard config.isConfigured else { return text }

        let systemPrompt = ClaudeClient.buildSystemPrompt(
            base: basePrompt,
            transcription: transcription,
            uzbekStyle: uzbekStyle,
            modifiers: modifiers,
            targetAppName: targetAppName
        )
        let userContent = ClaudeClient.buildUserPrompt(transcription: transcription)

        let output = try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userContent,
            maxTokens: 8192,
            timeout: 45
        )
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    func generateMeetingRecap(for meeting: MeetingRecord) async throws -> MeetingRecapOutput {
        let prompts = ClaudeClient.buildMeetingRecapPrompts(for: meeting)
        let fullText = try await complete(
            systemPrompt: prompts.system,
            userPrompt: prompts.user,
            maxTokens: 8192,
            timeout: 90
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !fullText.isEmpty else {
            return LocalRecapBuilder.build(for: meeting)
        }
        return ClaudeClient.parseMeetingRecapResponse(fullText, for: meeting)
    }

    func testConnection() async throws -> Int {
        let started = CFAbsoluteTimeGetCurrent()
        // Thinking-модели (Gemini 3/4, GPT-5, o-series) расходуют лимит и на внутреннее размышление:
        // слишком маленький maxTokens (например, 16) приводит к пустому текстовому ответу.
        let reply = try await complete(
            systemPrompt: "Отвечай предельно кратко.",
            userPrompt: "Ответь одним словом: ОК",
            maxTokens: 1024,
            timeout: 20
        )
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.emptyResponse
        }
        return max(1, Int(((CFAbsoluteTimeGetCurrent() - started) * 1000).rounded()))
    }

    func fetchAvailableModels() async throws -> [String] {
        if config.provider == .gemini {
            var aggregated: [String] = []
            var nextPageToken: String?
            for _ in 0..<4 {
                let request = try buildModelsListRequest(pageToken: nextPageToken)
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw LLMError.emptyResponse
                }
                guard (200..<300).contains(http.statusCode) else {
                    let msg = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                    throw LLMError.httpError(statusCode: http.statusCode, message: msg)
                }
                let page = try parseGeminiModelsPage(data: data)
                aggregated.append(contentsOf: page.ids)
                if let token = page.nextPageToken, !token.isEmpty {
                    nextPageToken = token
                } else {
                    break
                }
            }
            return Self.sortGeminiModels(Self.deduplicatePreservingOrder(aggregated))
        }

        let request = try buildModelsListRequest()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw LLMError.httpError(statusCode: http.statusCode, message: msg)
        }
        return try parseAvailableModels(data: data)
    }

    func buildModelsListRequest(timeout: TimeInterval = 15, pageToken: String? = nil) throws -> URLRequest {
        switch config.provider {
        case .anthropic:
            guard !config.trimmedKey.isEmpty else {
                throw LLMError.invalidConfiguration("Не задан Anthropic API key.")
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models?limit=100")!)
            req.httpMethod = "GET"
            req.timeoutInterval = timeout
            req.setValue(config.trimmedKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            return req

        case .openai:
            guard !config.trimmedKey.isEmpty else {
                throw LLMError.invalidConfiguration("Не задан OpenAI API key.")
            }
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
            req.httpMethod = "GET"
            req.timeoutInterval = timeout
            req.setValue("Bearer \(config.trimmedKey)", forHTTPHeaderField: "Authorization")
            return req

        case .gemini:
            guard !config.trimmedKey.isEmpty else {
                throw LLMError.invalidConfiguration("Не задан Google Gemini API key.")
            }
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            var queryItems = [URLQueryItem(name: "pageSize", value: "100")]
            if let pageToken, !pageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            components.queryItems = queryItems
            var req = URLRequest(url: components.url!)
            req.httpMethod = "GET"
            req.timeoutInterval = timeout
            req.setValue(config.trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            return req

        case .openaiCompatible:
            let chatURL = try LLMConfiguration.openAICompatibleEndpoint(from: config.normalizedCustomBaseURL)
            let modelsURL = chatURL.deletingLastPathComponent().appendingPathComponent("models")
            var req = URLRequest(url: modelsURL)
            req.httpMethod = "GET"
            req.timeoutInterval = timeout
            if !config.trimmedKey.isEmpty {
                req.setValue("Bearer \(config.trimmedKey)", forHTTPHeaderField: "Authorization")
            }
            return req
        }
    }

    func parseAvailableModels(data: Data) throws -> [String] {
        switch config.provider {
        case .gemini:
            let page = try parseGeminiModelsPage(data: data)
            return Self.sortGeminiModels(Self.deduplicatePreservingOrder(page.ids))

        case .anthropic:
            struct AnthropicModelsList: Decodable {
                struct Item: Decodable { let id: String }
                let data: [Item]?
            }
            let decoded = try JSONDecoder().decode(AnthropicModelsList.self, from: data)
            return Self.deduplicatePreservingOrder((decoded.data ?? []).map(\.id).filter { !$0.isEmpty })

        case .openaiCompatible:
            struct CompatibleModelsList: Decodable {
                struct DataItem: Decodable { let id: String }
                struct OllamaItem: Decodable { let name: String }
                let data: [DataItem]?
                let models: [OllamaItem]?
            }
            let decoded = try JSONDecoder().decode(CompatibleModelsList.self, from: data)
            let raw = (decoded.data?.map(\.id) ?? []) + (decoded.models?.map(\.name) ?? [])
            return Self.deduplicatePreservingOrder(raw.filter { !$0.isEmpty })

        case .openai:
            struct OpenAIModelsList: Decodable {
                struct Item: Decodable { let id: String }
                let data: [Item]?
            }
            let decoded = try JSONDecoder().decode(OpenAIModelsList.self, from: data)
            let ids = (decoded.data ?? [])
                .map(\.id)
                .filter { id in
                    let lower = id.lowercased()
                    let isChatPrefix = lower.hasPrefix("gpt-")
                        || lower.hasPrefix("chatgpt-")
                        || lower.hasPrefix("o1")
                        || lower.hasPrefix("o3")
                        || lower.hasPrefix("o4")
                    let isNonText = lower.contains("audio")
                        || lower.contains("realtime")
                        || lower.contains("transcribe")
                        || lower.contains("tts")
                        || lower.contains("image")
                        || lower.contains("search")
                        || lower.contains("instruct")
                        || lower.contains("moderation")
                        || lower.contains("embedding")
                    return isChatPrefix && !isNonText
                }
                .sorted(by: >)
            return Self.deduplicatePreservingOrder(ids)
        }
    }

    private func parseGeminiModelsPage(data: Data) throws -> (ids: [String], nextPageToken: String?) {
        struct GeminiModelsList: Decodable {
            struct Item: Decodable {
                let name: String
                let supportedGenerationMethods: [String]?
            }
            let models: [Item]?
            let nextPageToken: String?
        }
        let decoded = try JSONDecoder().decode(GeminiModelsList.self, from: data)
        let ids = (decoded.models ?? [])
            .filter { item in
                guard let methods = item.supportedGenerationMethods else { return true }
                return methods.contains("generateContent")
            }
            .map { item in
                item.name.hasPrefix("models/") ? String(item.name.dropFirst(7)) : item.name
            }
            .filter { id in
                let lower = id.lowercased()
                guard !lower.isEmpty else { return false }
                let excluded = ["imagen", "veo", "lyria", "embedding", "aqa", "robotics", "bisect", "-tts", "-image", "-audio", "computer-use"]
                return !excluded.contains { lower.contains($0) }
            }
        return (ids, decoded.nextPageToken)
    }

    private static func sortGeminiModels(_ ids: [String]) -> [String] {
        ids.sorted { lhs, rhs in
            let lScore = geminiVersionRank(lhs)
            let rScore = geminiVersionRank(rhs)
            if lScore != rScore { return lScore > rScore }
            return lhs > rhs
        }
    }

    private static func geminiVersionRank(_ id: String) -> Int {
        let lower = id.lowercased()
        let familyBonus = lower.hasPrefix("gemini-") ? 1000 : 0
        let cleaned = lower
            .replacingOccurrences(of: "gemini-", with: "")
            .replacingOccurrences(of: "gemma-", with: "")
        let numberToken = cleaned.split(whereSeparator: { !$0.isNumber && $0 != "." }).first.map(String.init) ?? ""
        let parts = numberToken.split(separator: ".").compactMap { Int($0) }
        let major = parts.first ?? 0
        let minor = parts.count > 1 ? parts[1] : 0
        let previewPenalty = lower.contains("exp") || lower.contains("preview") ? -1 : 0
        return familyBonus + major * 100 + minor * 10 + previewPenalty
    }

    private static func deduplicatePreservingOrder(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    static func isOpenAIReasoningModel(_ model: String) -> Bool {
        let lower = model.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lower.hasPrefix("gpt-5")
            || lower.hasPrefix("o1")
            || lower.hasPrefix("o3")
            || lower.hasPrefix("o4")
            || lower.hasPrefix("codex")
    }

    func complete(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 4096,
        timeout: TimeInterval = 45
    ) async throws -> String {
        let request = try buildRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens,
            timeout: timeout
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw LLMError.httpError(statusCode: http.statusCode, message: msg)
        }
        return try parseResponseText(data: data)
    }

    func buildRequest(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 4096,
        timeout: TimeInterval = 45
    ) throws -> URLRequest {
        switch config.provider {
        case .anthropic:
            guard !config.trimmedKey.isEmpty else {
                throw LLMError.invalidConfiguration("Не задан Anthropic API key.")
            }
            var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            req.httpMethod = "POST"
            req.timeoutInterval = timeout
            req.setValue(config.trimmedKey, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = AnthropicBody(
                model: config.resolvedModel,
                max_tokens: maxTokens,
                system: systemPrompt,
                messages: [.init(role: "user", content: userPrompt)]
            )
            req.httpBody = try JSONEncoder().encode(body)
            return req

        case .openai:
            guard !config.trimmedKey.isEmpty else {
                throw LLMError.invalidConfiguration("Не задан OpenAI API key.")
            }
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            req.httpMethod = "POST"
            req.timeoutInterval = timeout
            req.setValue("Bearer \(config.trimmedKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let model = config.resolvedModel
            let body = OpenAIModernBody(
                model: model,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: userPrompt)
                ],
                temperature: Self.isOpenAIReasoningModel(model) ? nil : 0.2,
                max_completion_tokens: maxTokens
            )
            req.httpBody = try JSONEncoder().encode(body)
            return req

        case .gemini:
            guard !config.trimmedKey.isEmpty else {
                throw LLMError.invalidConfiguration("Не задан Google Gemini API key.")
            }
            let encodedModel = config.resolvedModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.resolvedModel
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
                throw LLMError.invalidConfiguration("Некорректное имя модели Gemini.")
            }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = timeout
            req.setValue(config.trimmedKey, forHTTPHeaderField: "x-goog-api-key")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = GeminiBody(
                systemInstruction: .init(parts: [.init(text: systemPrompt)]),
                contents: [.init(role: "user", parts: [.init(text: userPrompt)])],
                generationConfig: .init(temperature: 0.2, maxOutputTokens: maxTokens)
            )
            req.httpBody = try JSONEncoder().encode(body)
            return req

        case .openaiCompatible:
            let url = try LLMConfiguration.openAICompatibleEndpoint(from: config.normalizedCustomBaseURL)
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = timeout
            if !config.trimmedKey.isEmpty {
                req.setValue("Bearer \(config.trimmedKey)", forHTTPHeaderField: "Authorization")
            }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body = OpenAIBody(
                model: config.resolvedModel,
                messages: [
                    .init(role: "system", content: systemPrompt),
                    .init(role: "user", content: userPrompt)
                ],
                temperature: 0.2,
                max_tokens: maxTokens
            )
            req.httpBody = try JSONEncoder().encode(body)
            return req
        }
    }

    func parseResponseText(data: Data) throws -> String {
        switch config.provider {
        case .anthropic:
            let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            let text = decoded.content
                .filter { $0.type == nil || $0.type == "text" }
                .compactMap(\.text)
                .joined()
            guard !text.isEmpty else { throw LLMError.emptyResponse }
            return text

        case .openai, .openaiCompatible:
            let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            let text = decoded.choices.first?.message?.content ?? ""
            guard !text.isEmpty else { throw LLMError.emptyResponse }
            return text

        case .gemini:
            let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
            let candidate = decoded.candidates?.first
            let parts = candidate?.content?.parts ?? []
            let text = parts
                .filter { $0.thought != true }
                .compactMap(\.text)
                .joined()
            if !text.isEmpty {
                return text
            }
            if let block = decoded.promptFeedback?.blockReason, !block.isEmpty {
                throw LLMError.httpError(statusCode: 200, message: "Запрос заблокирован фильтром безопасности Gemini (\(block)).")
            }
            if candidate?.finishReason == "MAX_TOKENS" {
                throw LLMError.httpError(statusCode: 200, message: "Модель исчерпала лимит токенов на размышление (MAX_TOKENS).")
            }
            throw LLMError.emptyResponse
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        struct GenericErrorEnvelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
            let message: String?
        }
        if let decoded = try? JSONDecoder().decode(GenericErrorEnvelope.self, from: data),
           let msg = decoded.error?.message ?? decoded.message,
           !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return msg
        }
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return String(raw.prefix(240))
        }
        return nil
    }

    // MARK: - Wire Payloads

    private struct AnthropicBody: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct AnthropicResponse: Decodable {
        let content: [Block]
        struct Block: Decodable {
            let type: String?
            let text: String?
        }
    }

    private struct OpenAIModernBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double?
        let max_completion_tokens: Int
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct OpenAIBody: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
        struct Message: Encodable { let role: String; let content: String }
    }

    private struct OpenAIResponse: Decodable {
        let choices: [Choice]
        struct Choice: Decodable {
            let message: Message?
            struct Message: Decodable { let content: String? }
        }
    }

    private struct GeminiBody: Encodable {
        let systemInstruction: Content
        let contents: [Content]
        let generationConfig: GenerationConfig
        struct Content: Encodable {
            let role: String?
            let parts: [Part]
            init(role: String? = nil, parts: [Part]) {
                self.role = role
                self.parts = parts
            }
        }
        struct Part: Encodable { let text: String }
        struct GenerationConfig: Encodable {
            let temperature: Double
            let maxOutputTokens: Int
        }
    }

    private struct GeminiResponse: Decodable {
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
        struct PromptFeedback: Decodable {
            let blockReason: String?
        }
        struct Candidate: Decodable {
            let content: Content?
            let finishReason: String?
            struct Content: Decodable {
                let parts: [Part]?
                struct Part: Decodable {
                    let text: String?
                    let thought: Bool?
                }
            }
        }
    }
}
