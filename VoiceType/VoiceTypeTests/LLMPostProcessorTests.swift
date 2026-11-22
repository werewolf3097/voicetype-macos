import XCTest
@testable import VoiceTypeTests

final class LLMPostProcessorTests: XCTestCase {
    func testOpenAICompatibleEndpointNormalization() throws {
        XCTAssertEqual(
            try LLMConfiguration.openAICompatibleEndpoint(from: "http://localhost:11434/v1").absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
        XCTAssertEqual(
            try LLMConfiguration.openAICompatibleEndpoint(from: "https://api.groq.com/openai/v1/").absoluteString,
            "https://api.groq.com/openai/v1/chat/completions"
        )
        XCTAssertEqual(
            try LLMConfiguration.openAICompatibleEndpoint(from: "openrouter.ai/api/v1/chat/completions").absoluteString,
            "https://openrouter.ai/api/v1/chat/completions"
        )
    }

    func testBuildRequestAndParseForAllFourProviders() throws {
        // 1. Anthropic
        let anthropic = LLMPostProcessor(
            config: LLMConfiguration(provider: .anthropic, apiKey: "sk-ant-test", model: "", customBaseURL: "")
        )
        let antReq = try anthropic.buildRequest(systemPrompt: "sys", userPrompt: "usr")
        XCTAssertEqual(antReq.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(antReq.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        let antParsed = try anthropic.parseResponseText(data: Data(#"{"content":[{"type":"text","text":"Готово"}]}"#.utf8))
        XCTAssertEqual(antParsed, "Готово")

        // 2. OpenAI
        let openai = LLMPostProcessor(
            config: LLMConfiguration(provider: .openai, apiKey: "sk-openai-test", model: "gpt-4o-mini", customBaseURL: "")
        )
        let oaiReq = try openai.buildRequest(systemPrompt: "sys", userPrompt: "usr")
        XCTAssertEqual(oaiReq.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(oaiReq.value(forHTTPHeaderField: "Authorization"), "Bearer sk-openai-test")
        let oaiParsed = try openai.parseResponseText(data: Data(#"{"choices":[{"message":{"content":"Привет!"}}]}"#.utf8))
        XCTAssertEqual(oaiParsed, "Привет!")

        // 3. Google Gemini
        let gemini = LLMPostProcessor(
            config: LLMConfiguration(provider: .gemini, apiKey: "AIza-test", model: "gemini-3.8-flash", customBaseURL: "")
        )
        let gemReq = try gemini.buildRequest(systemPrompt: "sys", userPrompt: "usr")
        XCTAssertEqual(
            gemReq.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent"
        )
        XCTAssertEqual(gemReq.value(forHTTPHeaderField: "x-goog-api-key"), "AIza-test")
        let gemParsed = try gemini.parseResponseText(
            data: Data(#"{"candidates":[{"content":{"parts":[{"text":"Исправлено."}]}}]}"#.utf8)
        )
        XCTAssertEqual(gemParsed, "Исправлено.")

        // 4. OpenAI-compatible (e.g. Ollama without API key)
        let ollama = LLMPostProcessor(
            config: LLMConfiguration(
                provider: .openaiCompatible,
                apiKey: "",
                model: "qwen2.5:7b",
                customBaseURL: "http://localhost:11434/v1"
            )
        )
        XCTAssertTrue(ollama.config.isConfigured)
        let ollReq = try ollama.buildRequest(systemPrompt: "sys", userPrompt: "usr")
        XCTAssertEqual(ollReq.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertNil(ollReq.value(forHTTPHeaderField: "Authorization"))
    }

    func testActiveLLMConfigSwitchesBySelectedProvider() throws {
        let suiteName = "com.farrukh.voicetype.tests.llm.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, persistSecrets: false, syncDockIcon: false)
        store.llmProvider = .gemini
        store.geminiApiKey = "AIza-abc"
        store.geminiModel = "gemini-3.8-flash"

        XCTAssertTrue(store.isLLMConfigured)
        XCTAssertEqual(store.activeLLMConfig.provider, .gemini)
        XCTAssertEqual(store.activeLLMConfig.apiKey, "AIza-abc")
        XCTAssertEqual(store.activeLLMConfig.resolvedModel, "gemini-3.8-flash")
    }

    func testMigratesDeprecatedGemini25FlashToDraftDefault() throws {
        let suiteName = "com.farrukh.voicetype.tests.llm.mig.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("gemini-2.5-flash", forKey: "geminiModel")
        let store = SettingsStore(defaults: defaults, persistSecrets: false, syncDockIcon: false)
        XCTAssertEqual(store.geminiModel, "")
        store.llmProvider = .gemini
        XCTAssertEqual(store.activeLLMConfig.resolvedModel, "gemini-3.8-flash")
    }

    func testGeminiSkipsThoughtPartsAndOpenAIReasoningOmitsTemperature() throws {
        let gemini = LLMPostProcessor(
            config: LLMConfiguration(provider: .gemini, apiKey: "AIza-test", model: "gemini-4-hydrogen", customBaseURL: "")
        )
        let gemJSON = Data("""
        {
          "candidates": [{
            "finishReason": "STOP",
            "content": {
              "parts": [
                {"text": "internal reasoning", "thought": true},
                {"text": "ОК"}
              ]
            }
          }]
        }
        """.utf8)
        XCTAssertEqual(try gemini.parseResponseText(data: gemJSON), "ОК")

        let gpt5 = LLMPostProcessor(
            config: LLMConfiguration(provider: .openai, apiKey: "sk-test", model: "gpt-5-mini", customBaseURL: "")
        )
        let req = try gpt5.buildRequest(systemPrompt: "sys", userPrompt: "usr", maxTokens: 1024)
        let body = try XCTUnwrap(req.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["max_completion_tokens"] as? Int, 1024)
        XCTAssertNil(json["max_tokens"])
        XCTAssertNil(json["temperature"])
    }

    func testParseAvailableModelsForGeminiAnthropicAndOpenAI() throws {
        let gemini = LLMPostProcessor(
            config: LLMConfiguration(provider: .gemini, apiKey: "k", model: "", customBaseURL: "")
        )
        let gemJSON = Data("""
        {
          "models": [
            {"name": "models/gemini-2.5-pro", "supportedGenerationMethods": ["generateContent"]},
            {"name": "models/gemini-4-hydrogen", "supportedGenerationMethods": ["generateContent"]},
            {"name": "models/imagen-4.0", "supportedGenerationMethods": ["generateContent"]},
            {"name": "models/text-embedding-004", "supportedGenerationMethods": ["embedContent"]}
          ]
        }
        """.utf8)
        XCTAssertEqual(try gemini.parseAvailableModels(data: gemJSON), ["gemini-4-hydrogen", "gemini-2.5-pro"])

        let anthropic = LLMPostProcessor(
            config: LLMConfiguration(provider: .anthropic, apiKey: "k", model: "", customBaseURL: "")
        )
        let antJSON = Data(#"{"data":[{"id":"claude-haiku-5-5"},{"id":"claude-sonnet-5-5"}]}"#.utf8)
        XCTAssertEqual(try anthropic.parseAvailableModels(data: antJSON), ["claude-haiku-5-5", "claude-sonnet-5-5"])

        let openai = LLMPostProcessor(
            config: LLMConfiguration(provider: .openai, apiKey: "k", model: "", customBaseURL: "")
        )
        let oaiJSON = Data(#"{"data":[{"id":"gpt-4o-mini"},{"id":"gpt-5-mini"},{"id":"whisper-1"},{"id":"gpt-4o-realtime"}]}"#.utf8)
        XCTAssertEqual(try openai.parseAvailableModels(data: oaiJSON), ["gpt-5-mini", "gpt-4o-mini"])
    }

    func testCleanupStyleLegacyMigrationAndAutoToneModifiers() {
        XCTAssertEqual(CleanupStyle.fromStored("Умная коррекция (Typeless)"), .friendly)
        XCTAssertEqual(CleanupStyle.fromStored("Заметка"), .business)
        XCTAssertEqual(CleanupStyle.fromStored("Сообщение/письмо"), .business)
        XCTAssertEqual(CleanupStyle.fromStored("Без LLM-обработки"), .off)

        var modifiers = CleanupModifiers(
            compactMode: true,
            structuredLists: true,
            preserveTechnicalTerms: true,
            autoToneByApp: true,
            customInstruction: "Пиши без эмодзи"
        )
        XCTAssertEqual(modifiers.resolvedStyle(base: .formal, targetAppName: "Telegram"), .friendly)
        XCTAssertEqual(modifiers.resolvedStyle(base: .friendly, targetAppName: "Mail"), .business)
        XCTAssertEqual(modifiers.resolvedStyle(base: .formal, targetAppName: "Safari"), .formal)
        XCTAssertEqual(modifiers.resolvedStyle(base: .off, targetAppName: "Telegram"), .off)

        modifiers.autoToneByApp = false
        XCTAssertEqual(modifiers.resolvedStyle(base: .formal, targetAppName: "Telegram"), .formal)

        let prompt = ClaudeClient.buildSystemPrompt(
            base: CleanupStyle.business.systemPrompt ?? "",
            transcription: GapiTranscription(
                text: "привет",
                languageCode: "ru",
                languageConfidence: nil,
                languageShare: nil,
                segments: []
            ),
            uzbekStyle: .tashkent,
            modifiers: modifiers,
            targetAppName: "Cursor"
        )
        XCTAssertTrue(prompt.contains("знаки препинания"))
        XCTAssertTrue(prompt.contains("Без воды"))
        XCTAssertTrue(prompt.contains("Списки и абзацы"))
        XCTAssertTrue(prompt.contains("Код и термины"))
        XCTAssertTrue(prompt.contains("Пиши без эмодзи"))
        XCTAssertTrue(prompt.contains("Cursor"))
    }

    func testCloudAudioSTTChunkParsingAndMultiStepRouting() async throws {
        let slice = WhisperWindowsClient.SpeechSlice(
            startFrame: 0,
            endFrame: 160000,
            startSeconds: 120.0,
            durationSeconds: 10.0
        )

        let gemRaw = """
        ```json
        [
          {"start": 0.5, "end": 3.0, "text": "Привет, коллеги."},
          {"start": 3.5, "end": 6.0, "text": "Начинаем созвон."}
        ]
        ```
        """
        let gemSegments = GeminiAudioSTTProvider.parseMeetingChunkResponse(gemRaw, slice: slice, speaker: 2)
        XCTAssertEqual(gemSegments.count, 2)
        XCTAssertEqual(gemSegments[0].speaker, 2)
        XCTAssertEqual(gemSegments[0].start ?? -1, 120.5, accuracy: 0.01)
        XCTAssertEqual(gemSegments[0].end ?? -1, 123.0, accuracy: 0.01)
        XCTAssertEqual(gemSegments[1].text, "Начинаем созвон.")

        let openAI = OpenAIAudioSTTProvider(apiKey: "sk-test", model: "whisper-1")
        let req = try openAI.buildTranscriptionRequest(
            audioData: Data("WAV".utf8),
            filename: "slice.wav",
            mimeType: "audio/wav",
            prompt: "Korzinka",
            includeSegmentTimestamps: true,
            timeout: 30
        )
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

        let oaiJSON = Data("""
        {"text":"Ок","language":"ru","segments":[{"text":"Ок","start":1.0,"end":2.5,"avg_logprob":-0.2,"no_speech_prob":0.1}]}
        """.utf8)
        let verbose = try JSONDecoder().decode(WhisperWindowsClient.VerboseResponse.self, from: oaiJSON)
        let oaiSegments = OpenAIAudioSTTProvider.extractSegments(from: verbose, slice: slice, speaker: 1)
        XCTAssertEqual(oaiSegments.count, 1)
        XCTAssertEqual(oaiSegments[0].speaker, 1)
        XCTAssertEqual(oaiSegments[0].start ?? -1, 121.0, accuracy: 0.01)

        // Multi-step coordinator fallback across 3 steps
        struct StubSTTProvider: TranscriptionProvider {
            let providerName: String
            let outcome: Result<TranscriptionResult, Error>
            func transcribe(fileURL: URL) async throws -> TranscriptionResult {
                try outcome.get()
            }
        }
        let coordinator = DictationTranscriptionCoordinator(providers: [
            StubSTTProvider(providerName: "local", outcome: .failure(HomeServerError.connectTimeout)),
            StubSTTProvider(providerName: "gapi", outcome: .failure(LLMError.httpError(statusCode: 503, message: "busy"))),
            StubSTTProvider(providerName: "gemini", outcome: .success(TranscriptionResult(text: "Готово", engine: "gemini", latencyMs: 120)))
        ])
        let dummyURL = URL(fileURLWithPath: "/tmp/dummy.wav")
        let routed = try await coordinator.transcribe(fileURL: dummyURL)
        XCTAssertEqual(routed.text, "Готово")
        XCTAssertEqual(routed.engine, "gemini")
        XCTAssertEqual(routed.fallbackFrom, "local")

        // Separate dictation and meeting route persistence in SettingsStore
        let suiteName = "com.farrukh.voicetype.tests.stt.routes.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults, persistSecrets: false, syncDockIcon: false)
        store.sttDictationRoute.swapAt(1, 2) // Put Gemini ahead of gapi only for dictation
        XCTAssertEqual(store.sttDictationRoute[1].source, .gemini)
        XCTAssertEqual(store.sttMeetingRoute[1].source, .gapi)

        let reloaded = SettingsStore(defaults: defaults, persistSecrets: false, syncDockIcon: false)
        XCTAssertEqual(reloaded.sttDictationRoute[1].source, .gemini)
        XCTAssertEqual(reloaded.sttMeetingRoute[1].source, .gapi)
    }
}
