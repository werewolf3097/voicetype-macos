import AVFoundation
import Foundation
import Network

struct MockHTTPRequest: Sendable {
    let method: String
    let path: String
    let queryItems: [String: String]
    let headers: [String: String]
    let body: Data
}

struct MockHTTPResponse: Sendable {
    let statusCode: Int
    let reasonPhrase: String
    let body: Data
    let contentType: String
    let delaySeconds: TimeInterval

    init(
        statusCode: Int = 200,
        reasonPhrase: String? = nil,
        json: [String: Any],
        delaySeconds: TimeInterval = 0
    ) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase ?? Self.defaultReason(for: statusCode)
        self.body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        self.contentType = "application/json"
        self.delaySeconds = delaySeconds
    }

    init(
        statusCode: Int,
        reasonPhrase: String? = nil,
        rawBody: Data,
        contentType: String = "application/json",
        delaySeconds: TimeInterval = 0
    ) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase ?? Self.defaultReason(for: statusCode)
        self.body = rawBody
        self.contentType = contentType
        self.delaySeconds = delaySeconds
    }

    private static func defaultReason(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 413: return "Payload Too Large"
        case 415: return "Unsupported Media Type"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 502: return "Bad Gateway"
        default: return "Status \(code)"
        }
    }
}

/// Локальный мок HTTP-шлюза на 127.0.0.1 для юнит-тестов HomeServerProvider.
final class MockGatewayServer: @unchecked Sendable {
    typealias Handler = @Sendable (MockHTTPRequest) -> MockHTTPResponse

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.farrukh.voicetype.mockgateway", attributes: .concurrent)
    private let lock = NSLock()
    private var handler: Handler
    private var _recordedRequests: [MockHTTPRequest] = []

    private(set) var port: UInt16 = 0
    var baseURLString: String { "http://127.0.0.1:\(port)" }

    var recordedRequests: [MockHTTPRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _recordedRequests
    }

    init(handler: @escaping Handler) throws {
        self.handler = handler
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let localListener = try NWListener(using: params, on: .any)
        self.listener = localListener

        let ready = DispatchSemaphore(value: 0)
        var boundPort: UInt16 = 0
        var startError: Error?

        localListener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                boundPort = localListener.port?.rawValue ?? 0
                ready.signal()
            case .failed(let err):
                startError = err
                ready.signal()
            default:
                break
            }
        }

        localListener.newConnectionHandler = { [weak self] conn in
            self?.handleConnection(conn)
        }

        localListener.start(queue: queue)
        ready.wait()

        if let startError {
            throw startError
        }
        guard boundPort > 0 else {
            throw NSError(domain: "MockGatewayServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to bind ephemeral port"])
        }
        self.port = boundPort
    }

    func setHandler(_ newHandler: @escaping Handler) {
        lock.lock()
        self.handler = newHandler
        lock.unlock()
    }

    func stop() {
        listener.cancel()
    }

    deinit {
        listener.cancel()
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        var buffer = Data()
        readNextChunk(connection: connection, buffer: &buffer)
    }

    private func readNextChunk(connection: NWConnection, buffer: inout Data) {
        var accumulated = buffer
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_144) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if let data, !data.isEmpty {
                accumulated.append(data)
            }
            if let parsed = Self.tryParseHTTPRequest(from: accumulated) {
                self.dispatchRequest(parsed, on: connection)
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            var nextBuf = accumulated
            self.readNextChunk(connection: connection, buffer: &nextBuf)
        }
    }

    private func dispatchRequest(_ request: MockHTTPRequest, on connection: NWConnection) {
        lock.lock()
        _recordedRequests.append(request)
        let currentHandler = handler
        lock.unlock()

        let response = currentHandler(request)
        let sendBlock = {
            let headerLines = [
                "HTTP/1.1 \(response.statusCode) \(response.reasonPhrase)",
                "Content-Type: \(response.contentType)",
                "Content-Length: \(response.body.count)",
                "Connection: close",
                "",
                ""
            ]
            var wire = Data(headerLines.joined(separator: "\r\n").utf8)
            wire.append(response.body)
            connection.send(content: wire, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }

        if response.delaySeconds > 0 {
            queue.asyncAfter(deadline: .now() + response.delaySeconds, execute: sendBlock)
        } else {
            sendBlock()
        }
    }

    private static func tryParseHTTPRequest(from data: Data) -> MockHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEndRange = data.range(of: separator) else { return nil }
        let headerData = data[..<headerEndRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        let method = String(parts[0])
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let bodyStart = headerEndRange.upperBound
        let rawBody = Data(data[bodyStart...])

        if let clString = headers["content-length"], let expectedLen = Int(clString) {
            guard rawBody.count >= expectedLen else { return nil }
            let body = Data(rawBody.prefix(expectedLen))
            return buildRequest(method: method, target: target, headers: headers, body: body)
        }

        if let te = headers["transfer-encoding"]?.lowercased(), te.contains("chunked") {
            guard let decoded = decodeChunkedBody(rawBody) else { return nil }
            return buildRequest(method: method, target: target, headers: headers, body: decoded)
        }

        return buildRequest(method: method, target: target, headers: headers, body: rawBody)
    }

    private static func buildRequest(
        method: String,
        target: String,
        headers: [String: String],
        body: Data
    ) -> MockHTTPRequest {
        let components = URLComponents(string: "http://localhost\(target)")
        let path = components?.path ?? target
        var queryDict: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            queryDict[item.name] = item.value ?? ""
        }
        return MockHTTPRequest(
            method: method,
            path: path,
            queryItems: queryDict,
            headers: headers,
            body: body
        )
    }

    private static func decodeChunkedBody(_ data: Data) -> Data? {
        var result = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while true {
            guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else { return nil }
            let sizeStr = String(data: data[index..<lineEnd.lowerBound], encoding: .utf8)?
                .split(separator: ";").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard let chunkSize = Int(sizeStr, radix: 16) else { return nil }
            let chunkStart = lineEnd.upperBound
            if chunkSize == 0 {
                // Ensure trailing CRLF exists
                if data.distance(from: chunkStart, to: data.endIndex) >= 2 {
                    return result
                }
                return nil
            }
            let needed = chunkSize + 2
            guard data.distance(from: chunkStart, to: data.endIndex) >= needed else { return nil }
            let chunkEnd = data.index(chunkStart, offsetBy: chunkSize)
            result.append(data[chunkStart..<chunkEnd])
            index = data.index(chunkEnd, offsetBy: 2)
        }
    }
}

enum TestAudioFactory {
    static func makeSampleWAV(durationSeconds: Double = 2.0, sampleRate: Double = 16_000) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetype-test-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: true
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.int16ChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let value = sin(2.0 * .pi * 320.0 * t) * 0.4 + sin(2.0 * .pi * 640.0 * t) * 0.2
            samples[i] = Int16(value * 32767.0)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        try file.write(from: buffer)
        return url
    }
}
