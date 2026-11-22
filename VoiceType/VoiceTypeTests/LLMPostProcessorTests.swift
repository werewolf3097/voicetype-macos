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

    func testMigratesDeprecatedGemini25FlashTo38Flash() throws {
        let suiteName = "com.farrukh.voicetype.tests.llm.mig.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("gemini-2.5-flash", forKey: "geminiModel")
        let store = SettingsStore(defaults: defaults, persistSecrets: false, syncDockIcon: false)
        XCTAssertEqual(store.geminiModel, "gemini-3.8-flash")
    }

    func testParseAvailableModelsForGeminiAnthropicAndOpenAI() throws {
        let gemini = LLMPostProcessor(
            config: LLMConfiguration(provider: .gemini, apiKey: "k", model: "", customBaseURL: "")
        )
        let gemJSON = Data("""
        {
          "models": [
            {"name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["generateContent"]},
            {"name": "models/text-embedding-004", "supportedGenerationMethods": ["embedContent"]}
          ]
        }
        """.utf8)
        XCTAssertEqual(try gemini.parseAvailableModels(data: gemJSON), ["gemini-3.8-flash"])

        let anthropic = LLMPostProcessor(
            config: LLMConfiguration(provider: .anthropic, apiKey: "k", model: "", customBaseURL: "")
        )
        let antJSON = Data(#"{"data":[{"id":"claude-haiku-5-5"},{"id":"claude-sonnet-5-5"}]}"#.utf8)
        XCTAssertEqual(try anthropic.parseAvailableModels(data: antJSON), ["claude-haiku-5-5", "claude-sonnet-5-5"])

        let openai = LLMPostProcessor(
            config: LLMConfiguration(provider: .openai, apiKey: "k", model: "", customBaseURL: "")
        )
        let oaiJSON = Data(#"{"data":[{"id":"gpt-5-mini"},{"id":"whisper-1"},{"id":"gpt-4o-realtime"}]}"#.utf8)
        XCTAssertEqual(try openai.parseAvailableModels(data: oaiJSON), ["gpt-5-mini"])
    }
}
