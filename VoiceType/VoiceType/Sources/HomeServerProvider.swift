import Foundation
import os

enum HomeServerEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "auto"
    case parakeet = "parakeet"
    case whisper = "whisper"
    case gapi = "gapi"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Авто (рекомендуется)"
        case .parakeet: return "Быстро — Parakeet"
        case .whisper: return "Точно — Whisper"
        case .gapi: return "Узбекский — Gapi"
        }
    }

    var defaultAllowFallback: Bool {
        self == .auto
    }
}

enum HomeServerLanguage: String, CaseIterable, Identifiable, Codable, Sendable {
    case auto = "auto"
    case ru = "ru"
    case uz = "uz"
    case en = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Авто"
        case .ru: return "Русский"
        case .uz: return "Узбекский"
        case .en: return "Английский"
        }
    }
}

struct HomeServerConfig: Equatable, Sendable {
    static let defaultURLString = "http://100.79.78.37:8790"
    static let defaultConnectTimeout: TimeInterval = 3.0
    static let defaultRequestTimeout: TimeInterval = 45.0

    var baseURLString: String
    var token: String
    var engine: HomeServerEngine
    var language: HomeServerLanguage
    var allowFallback: Bool
    var connectTimeout: TimeInterval
    var requestTimeout: TimeInterval

    init(
        baseURLString: String = HomeServerConfig.defaultURLString,
        token: String,
        engine: HomeServerEngine = .auto,
        language: HomeServerLanguage = .auto,
        allowFallback: Bool? = nil,
        connectTimeout: TimeInterval = HomeServerConfig.defaultConnectTimeout,
        requestTimeout: TimeInterval = HomeServerConfig.defaultRequestTimeout
    ) {
        self.baseURLString = baseURLString
        self.token = token
        self.engine = engine
        self.language = language
        self.allowFallback = allowFallback ?? engine.defaultAllowFallback
        self.connectTimeout = connectTimeout
        self.requestTimeout = requestTimeout
    }

    func normalizedBaseURL() throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw HomeServerError.invalidURL("Не указан адрес домашнего сервера")
        }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        let cleaned = withScheme.hasSuffix("/") ? String(withScheme.dropLast()) : withScheme
        guard let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              let host = url.host,
              !host.isEmpty else {
            throw HomeServerError.invalidURL("Некорректный адрес домашнего сервера: \(trimmed)")
        }
        return url
    }

    func transcribeURL() throws -> URL {
        let base = try normalizedBaseURL()
        guard var components = URLComponents(url: base.appendingPathComponent("v1/transcribe"), resolvingAgainstBaseURL: false) else {
            throw HomeServerError.invalidURL("Не удалось собрать URL для /v1/transcribe")
        }
        components.queryItems = [
            URLQueryItem(name: "engine", value: engine.rawValue),
            URLQueryItem(name: "lang", value: language.rawValue),
            URLQueryItem(name: "fallback", value: allowFallback ? "1" : "0")
        ]
        guard let url = components.url else {
            throw HomeServerError.invalidURL("Не удалось собрать URL запроса")
        }
        return url
    }

    func healthURL() throws -> URL {
        try normalizedBaseURL().appendingPathComponent("v1/health")
    }
}

