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
            config: LLMConfiguration(provider: .gemini, apiKey: "AIza-test", model: "gemini-2.5-flash", customBaseURL: "")
        )
        let gemReq = try gemini.buildRequest(systemPrompt: "sys", userPrompt: "usr")
        XCTAssertEqual(
            gemReq.url?.absoluteString,
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
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
        store.geminiModel = "gemini-2.5-flash"

        XCTAssertTrue(store.isLLMConfigured)
        XCTAssertEqual(store.activeLLMConfig.provider, .gemini)
        XCTAssertEqual(store.activeLLMConfig.apiKey, "AIza-abc")
        XCTAssertEqual(store.activeLLMConfig.resolvedModel, "gemini-2.5-flash")
    }
}
