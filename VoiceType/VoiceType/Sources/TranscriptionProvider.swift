import Foundation

struct TranscriptionResult: Equatable, Sendable {
    let text: String
    let languageCode: String?
    let languageSummary: String?
    let engine: String
    let latencyMs: Int
    let audioSeconds: Double?
    let fallbackFrom: String?
    let note: String?

    init(
        text: String,
        languageCode: String? = nil,
        languageSummary: String? = nil,
        engine: String,
        latencyMs: Int,
        audioSeconds: Double? = nil,
        fallbackFrom: String? = nil,
        note: String? = nil
    ) {
        self.text = text
        self.languageCode = languageCode
        self.languageSummary = languageSummary
        self.engine = engine
        self.latencyMs = latencyMs
        self.audioSeconds = audioSeconds
        self.fallbackFrom = fallbackFrom
        self.note = note
    }
}

protocol TranscriptionProvider: Sendable {
    var providerName: String { get }
    func transcribe(fileURL: URL) async throws -> TranscriptionResult
}

/// Обёртка над текущим GapiClient без изменения формата и поведения Gapi.
struct GapiTranscriptionProvider: TranscriptionProvider {
    let token: String
    let applyLocalFixes: Bool

    var providerName: String { "gapi" }

    init(token: String, applyLocalFixes: Bool = true) {
        self.token = token
        self.applyLocalFixes = applyLocalFixes
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        let result = try await GapiClient(token: token).transcribe(
            fileURL: fileURL,
            applyLocalFixes: applyLocalFixes
        )
        let latencyMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
        return TranscriptionResult(
            text: result.text,
            languageCode: result.languageCode,
            languageSummary: result.languageSummary,
            engine: "gapi",
            latencyMs: latencyMs,
            audioSeconds: result.audioSeconds
        )
    }
}

/// Координатор диктовки: последовательно пробует настроенные провайдеры из списка очередности
/// и автоматически переключается на следующий шаг при недоступности или ошибке предыдущего.
struct DictationTranscriptionCoordinator: Sendable {
    let providers: [any TranscriptionProvider]
    let enforceHomeFallbackPolicyForSingleFallback: Bool
    let onFallback: (@Sendable (String) -> Void)?

    init(
        providers: [any TranscriptionProvider],
        onFallback: (@Sendable (String) -> Void)? = nil
    ) {
        self.providers = providers
        self.enforceHomeFallbackPolicyForSingleFallback = false
        self.onFallback = onFallback
    }

    init(
        primary: any TranscriptionProvider,
        fallback: (any TranscriptionProvider)? = nil,
        onFallback: (@Sendable (String) -> Void)? = nil
    ) {
        var list: [any TranscriptionProvider] = [primary]
        if let fallback {
            list.append(fallback)
        }
        self.providers = list
        self.enforceHomeFallbackPolicyForSingleFallback = true
        self.onFallback = onFallback
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        guard !providers.isEmpty else {
            throw HomeServerError.invalidURL("Не настроен ни один сервис распознавания речи.")
        }

        let startedAt = CFAbsoluteTimeGetCurrent()
        var firstFailedProvider: String?

        for (index, provider) in providers.enumerated() {
            try Task.checkCancellation()
            do {
                let result = try await provider.transcribe(fileURL: fileURL)
                let totalMs = max(result.latencyMs, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
                return TranscriptionResult(
                    text: result.text,
                    languageCode: result.languageCode,
                    languageSummary: result.languageSummary,
                    engine: result.engine,
                    latencyMs: totalMs,
                    audioSeconds: result.audioSeconds,
                    fallbackFrom: result.fallbackFrom ?? firstFailedProvider,
                    note: result.note
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw urlError
            } catch {
                let hasNext = index + 1 < providers.count
                if !hasNext {
                    throw error
                }
                if enforceHomeFallbackPolicyForSingleFallback && provider is HomeServerProvider && !HomeServerError.shouldFallbackToGapi(error) {
                    throw error
                }
                if firstFailedProvider == nil {
                    firstFailedProvider = provider.providerName
                }
                let reason = (provider is HomeServerProvider)
                    ? HomeServerError.shortFallbackReason(for: error)
                    : error.localizedDescription
                onFallback?("\(provider.providerName): \(reason)")
            }
        }

        throw HomeServerError.invalidURL("Не удалось распознать речь.")
    }
}