enum HomeServerError: Error, LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case missingToken
    case encodingFailed(String)
    case connectTimeout
    case requestTimeout
    case networkUnavailable(String)
    case badRequest(String)
    case unauthorized(String)
    case payloadTooLarge(String)
    case unsupportedMediaType(String)
    case audioTooShort(String)
    case rateLimited(String)
    case allEnginesUnavailable(String)
    case httpError(statusCode: Int, message: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let msg):
            return msg
        case .missingToken:
            return "Не задан токен домашнего сервера. Откройте настройки."
        case .encodingFailed(let msg):
            return "Не удалось сжать аудио для шлюза: \(msg)"
        case .connectTimeout:
            return "Домашний сервер не ответил за 3 с (проверьте Tailscale)."
        case .requestTimeout:
            return "Превышено время ожидания ответа домашнего сервера."
        case .networkUnavailable(let msg):
            return "Нет связи с домашним сервером: \(msg)"
        case .badRequest(let msg):
            return "Ошибка параметров запроса (400): \(msg)"
        case .unauthorized(let msg):
            return "Ошибка авторизации на домашнем сервере (401): \(msg)"
        case .payloadTooLarge(let msg):
            return "Аудиофайл слишком большой (>50 МБ, 413): \(msg)"
        case .unsupportedMediaType(let msg):
            return "Неподдерживаемый формат аудио (415): \(msg)"
        case .audioTooShort(let msg):
            return "Запись слишком короткая (<0,2 с, 422): \(msg)"
        case .rateLimited(let msg):
            return "Слишком много одновременных запросов к серверу (429): \(msg)"
        case .allEnginesUnavailable(let msg):
            return "Все движки домашнего сервера недоступны (502): \(msg)"
        case .httpError(let statusCode, let msg):
            return "Домашний сервер вернул HTTP \(statusCode): \(msg)"
        case .invalidResponse(let msg):
            return "Некорректный ответ домашнего сервера: \(msg)"
        }
    }

    /// True когда проблема в доступности самого шлюза/сети и нужно переключиться на Gapi.
    var isGatewayUnavailable: Bool {
        switch self {
        case .connectTimeout, .requestTimeout, .networkUnavailable, .allEnginesUnavailable:
            return true
        case .invalidURL, .missingToken, .encodingFailed,
             .badRequest, .unauthorized, .payloadTooLarge,
             .unsupportedMediaType, .audioTooShort, .rateLimited,
             .httpError, .invalidResponse:
            return false
        }
    }

    static func shouldFallbackToGapi(_ error: Error) -> Bool {
        if let homeError = error as? HomeServerError {
            return homeError.isGatewayUnavailable
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        return false
    }

    static func shortFallbackReason(for error: Error) -> String {
        if let homeError = error as? HomeServerError {
            switch homeError {
            case .connectTimeout:
                return "таймаут подключения (3 с)"
            case .requestTimeout:
                return "таймаут ответа"
            case .allEnginesUnavailable:
                return "все движки недоступны (502)"
            case .networkUnavailable:
                return "нет соединения (Tailscale)"
            default:
                return "шлюз недоступен"
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "таймаут подключения"
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet:
                return "нет соединения (Tailscale)"
            default:
                return "ошибка сети"
            }
        }
        return "шлюз недоступен"
    }
}

struct HomeServerTranscribeResponse: Decodable, Equatable, Sendable {
    let text: String
    let engine: String
    let language: String?
    let seconds: Double?
    let audio_seconds: Double?
    let fallback_from: String?
    let note: String?
}

struct HomeServerHealth: Equatable, Sendable {
    let ok: Bool
    let engines: [String: Bool]
    let latencyMs: Int

    var availableEngines: [String] {
        engines.filter { $0.value }.map(\.key).sorted()
    }

    var unavailableEngines: [String] {
        engines.filter { !$0.value }.map(\.key).sorted()
    }
}

private struct HomeServerErrorBody: Decodable {
    let error: String?
}

private struct RawHealthResponse: Decodable {
    let ok: Bool
    let engines: [String: RawEngineStatus]?

    enum RawEngineStatus: Decodable {
        case bool(Bool)
        case string(String)
        case object(ok: Bool?)

        var isAvailable: Bool {
            switch self {
            case .bool(let flag):
                return flag
            case .string(let value):
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized == "ok" || normalized == "ready" || normalized == "up" || normalized == "available" || normalized == "true"
            case .object(let ok):
                return ok ?? false
            }
        }

        private struct ObjectStatus: Decodable {
            let ok: Bool?
            let available: Bool?
            let ready: Bool?
            let status: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .bool(flag)
                return
            }
            if let str = try? container.decode(String.self) {
                self = .string(str)
                return
            }
            if let obj = try? container.decode(ObjectStatus.self) {
                if let ok = obj.ok ?? obj.available ?? obj.ready {
                    self = .object(ok: ok)
                } else if let status = obj.status {
                    self = .string(status)
                } else {
                    self = .object(ok: false)
                }
                return
            }
            self = .bool(false)
        }
    }
}

