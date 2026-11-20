import Foundation
import XCTest

final class HomeServerProviderTests: XCTestCase {

    // MARK: - 1. Engine Selection & URL Building

    func testTranscribeURLSelectionForAutoAndExplicitEngines() throws {
        let autoConfig = HomeServerConfig(
            baseURLString: "http://100.79.78.37:8790/",
            token: "test-secret",
            engine: .auto,
            language: .auto
        )
        let autoURL = try autoConfig.transcribeURL()
        XCTAssertEqual(autoURL.path, "/v1/transcribe")
        XCTAssertEqual(queryDictionary(autoURL), ["engine": "auto", "lang": "auto", "fallback": "1"])

        let autoUzConfig = HomeServerConfig(
            baseURLString: "100.79.78.37:8790",
            token: "test-secret",
            engine: .auto,
            language: .uz
        )
        let autoUzURL = try autoUzConfig.transcribeURL()
        XCTAssertEqual(autoUzURL.scheme, "http")
        XCTAssertEqual(queryDictionary(autoUzURL), ["engine": "auto", "lang": "uz", "fallback": "1"])

        let parakeetConfig = HomeServerConfig(
            baseURLString: "http://100.79.78.37:8790",
            token: "test-secret",
            engine: .parakeet,
            language: .ru
        )
        XCTAssertEqual(
            queryDictionary(try parakeetConfig.transcribeURL()),
            ["engine": "parakeet", "lang": "ru", "fallback": "0"]
        )

        let whisperWithFallback = HomeServerConfig(
            baseURLString: "http://100.79.78.37:8790",
            token: "test-secret",
            engine: .whisper,
            language: .en,
            allowFallback: true
        )
        XCTAssertEqual(
            queryDictionary(try whisperWithFallback.transcribeURL()),
            ["engine": "whisper", "lang": "en", "fallback": "1"]
        )

        let gapiExplicit = HomeServerConfig(
            baseURLString: "http://100.79.78.37:8790",
            token: "test-secret",
            engine: .gapi,
            language: .uz
        )
        XCTAssertEqual(
            queryDictionary(try gapiExplicit.transcribeURL()),
            ["engine": "gapi", "lang": "uz", "fallback": "0"]
        )
    }

    func testInvalidBaseURLThrows() {
        let empty = HomeServerConfig(baseURLString: "   ", token: "tok")
        XCTAssertThrowsError(try empty.transcribeURL()) { error in
            guard case HomeServerError.invalidURL = error else {
                return XCTFail("Expected invalidURL, got \(error)")
            }
        }
    }

    // MARK: - 2. Response & Error Parsing

    func testParseTranscribeResponse200AllFields() throws {
        let json = """
        {
          "text": "Привет, мир!",
          "engine": "parakeet",
          "language": "ru",
          "seconds": 0.94,
          "audio_seconds": 5.1,
          "fallback_from": null
        }
        """
        let parsed = try HomeServerProvider.parseTranscribeResponse(data: Data(json.utf8), statusCode: 200)
        XCTAssertEqual(parsed.text, "Привет, мир!")
        XCTAssertEqual(parsed.engine, "parakeet")
        XCTAssertEqual(parsed.language, "ru")
        XCTAssertEqual(parsed.seconds, 0.94)
        XCTAssertEqual(parsed.audio_seconds, 5.1)
        XCTAssertNil(parsed.fallback_from)
        XCTAssertNil(parsed.note)
    }

    func testParseTranscribeResponseWithFallbackAndGapiNote() throws {
        let json = """
        {
          "text": "Privet",
          "engine": "gapi",
          "language": "ru",
          "seconds": 1.3,
          "audio_seconds": 4.2,
          "fallback_from": "whisper",
          "note": "gapi writes Russian in Latin"
        }
        """
        let parsed = try HomeServerProvider.parseTranscribeResponse(data: Data(json.utf8), statusCode: 200)
        XCTAssertEqual(parsed.engine, "gapi")
        XCTAssertEqual(parsed.fallback_from, "whisper")
        XCTAssertEqual(parsed.note, "gapi writes Russian in Latin")
    }

