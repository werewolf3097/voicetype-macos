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

/// Координатор диктовки: при выключенном переключателе использует только Gapi;
/// при включённом — отправляет на домашний шлюз и автоматически переключается на Gapi,
/// если шлюз недоступен (Tailscale выключен, 502 или таймаут).
struct DictationTranscriptionCoordinator: Sendable {
    let primary: any TranscriptionProvider
    let fallback: (any TranscriptionProvider)?
    let onFallback: (@Sendable (String) -> Void)?

    init(
        primary: any TranscriptionProvider,
        fallback: (any TranscriptionProvider)? = nil,
        onFallback: (@Sendable (String) -> Void)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.onFallback = onFallback
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        let startedAt = CFAbsoluteTimeGetCurrent()
        do {
            let result = try await primary.transcribe(fileURL: fileURL)
            let totalMs = max(result.latencyMs, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
            return TranscriptionResult(
                text: result.text,
                languageCode: result.languageCode,
                languageSummary: result.languageSummary,
                engine: result.engine,
                latencyMs: totalMs,
                audioSeconds: result.audioSeconds,
                fallbackFrom: result.fallbackFrom,
                note: result.note
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard let fallback, HomeServerError.shouldFallbackToGapi(error) else {
                throw error
            }
            let reason = HomeServerError.shortFallbackReason(for: error)
            onFallback?(reason)
            let gapiResult = try await fallback.transcribe(fileURL: fileURL)
            let totalMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
            return TranscriptionResult(
                text: gapiResult.text,
                languageCode: gapiResult.languageCode,
                languageSummary: gapiResult.languageSummary,
                engine: gapiResult.engine,
                latencyMs: totalMs,
                audioSeconds: gapiResult.audioSeconds,
                fallbackFrom: primary.providerName,
                note: gapiResult.note
            )
        }
    }
}