/// Управляет пулом URLSession с HTTP Keep-Alive и точным connect-таймаутом для каждой задачи.
final class HomeServerTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = HomeServerTransport()

    private struct TaskState {
        var connected = false
        var connectTimedOut = false
        var timer: DispatchSourceTimer?
        weak var task: URLSessionTask?
    }

    private let lock = NSLock()
    private var states: [Int: TaskState] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    func upload(
        request: URLRequest,
        body: Data,
        connectTimeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        let taskHolder = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.uploadTask(with: request, from: body) { [weak self] data, response, error in
                    let timedOut = self?.finishTask(id: taskHolder.taskID) ?? false
                    if timedOut {
                        continuation.resume(throwing: HomeServerError.connectTimeout)
                        return
                    }
                    if let error {
                        continuation.resume(throwing: Self.mapTransportError(error))
                        return
                    }
                    guard let http = response as? HTTPURLResponse, let data else {
                        continuation.resume(throwing: HomeServerError.invalidResponse("Пустой ответ от сервера"))
                        return
                    }
                    continuation.resume(returning: (data, http))
                }
                taskHolder.set(task: task)
                armConnectTimer(for: task, timeout: connectTimeout)
                task.resume()
            }
        } onCancel: {
            taskHolder.cancel()
        }
    }

    func get(
        request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse) {
        var req = request
        req.timeoutInterval = timeout
        let taskHolder = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: req) { [weak self] data, response, error in
                    let timedOut = self?.finishTask(id: taskHolder.taskID) ?? false
                    if timedOut {
                        continuation.resume(throwing: HomeServerError.connectTimeout)
                        return
                    }
                    if let error {
                        continuation.resume(throwing: Self.mapTransportError(error))
                        return
                    }
                    guard let http = response as? HTTPURLResponse, let data else {
                        continuation.resume(throwing: HomeServerError.invalidResponse("Пустой ответ от сервера"))
                        return
                    }
                    continuation.resume(returning: (data, http))
                }
                taskHolder.set(task: task)
                armConnectTimer(for: task, timeout: timeout)
                task.resume()
            }
        } onCancel: {
            taskHolder.cancel()
        }
    }

    private func armConnectTimer(for task: URLSessionTask, timeout: TimeInterval) {
        let taskID = task.taskIdentifier
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        timer.schedule(deadline: .now() + max(0.05, timeout))
        timer.setEventHandler { [weak self] in
            self?.handleConnectTimeout(taskID: taskID)
        }
        lock.lock()
        states[taskID] = TaskState(connected: false, connectTimedOut: false, timer: timer, task: task)
        lock.unlock()
        timer.resume()
    }

    private func markConnected(taskID: Int) {
        lock.lock()
        if var state = states[taskID] {
            state.connected = true
            state.timer?.cancel()
            state.timer = nil
            states[taskID] = state
        }
        lock.unlock()
    }

    private func handleConnectTimeout(taskID: Int) {
        lock.lock()
        guard var state = states[taskID] else {
            lock.unlock()
            return
        }
        let shouldCancel = !state.connected
        if shouldCancel {
            state.connectTimedOut = true
        }
        let target = state.task
        state.timer?.cancel()
        state.timer = nil
        states[taskID] = state
        lock.unlock()
        if shouldCancel {
            target?.cancel()
        }
    }

    private func finishTask(id: Int) -> Bool {
        lock.lock()
        let state = states.removeValue(forKey: id)
        lock.unlock()
        state?.timer?.cancel()
        return state?.connectTimedOut ?? false
    }

    private static func mapTransportError(_ error: Error) -> Error {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return CancellationError()
            case .timedOut:
                return HomeServerError.requestTimeout
            default:
                return HomeServerError.networkUnavailable(urlError.localizedDescription)
            }
        }
        return HomeServerError.networkUnavailable(error.localizedDescription)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        markConnected(taskID: task.taskIdentifier)
    }

    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionTask?
        private var cancelled = false
        private(set) var taskID: Int = -1

        func set(task: URLSessionTask) {
            lock.lock()
            self.task = task
            self.taskID = task.taskIdentifier
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel {
                task.cancel()
            }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let current = task
            lock.unlock()
            current?.cancel()
        }
    }
}

/// Провайдер транскрибации через домашний шлюз (Parakeet / Whisper / Gapi внутри Tailscale).
/// Токен передаётся только в заголовке Authorization и никогда не логируется;
/// текст расшифровки также никогда не попадает в логи.
struct HomeServerProvider: TranscriptionProvider {
    private static let logger = Logger(subsystem: "com.farrukh.voicetype", category: "HomeServerProvider")

    let config: HomeServerConfig
    let compressor: any AudioCompressing
    let transport: HomeServerTransport

    var providerName: String { "home_server" }

    init(
        config: HomeServerConfig,
        compressor: any AudioCompressing = AudioCompressor(),
        transport: HomeServerTransport = .shared
    ) {
        self.config = config
        self.compressor = compressor
        self.transport = transport
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        let token = config.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw HomeServerError.missingToken
        }