    func testParseAllGatewayErrorCodesAndFallbackClassification() {
        let cases: [(Int, String, Bool, (HomeServerError) -> Bool)] = [
            (400, "empty body", false, { if case .badRequest = $0 { return true }; return false }),
            (401, "invalid token", false, { if case .unauthorized = $0 { return true }; return false }),
            (413, "too large", false, { if case .payloadTooLarge = $0 { return true }; return false }),
            (415, "not audio", false, { if case .unsupportedMediaType = $0 { return true }; return false }),
            (422, "too short", false, { if case .audioTooShort = $0 { return true }; return false }),
            (429, "too many concurrent", false, { if case .rateLimited = $0 { return true }; return false }),
            (502, "all engines down", true, { if case .allEnginesUnavailable = $0 { return true }; return false })
        ]

        for (code, message, expectedFallback, matcher) in cases {
            let body = Data("{\"error\":\"\(message)\"}".utf8)
            let mapped = HomeServerProvider.mapHTTPError(statusCode: code, data: body)
            XCTAssertTrue(matcher(mapped), "HTTP \(code) mapped to unexpected error \(mapped)")
            XCTAssertEqual(mapped.isGatewayUnavailable, expectedFallback, "HTTP \(code) fallback mismatch")
            XCTAssertEqual(HomeServerError.shouldFallbackToGapi(mapped), expectedFallback)
        }
    }

    func testParseHealthResponseFlexibleEngineFormats() throws {
        let boolJSON = """
        {"ok": true, "engines": {"parakeet": true, "whisper": true, "gapi": false}}
        """
        let health1 = try HomeServerProvider.parseHealthResponse(data: Data(boolJSON.utf8), statusCode: 200, latencyMs: 42)
        XCTAssertTrue(health1.ok)
        XCTAssertEqual(health1.engines, ["parakeet": true, "whisper": true, "gapi": false])
        XCTAssertEqual(health1.availableEngines, ["parakeet", "whisper"])
        XCTAssertEqual(health1.latencyMs, 42)

        let objJSON = """
        {"ok": true, "engines": {"parakeet": {"ok": true}, "whisper": "ready", "gapi": {"available": false}}}
        """
        let health2 = try HomeServerProvider.parseHealthResponse(data: Data(objJSON.utf8), statusCode: 200, latencyMs: 18)
        XCTAssertEqual(health2.engines, ["parakeet": true, "whisper": true, "gapi": false])
    }

    // MARK: - 3. Audio Compression (Opus/CAF & AAC/M4A)

    func testOpusCAFCompressionProducesCompactValidCAF() throws {
        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 5.0)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let compressor = AudioCompressor()
        let compressed = try compressor.compressForGateway(fileURL: wavURL)

        XCTAssertEqual(compressed.codecName, "opus/caf")
        XCTAssertEqual(compressed.contentType, "audio/x-caf")
        XCTAssertGreaterThan(compressed.inputBytes, 150_000)
        XCTAssertLessThan(compressed.outputBytes, 30_000, "5s Opus 24kbps CAF should stay compact (<30 KB)")
        XCTAssertEqual(String(data: compressed.data.prefix(4), encoding: .ascii), "caff")
    }

    func testAACM4AEncodingEnforcesMinimum48kbps() throws {
        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 3.0)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let compressor = AudioCompressor(aacBitRate: 24_000)
        XCTAssertGreaterThanOrEqual(compressor.aacBitRate, 48_000)
        let data = try compressor.encodeAACM4A(from: wavURL, bitRate: 24_000)
        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(String(data: data.subdata(in: 4..<8), encoding: .ascii), "ftyp")
    }

    // MARK: - 4. Mock Gateway End-to-End & Auth Privacy

    func testMockGatewayTranscribeAutoAndHealthCheck() async throws {
        let secretToken = "unit-test-token-do-not-leak"
        let server = try MockGatewayServer { request in
            guard request.headers["authorization"] == "Bearer \(secretToken)" else {
                return MockHTTPResponse(statusCode: 401, json: ["error": "unauthorized"])
            }
            if request.path == "/v1/health" {
                return MockHTTPResponse(
                    statusCode: 200,
                    json: ["ok": true, "engines": ["parakeet": true, "whisper": true, "gapi": true]]
                )
            }
            if request.path == "/v1/transcribe" {
                let engine = request.queryItems["engine"] ?? "auto"
                let lang = request.queryItems["lang"] ?? "auto"
                let resolvedEngine = (engine == "auto" && lang == "uz") ? "gapi" : (engine == "auto" ? "parakeet" : engine)
                return MockHTTPResponse(
                    statusCode: 200,
                    json: [
                        "text": "Тестовая фраза успешно распознана.",
                        "engine": resolvedEngine,
                        "language": lang == "auto" ? "ru" : lang,
                        "seconds": 0.42,
                        "audio_seconds": 2.0,
                        "fallback_from": NSNull()
                    ]
                )
            }
            return MockHTTPResponse(statusCode: 404, json: ["error": "not found"])
        }
        defer { server.stop() }

        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 2.0)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let provider = HomeServerProvider(
            config: HomeServerConfig(
                baseURLString: server.baseURLString,
                token: secretToken,
                engine: .auto,
                language: .ru
            )
        )

        let health = try await provider.checkHealth()
        XCTAssertTrue(health.ok)
        XCTAssertEqual(health.availableEngines, ["gapi", "parakeet", "whisper"])

        let result = try await provider.transcribe(fileURL: wavURL)
        XCTAssertEqual(result.text, "Тестовая фраза успешно распознана.")
        XCTAssertEqual(result.engine, "parakeet")
        XCTAssertEqual(result.languageCode, "ru")
        XCTAssertEqual(result.languageSummary, "Русский")

        let transcribeReq = try XCTUnwrap(server.recordedRequests.last)
        XCTAssertEqual(transcribeReq.method, "POST")
        XCTAssertEqual(transcribeReq.path, "/v1/transcribe")
        XCTAssertEqual(transcribeReq.queryItems, ["engine": "auto", "lang": "ru", "fallback": "1"])
        XCTAssertEqual(transcribeReq.headers["authorization"], "Bearer \(secretToken)")
        XCTAssertEqual(transcribeReq.headers["content-type"], "audio/x-caf")
        XCTAssertEqual(String(data: transcribeReq.body.prefix(4), encoding: .ascii), "caff")
    }

    func testSlowWhisperResponseSucceedsBeyondConnectTimeout() async throws {
        let server = try MockGatewayServer { _ in
            MockHTTPResponse(
                statusCode: 200,
                json: [
                    "text": "Точная расшифровка через Whisper.",
                    "engine": "whisper",
                    "language": "ru",
                    "seconds": 1.1,
                    "audio_seconds": 2.0,
                    "fallback_from": NSNull()
                ],
                delaySeconds: 1.2
            )
        }
        defer { server.stop() }

        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 1.5)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let provider = HomeServerProvider(
            config: HomeServerConfig(
                baseURLString: server.baseURLString,
                token: "tok",
                engine: .whisper,
                language: .ru,
                connectTimeout: 0.4,
                requestTimeout: 5.0
            )
        )

        let result = try await provider.transcribe(fileURL: wavURL)
        XCTAssertEqual(result.engine, "whisper")
        XCTAssertEqual(result.text, "Точная расшифровка через Whisper.")
    }

    // MARK: - 5. Fallback Coordinator Tests

    func testFallbackOn502CallsGapiWithOriginalWAVAndNotifies() async throws {
        let server = try MockGatewayServer { _ in
            MockHTTPResponse(statusCode: 502, json: ["error": "all engines unavailable"])
        }
        defer { server.stop() }

        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 1.5)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let homeProvider = HomeServerProvider(
            config: HomeServerConfig(baseURLString: server.baseURLString, token: "tok")
        )
        let spyGapi = SpyTranscriptionProvider(
            result: TranscriptionResult(
                text: "Gapi fallback text",
                languageCode: "uz",
                languageSummary: "O‘zbek",
                engine: "gapi",
                latencyMs: 120
            )
        )
        let notifiedReasons = LockedBox<[String]>([])

        let coordinator = DictationTranscriptionCoordinator(
            primary: homeProvider,
            fallback: spyGapi
        ) { reason in
            notifiedReasons.mutate { $0.append(reason) }
        }

        let result = try await coordinator.transcribe(fileURL: wavURL)
        XCTAssertEqual(result.text, "Gapi fallback text")
        XCTAssertEqual(result.engine, "gapi")
        XCTAssertEqual(result.fallbackFrom, "home_server")
        XCTAssertEqual(spyGapi.receivedURLs, [wavURL], "Fallback to Gapi must pass the original WAV URL unchanged")
        XCTAssertEqual(notifiedReasons.value.count, 1)
    }

    func testFallbackOnConnectTimeoutSwitchesToGapiQuickly() async throws {
        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        // 192.0.2.1 (TEST-NET-1) drops SYN packets, simulating Tailscale off / peer unreachable
        let homeProvider = HomeServerProvider(
            config: HomeServerConfig(
                baseURLString: "http://192.0.2.1:8790",
                token: "tok",
                connectTimeout: 0.6,
                requestTimeout: 10.0
            )
        )
        let spyGapi = SpyTranscriptionProvider(
            result: TranscriptionResult(text: "Fallback after timeout", engine: "gapi", latencyMs: 50)
        )
        let notified = LockedBox<Bool>(false)

        let coordinator = DictationTranscriptionCoordinator(
            primary: homeProvider,
            fallback: spyGapi
        ) { _ in
            notified.mutate { $0 = true }
        }

        let started = CFAbsoluteTimeGetCurrent()
        let result = try await coordinator.transcribe(fileURL: wavURL)
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(result.text, "Fallback after timeout")
        XCTAssertEqual(result.engine, "gapi")
        XCTAssertTrue(notified.value)
        XCTAssertLessThan(elapsed, 2.5, "Connect timeout fallback should trigger quickly, not wait for OS TCP timeout")
    }

    func testNoFallbackOn401Or422Or429AndTokenNotLeakedInError() async throws {
        let secret = "super-secret-gateway-token-999"
        for statusCode in [401, 422, 429] {
            let server = try MockGatewayServer { _ in
                MockHTTPResponse(statusCode: statusCode, json: ["error": "client error \(statusCode)"])
            }
            defer { server.stop() }

            let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 1.0)
            defer { try? FileManager.default.removeItem(at: wavURL) }

            let homeProvider = HomeServerProvider(
                config: HomeServerConfig(baseURLString: server.baseURLString, token: secret)
            )
            let spyGapi = SpyTranscriptionProvider(
                result: TranscriptionResult(text: "should not be called", engine: "gapi", latencyMs: 10)
            )
            let notified = LockedBox<Bool>(false)

            let coordinator = DictationTranscriptionCoordinator(
                primary: homeProvider,
                fallback: spyGapi
            ) { _ in
                notified.mutate { $0 = true }
            }

            do {
                _ = try await coordinator.transcribe(fileURL: wavURL)
                XCTFail("Expected error for HTTP \(statusCode)")
            } catch {
                XCTAssertTrue(spyGapi.receivedURLs.isEmpty, "HTTP \(statusCode) must NOT trigger Gapi fallback")
                XCTAssertFalse(notified.value)
                XCTAssertFalse(error.localizedDescription.contains(secret), "Token must never appear in error message")
            }
        }
    }

    // MARK: - 6. HistoryStore Backward-Compatible Migration

    func testHistoryMigrationPreservesLegacyRecordsAndAddsEngineAndLatency() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetype-history-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyURL = tempDir.appendingPathComponent("history.json")
        let legacyID = UUID()
        let legacyJSON = """
        [
          {
            "id": "\(legacyID.uuidString)",
            "date": "2026-10-15T12:00:00Z",
            "text": "Старая запись без engine и latencyMs",
            "durationSeconds": 4.5,
            "languageCode": "uz",
            "languageSummary": "O‘zbek"
          }
        ]
        """
        try Data(legacyJSON.utf8).write(to: historyURL)

        let store = HistoryStore(fileURL: historyURL)
        XCTAssertEqual(store.records.count, 1)
        XCTAssertEqual(store.records[0].id, legacyID)
        XCTAssertEqual(store.records[0].text, "Старая запись без engine и latencyMs")
        XCTAssertNil(store.records[0].engine)
        XCTAssertNil(store.records[0].latencyMs)

        store.add(
            text: "Новая запись через Parakeet",
            durationSeconds: 5.0,
            languageCode: "ru",
            languageSummary: "Русский",
            engine: "parakeet",
            latencyMs: 910
        )

        let reloaded = HistoryStore(fileURL: historyURL)
        XCTAssertEqual(reloaded.records.count, 2)
        XCTAssertEqual(reloaded.records[0].engine, "parakeet")
        XCTAssertEqual(reloaded.records[0].latencyMs, 910)
        XCTAssertEqual(reloaded.records[0].formattedLatency, "910 мс")
        XCTAssertEqual(reloaded.records[1].id, legacyID)
        XCTAssertNil(reloaded.records[1].engine)
    }

    func testGapiPrimaryCoordinatorNeverTriggersFallbackNotification() async throws {
        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 1.0)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let spyGapi = SpyTranscriptionProvider(
            result: TranscriptionResult(
                text: "Salom dunyo",
                languageCode: "uz",
                languageSummary: "O‘zbek",
                engine: "gapi",
                latencyMs: 310
            )
        )
        let notified = LockedBox<Bool>(false)
        let coordinator = DictationTranscriptionCoordinator(primary: spyGapi) { _ in
            notified.mutate { $0 = true }
        }

        let result = try await coordinator.transcribe(fileURL: wavURL)
        XCTAssertEqual(result.engine, "gapi")
        XCTAssertEqual(result.text, "Salom dunyo")
        XCTAssertNil(result.fallbackFrom)
        XCTAssertEqual(spyGapi.receivedURLs, [wavURL])
        XCTAssertFalse(notified.value)
    }

    func testLiveGatewayBenchmark20RequestsIfTokenPresent() async throws {
        guard let token = ProcessInfo.processInfo.environment["VOICE_GATEWAY_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            throw XCTSkip("VOICE_GATEWAY_TOKEN не задан в окружении — живой бенчмарк пропущен.")
        }

        let baseURL = ProcessInfo.processInfo.environment["VOICE_GATEWAY_URL"] ?? HomeServerConfig.defaultURLString
        let wavURL = try TestAudioFactory.makeSampleWAV(durationSeconds: 5.0)
        defer { try? FileManager.default.removeItem(at: wavURL) }

        let provider = HomeServerProvider(
            config: HomeServerConfig(
                baseURLString: baseURL,
                token: token,
                engine: .auto,
                language: .ru
            )
        )

        var latenciesMs: [Int] = []
        for _ in 0..<20 {
            let started = CFAbsoluteTimeGetCurrent()
            let res = try await provider.transcribe(fileURL: wavURL)
            let elapsedMs = Int(((CFAbsoluteTimeGetCurrent() - started) * 1000).rounded())
            latenciesMs.append(elapsedMs)
            XCTAssertFalse(res.engine.isEmpty)
        }

        let sorted = latenciesMs.sorted()
        let p50 = sorted[Int(Double(sorted.count - 1) * 0.50)]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        print("[Benchmark] n=\(sorted.count) p50=\(p50)ms p95=\(p95)ms min=\(sorted.first ?? 0)ms max=\(sorted.last ?? 0)ms")
        XCTAssertLessThanOrEqual(p50, 1500, "p50 latency should be <= 1500ms")
    }

    // MARK: - Helpers

    private func queryDictionary(_ url: URL) -> [String: String] {
        var result: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            result[item.name] = item.value ?? ""
        }
        return result
    }
}

private final class SpyTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    var providerName: String { "gapi" }
    private let result: TranscriptionResult
    private let lock = NSLock()
    private var _receivedURLs: [URL] = []

    var receivedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _receivedURLs
    }

    init(result: TranscriptionResult) {
        self.result = result
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        lock.lock()
        _receivedURLs.append(fileURL)
        lock.unlock()
        return result
    }
}

private final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: T

    var value: T {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    init(_ value: T) {
        self._value = value
    }

    func mutate(_ block: (inout T) -> Void) {
        lock.lock()
        block(&_value)
        lock.unlock()
    }
}