        let endpointURL = try config.transcribeURL()
        let startedAt = CFAbsoluteTimeGetCurrent()

        let compressed: CompressedAudio
        do {
            compressed = try await Task.detached(priority: .userInitiated) {
                try compressor.compressForGateway(fileURL: fileURL)
            }.value
        } catch let error as HomeServerError {
            throw error
        } catch {
            throw HomeServerError.encodingFailed(error.localizedDescription)
        }

        try Task.checkCancellation()

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = config.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(compressed.contentType, forHTTPHeaderField: "Content-Type")

        let (data, http) = try await transport.upload(
            request: request,
            body: compressed.data,
            connectTimeout: config.connectTimeout
        )

        let totalMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
        let parsed = try Self.parseTranscribeResponse(data: data, statusCode: http.statusCode)

        let resolvedLangSummary = parsed.language.flatMap { code in
            code.isEmpty ? nil : GapiTranscription.displayName(for: code)
        }

        Self.logger.info(
            "Gateway transcribe ok: engine=\(parsed.engine, privacy: .public) lang=\(parsed.language ?? "none", privacy: .public) fallbackFrom=\(parsed.fallback_from ?? "none", privacy: .public) payloadBytes=\(compressed.outputBytes, privacy: .public) encodeMs=\(compressed.encodingMs, privacy: .public) totalMs=\(totalMs, privacy: .public)"
        )

        return TranscriptionResult(
            text: parsed.text.trimmingCharacters(in: .whitespacesAndNewlines),
            languageCode: parsed.language,
            languageSummary: resolvedLangSummary,
            engine: parsed.engine,
            latencyMs: totalMs,
            audioSeconds: parsed.audio_seconds,
            fallbackFrom: parsed.fallback_from,
            note: parsed.note
        )
    }

    func checkHealth() async throws -> HomeServerHealth {
        let token = config.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw HomeServerError.missingToken
        }

        let healthURL = try config.healthURL()
        let startedAt = CFAbsoluteTimeGetCurrent()

        var request = URLRequest(url: healthURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, http) = try await transport.get(
            request: request,
            timeout: config.connectTimeout
        )
        let latencyMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
        let health = try Self.parseHealthResponse(data: data, statusCode: http.statusCode, latencyMs: latencyMs)

        Self.logger.info(
            "Gateway health: ok=\(health.ok, privacy: .public) latencyMs=\(latencyMs, privacy: .public)"
        )
        return health
    }

    // MARK: - Pure Response & Error Parsers (unit-tested)

    static func parseTranscribeResponse(data: Data, statusCode: Int) throws -> HomeServerTranscribeResponse {
        guard statusCode == 200 else {
            throw mapHTTPError(statusCode: statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(HomeServerTranscribeResponse.self, from: data)
        } catch {
            throw HomeServerError.invalidResponse("Не удалось разобрать JSON ответа")
        }
    }

    static func parseHealthResponse(data: Data, statusCode: Int, latencyMs: Int) throws -> HomeServerHealth {
        guard statusCode == 200 else {
            throw mapHTTPError(statusCode: statusCode, data: data)
        }
        do {
            let raw = try JSONDecoder().decode(RawHealthResponse.self, from: data)
            let mapped = (raw.engines ?? [:]).mapValues { $0.isAvailable }
            return HomeServerHealth(ok: raw.ok, engines: mapped, latencyMs: latencyMs)
        } catch {
            throw HomeServerError.invalidResponse("Не удалось разобрать JSON /v1/health")
        }
    }

    static func mapHTTPError(statusCode: Int, data: Data) -> HomeServerError {
        let message = extractErrorMessage(from: data) ?? "HTTP \(statusCode)"
        switch statusCode {
        case 400: return .badRequest(message)
        case 401: return .unauthorized(message)
        case 413: return .payloadTooLarge(message)
        case 415: return .unsupportedMediaType(message)
        case 422: return .audioTooShort(message)
        case 429: return .rateLimited(message)
        case 502: return .allEnginesUnavailable(message)
        default: return .httpError(statusCode: statusCode, message: message)
        }
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(HomeServerErrorBody.self, from: data),
           let msg = decoded.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !msg.isEmpty {
            return msg
        }
        if let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return String(raw.prefix(200))
        }
        return nil
    }
}
