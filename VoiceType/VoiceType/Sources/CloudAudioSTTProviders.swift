import AVFoundation
import Foundation

// MARK: - Google Gemini Audio STT (Dictation + Separate-Channel Meetings)

struct GeminiAudioSTTProvider: TranscriptionProvider {
    let apiKey: String
    let model: String
    let vocabularyTerms: [String]
    private let session: URLSession

    var providerName: String { "gemini (\(resolvedModel))" }

    var resolvedModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? LLMProviderKind.gemini.defaultModel : trimmed
    }

    init(
        apiKey: String,
        model: String = "",
        vocabularyTerms: [String] = [],
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.vocabularyTerms = vocabularyTerms
        self.session = session
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidConfiguration("Не задан Google Gemini API key.")
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let audioPayload = try Self.prepareInlineAudio(from: fileURL)

        var prompt = """
        Transcribe the spoken speech in this audio verbatim in its original language (Russian, Uzbek, English, or mixed speech).
        Preserve Russian in Cyrillic and Uzbek in Latin script. Do not translate, summarize, or add timestamps.
        Return ONLY the exact transcribed text. If there is only silence or background noise with no speech, return an empty string.
        """
        if !vocabularyTerms.isEmpty {
            prompt += "\nPreferred spelling for terms/names: \(vocabularyTerms.joined(separator: ", "))."
        }

        let rawText = try await generateContent(
            systemPrompt: "You are a precise verbatim speech-to-text transcriber.",
            userPrompt: prompt,
            audioData: audioPayload.data,
            mimeType: audioPayload.mimeType,
            jsonMode: false,
            timeout: 45
        )
        let latencyMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
        let cleanText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        return TranscriptionResult(
            text: cleanText,
            languageCode: nil,
            languageSummary: nil,
            engine: "gemini (\(resolvedModel))",
            latencyMs: latencyMs,
            audioSeconds: audioPayload.durationSeconds
        )
    }

    func transcribeMeeting(
        micURL: URL,
        sysURL: URL?,
        customTerms: [String] = [],
        expectedDuration: Double? = nil,
        onProgress: (@Sendable (MeetingTranscriptionProgress) -> Void)? = nil
    ) async throws -> GapiTranscription {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidConfiguration("Не задан Google Gemini API key.")
        }

        let prepWeight = 0.05
        onProgress?(
            MeetingTranscriptionProgress(
                stage: .preparingAudio,
                overallFraction: 0.01,
                uploadPhaseEndFraction: prepWeight,
                uploadCompleted: false,
                processedSeconds: 0,
                totalSeconds: expectedDuration
            )
        )

        // Gemini объединяет стерео в моно, поэтому мик и системный звук отправляем раздельно,
        // чтобы гарантированно сохранить роли «Вы» (1) и «Собеседники» (2).
        let (micScan, sysScan) = try await Task.detached(priority: .userInitiated) {
            let mic = try WhisperWindowsClient.analyzeSpeechSlices(
                fileURL: micURL,
                maxSliceSeconds: 180,
                splitSearchStartSeconds: 120
            )
            let sys: WhisperWindowsClient.AudioScanResult? = if let sysURL, FileManager.default.fileExists(atPath: sysURL.path) {
                try WhisperWindowsClient.analyzeSpeechSlices(
                    fileURL: sysURL,
                    maxSliceSeconds: 180,
                    splitSearchStartSeconds: 120
                )
            } else {
                nil
            }
            return (mic, sys)
        }.value

        let meetingDuration = max(
            expectedDuration ?? 0,
            max(micScan.totalDurationSeconds, sysScan?.totalDurationSeconds ?? 0)
        )
        let totalDurationOpt: Double? = meetingDuration > 0 ? meetingDuration : nil

        struct WorkItem {
            let sourceURL: URL
            let slice: WhisperWindowsClient.SpeechSlice
            let speaker: Int
        }

        var workItems: [WorkItem] = micScan.slices.map { WorkItem(sourceURL: micURL, slice: $0, speaker: 1) }
        if let sysURL, let sysScan {
            workItems.append(contentsOf: sysScan.slices.map { WorkItem(sourceURL: sysURL, slice: $0, speaker: 2) })
        }
        workItems.sort { $0.slice.startSeconds < $1.slice.startSeconds }

        guard !workItems.isEmpty else {
            return GapiTranscription(
                text: "",
                languageCode: "ru",
                languageConfidence: nil,
                languageShare: nil,
                segments: [],
                summaryText: nil,
                stereoParties: sysScan != nil,
                speakerCount: sysScan != nil ? 2 : 1,
                audioSeconds: totalDurationOpt
            )
        }

        let totalSpeechWork = max(1.0, workItems.reduce(0.0) { $0 + $1.slice.durationSeconds })
        var completedWork = 0.0
        var allSegments: [GapiTranscription.Segment] = []
        let vocabPrompt = (customTerms + vocabularyTerms).joined(separator: ", ")

        for (idx, item) in workItems.enumerated() {
            try Task.checkCancellation()
            let sliceWAV = try await Task.detached(priority: .userInitiated) {
                try WhisperWindowsClient.exportSliceToTempWAV(sourceURL: item.sourceURL, slice: item.slice)
            }.value
            defer { try? FileManager.default.removeItem(at: sliceWAV) }

            let payload = try Self.prepareInlineAudio(from: sliceWAV)
            let segments = try await transcribeMeetingChunk(
                audioData: payload.data,
                mimeType: payload.mimeType,
                slice: item.slice,
                speaker: item.speaker,
                vocabularyHint: vocabPrompt
            )
            allSegments.append(contentsOf: segments)

            completedWork += item.slice.durationSeconds
            let ratio = min(1.0, completedWork / totalSpeechWork)
            let processed = meetingDuration > 0 ? ratio * meetingDuration : completedWork
            onProgress?(
                MeetingTranscriptionProgress(
                    stage: .transcribing(
                        processedSeconds: processed,
                        totalSeconds: totalDurationOpt,
                        chunkIndex: idx + 1,
                        totalChunks: workItems.count
                    ),
                    overallFraction: prepWeight + (1.0 - prepWeight) * ratio,
                    uploadPhaseEndFraction: prepWeight,
                    uploadCompleted: true,
                    processedSeconds: processed,
                    totalSeconds: totalDurationOpt
                )
            )
        }

        let merged = WhisperWindowsClient.mergeAndCleanSegments(allSegments)
        let fullText = merged.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")

        return GapiTranscription(
            text: fullText,
            languageCode: "ru",
            languageConfidence: nil,
            languageShare: nil,
            segments: merged,
            summaryText: nil,
            stereoParties: sysScan != nil,
            speakerCount: sysScan != nil ? 2 : 1,
            audioSeconds: totalDurationOpt
        )
    }

    private func transcribeMeetingChunk(
        audioData: Data,
        mimeType: String,
        slice: WhisperWindowsClient.SpeechSlice,
        speaker: Int,
        vocabularyHint: String
    ) async throws -> [GapiTranscription.Segment] {
        var prompt = """
        Transcribe all speech in this audio clip accurately in its original language (Russian in Cyrillic, Uzbek in Latin, English as spoken).
        Split into natural phrase segments with relative timestamps in seconds from the start of THIS clip (0.0 to \(String(format: "%.1f", slice.durationSeconds))).
        Return a JSON array of objects: [{"start": 0.0, "end": 4.2, "text": "..."}].
        If there is no intelligible speech, return [].
        """
        if !vocabularyHint.isEmpty {
            prompt += "\nTerms/names spelling hint: \(vocabularyHint)."
        }

        let raw = try await generateContent(
            systemPrompt: "You are a precise speech-to-text transcription engine. Output valid JSON array only.",
            userPrompt: prompt,
            audioData: audioData,
            mimeType: mimeType,
            jsonMode: true,
            timeout: 120
        )

        return Self.parseMeetingChunkResponse(raw, slice: slice, speaker: speaker)
    }

    static func parseMeetingChunkResponse(
        _ raw: String,
        slice: WhisperWindowsClient.SpeechSlice,
        speaker: Int
    ) -> [GapiTranscription.Segment] {
        struct GeminiSegment: Decodable {
            let start: Double?
            let end: Double?
            let text: String?
        }

        let cleanedJSON = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleanedJSON.data(using: .utf8),
           let items = try? JSONDecoder().decode([GeminiSegment].self, from: data) {
            let mapped = items.compactMap { item -> GapiTranscription.Segment? in
                guard let txt = item.text,
                      let clean = WhisperWindowsClient.sanitizeSegmentText(txt, avgLogProb: nil) else {
                    return nil
                }
                let relStart = max(0, item.start ?? 0)
                let relEnd = max(relStart, item.end ?? (relStart + 1))
                return GapiTranscription.Segment(
                    index: 0,
                    start: slice.startSeconds + relStart,
                    end: slice.startSeconds + relEnd,
                    speaker: speaker,
                    text: clean,
                    languageCode: "ru",
                    languageConfidence: nil
                )
            }
            if !mapped.isEmpty {
                return mapped
            }
            // Explicit empty JSON array `[]` means silence.
            if items.isEmpty {
                return []
            }
        }

        guard let fallback = WhisperWindowsClient.sanitizeSegmentText(raw, avgLogProb: nil) else {
            return []
        }
        return [
            GapiTranscription.Segment(
                index: 0,
                start: slice.startSeconds,
                end: slice.startSeconds + slice.durationSeconds,
                speaker: speaker,
                text: fallback,
                languageCode: "ru",
                languageConfidence: nil
            )
        ]
    }

    private func generateContent(
        systemPrompt: String,
        userPrompt: String,
        audioData: Data,
        mimeType: String,
        jsonMode: Bool,
        timeout: TimeInterval
    ) async throws -> String {
        let encodedModel = resolvedModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? resolvedModel
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):generateContent") else {
            throw LLMError.invalidConfiguration("Некорректное имя модели Gemini: \(resolvedModel)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = GeminiAudioBody(
            systemInstruction: .init(parts: [.init(text: systemPrompt, inlineData: nil)]),
            contents: [
                .init(
                    role: "user",
                    parts: [
                        .init(
                            text: nil,
                            inlineData: .init(mimeType: mimeType, data: audioData.base64EncodedString())
                        ),
                        .init(text: userPrompt, inlineData: nil)
                    ]
                )
            ],
            generationConfig: .init(
                temperature: 0.1,
                maxOutputTokens: jsonMode ? 8192 : 2048,
                responseMimeType: jsonMode ? "application/json" : nil
            )
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw LLMError.httpError(statusCode: http.statusCode, message: msg)
        }

        let decoded = try JSONDecoder().decode(GeminiAudioResponse.self, from: data)
        let parts = decoded.candidates?.first?.content?.parts ?? []
        return parts
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func prepareInlineAudio(from fileURL: URL) throws -> (data: Data, mimeType: String, durationSeconds: Double?) {
        let rawData = try Data(contentsOf: fileURL)
        let ext = fileURL.pathExtension.lowercased()
        let duration: Double? = {
            guard let file = try? AVAudioFile(forReading: fileURL), file.processingFormat.sampleRate > 0 else {
                return nil
            }
            return Double(file.length) / file.processingFormat.sampleRate
        }()

        // Если файл больше 12 МБ — сжимаем в компактный AAC/M4A (~480 КБ/мин), чтобы уверенно вписываться в inline-лимит.
        if rawData.count > 12 * 1024 * 1024 {
            let compressed = try AudioCompressor().encodeAACM4A(from: fileURL, bitRate: 64_000)
            return (compressed, "audio/mp4", duration)
        }

        let mimeType: String = switch ext {
        case "m4a", "mp4": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "ogg", "oga": "audio/ogg"
        case "flac": "audio/flac"
        default: "audio/wav"
        }
        return (rawData, mimeType, duration)
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
            let message: String?
        }
        if let decoded = try? JSONDecoder().decode(Envelope.self, from: data),
           let msg = decoded.error?.message ?? decoded.message,
           !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return msg
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(240)) }
    }

    private struct GeminiAudioBody: Encodable {
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
        struct Part: Encodable {
            let text: String?
            let inlineData: InlineData?
        }
        struct InlineData: Encodable {
            let mimeType: String
            let data: String
        }
        struct GenerationConfig: Encodable {
            let temperature: Double
            let maxOutputTokens: Int
            let responseMimeType: String?
        }
    }

    private struct GeminiAudioResponse: Decodable {
        let candidates: [Candidate]?
        struct Candidate: Decodable {
            let content: Content?
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

// MARK: - OpenAI Audio STT (whisper-1, 25 MB chunking)

struct OpenAIAudioSTTProvider: TranscriptionProvider {
    static let maxUploadBytes = 23 * 1024 * 1024

    let apiKey: String
    let model: String
    let vocabularyTerms: [String]
    private let session: URLSession

    var providerName: String { "openai (\(model))" }

    init(
        apiKey: String,
        model: String = "whisper-1",
        vocabularyTerms: [String] = [],
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        self.vocabularyTerms = vocabularyTerms
        self.session = session
    }

    func transcribe(fileURL: URL) async throws -> TranscriptionResult {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidConfiguration("Не задан OpenAI API key.")
        }
        let startedAt = CFAbsoluteTimeGetCurrent()
        let upload = try Self.prepareChunkForOpenAI(from: fileURL)
        let prompt = vocabularyTerms.isEmpty ? nil : vocabularyTerms.joined(separator: ", ")

        let req = try buildTranscriptionRequest(
            audioData: upload.data,
            filename: upload.filename,
            mimeType: upload.mimeType,
            prompt: prompt,
            includeSegmentTimestamps: false,
            timeout: 45
        )

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
            throw LLMError.httpError(statusCode: http.statusCode, message: msg)
        }

        let decoded = try JSONDecoder().decode(WhisperWindowsClient.VerboseResponse.self, from: data)
        let text = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let latencyMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))

        return TranscriptionResult(
            text: text,
            languageCode: decoded.language,
            languageSummary: nil,
            engine: "openai (\(model))",
            latencyMs: latencyMs,
            audioSeconds: decoded.duration
        )
    }

    func transcribeMeeting(
        micURL: URL,
        sysURL: URL?,
        customTerms: [String] = [],
        expectedDuration: Double? = nil,
        onProgress: (@Sendable (MeetingTranscriptionProgress) -> Void)? = nil
    ) async throws -> GapiTranscription {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidConfiguration("Не задан OpenAI API key.")
        }

        let prepWeight = 0.05
        onProgress?(
            MeetingTranscriptionProgress(
                stage: .preparingAudio,
                overallFraction: 0.01,
                uploadPhaseEndFraction: prepWeight,
                uploadCompleted: false,
                processedSeconds: 0,
                totalSeconds: expectedDuration
            )
        )

        // Лимит OpenAI — 25 МБ: режем речь на чанки до ~180 с (16 кГц моно WAV ≈ 5.7 МБ),
        // при превышении сжимаем в AAC/M4A. Мик (1) и системный звук (2) обрабатываются раздельно.
        let (micScan, sysScan) = try await Task.detached(priority: .userInitiated) {
            let mic = try WhisperWindowsClient.analyzeSpeechSlices(
                fileURL: micURL,
                maxSliceSeconds: 180,
                splitSearchStartSeconds: 120
            )
            let sys: WhisperWindowsClient.AudioScanResult? = if let sysURL, FileManager.default.fileExists(atPath: sysURL.path) {
                try WhisperWindowsClient.analyzeSpeechSlices(
                    fileURL: sysURL,
                    maxSliceSeconds: 180,
                    splitSearchStartSeconds: 120
                )
            } else {
                nil
            }
            return (mic, sys)
        }.value

        let meetingDuration = max(
            expectedDuration ?? 0,
            max(micScan.totalDurationSeconds, sysScan?.totalDurationSeconds ?? 0)
        )
        let totalDurationOpt: Double? = meetingDuration > 0 ? meetingDuration : nil

        struct WorkItem {
            let sourceURL: URL
            let slice: WhisperWindowsClient.SpeechSlice
            let speaker: Int
        }

        var workItems: [WorkItem] = micScan.slices.map { WorkItem(sourceURL: micURL, slice: $0, speaker: 1) }
        if let sysURL, let sysScan {
            workItems.append(contentsOf: sysScan.slices.map { WorkItem(sourceURL: sysURL, slice: $0, speaker: 2) })
        }
        workItems.sort { $0.slice.startSeconds < $1.slice.startSeconds }

        guard !workItems.isEmpty else {
            return GapiTranscription(
                text: "",
                languageCode: "ru",
                languageConfidence: nil,
                languageShare: nil,
                segments: [],
                summaryText: nil,
                stereoParties: sysScan != nil,
                speakerCount: sysScan != nil ? 2 : 1,
                audioSeconds: totalDurationOpt
            )
        }

        let prompt = WhisperWindowsClient.buildPrompt(customTerms: customTerms + vocabularyTerms)
        let totalSpeechWork = max(1.0, workItems.reduce(0.0) { $0 + $1.slice.durationSeconds })
        var completedWork = 0.0
        var allSegments: [GapiTranscription.Segment] = []

        for (idx, item) in workItems.enumerated() {
            try Task.checkCancellation()
            let tempWAV = try await Task.detached(priority: .userInitiated) {
                try WhisperWindowsClient.exportSliceToTempWAV(sourceURL: item.sourceURL, slice: item.slice)
            }.value
            defer { try? FileManager.default.removeItem(at: tempWAV) }

            let chunk = try Self.prepareChunkForOpenAI(from: tempWAV)
            let req = try buildTranscriptionRequest(
                audioData: chunk.data,
                filename: chunk.filename,
                mimeType: chunk.mimeType,
                prompt: prompt,
                includeSegmentTimestamps: true,
                timeout: 120
            )

            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw LLMError.emptyResponse
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = Self.extractErrorMessage(from: data) ?? "HTTP \(http.statusCode)"
                throw LLMError.httpError(statusCode: http.statusCode, message: msg)
            }

            let decoded = try JSONDecoder().decode(WhisperWindowsClient.VerboseResponse.self, from: data)
            allSegments.append(contentsOf: Self.extractSegments(from: decoded, slice: item.slice, speaker: item.speaker))

            completedWork += item.slice.durationSeconds
            let ratio = min(1.0, completedWork / totalSpeechWork)
            let processed = meetingDuration > 0 ? ratio * meetingDuration : completedWork
            onProgress?(
                MeetingTranscriptionProgress(
                    stage: .transcribing(
                        processedSeconds: processed,
                        totalSeconds: totalDurationOpt,
                        chunkIndex: idx + 1,
                        totalChunks: workItems.count
                    ),
                    overallFraction: prepWeight + (1.0 - prepWeight) * ratio,
                    uploadPhaseEndFraction: prepWeight,
                    uploadCompleted: true,
                    processedSeconds: processed,
                    totalSeconds: totalDurationOpt
                )
            )
        }

        let merged = WhisperWindowsClient.mergeAndCleanSegments(allSegments)
        let fullText = merged.map(\.text).filter { !$0.isEmpty }.joined(separator: "\n")

        return GapiTranscription(
            text: fullText,
            languageCode: "ru",
            languageConfidence: nil,
            languageShare: nil,
            segments: merged,
            summaryText: nil,
            stereoParties: sysScan != nil,
            speakerCount: sysScan != nil ? 2 : 1,
            audioSeconds: totalDurationOpt
        )
    }

    func buildTranscriptionRequest(
        audioData: Data,
        filename: String,
        mimeType: String,
        prompt: String?,
        includeSegmentTimestamps: Bool,
        timeout: TimeInterval
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else {
            throw LLMError.invalidConfiguration("Не задан OpenAI API key.")
        }
        let boundary = "voicetype-openai-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        appendField("model", model)
        appendField("response_format", "verbose_json")
        if includeSegmentTimestamps {
            appendField("timestamp_granularities[]", "segment")
        }
        if let prompt, !prompt.isEmpty {
            appendField("prompt", prompt)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    static func extractSegments(
        from decoded: WhisperWindowsClient.VerboseResponse,
        slice: WhisperWindowsClient.SpeechSlice,
        speaker: Int
    ) -> [GapiTranscription.Segment] {
        if let segments = decoded.segments, !segments.isEmpty {
            let mapped = segments.compactMap { seg -> GapiTranscription.Segment? in
                let rawText = (seg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let cleaned = WhisperWindowsClient.sanitizeSegmentText(rawText, avgLogProb: seg.avg_logprob) else {
                    return nil
                }
                let start = slice.startSeconds + (seg.start ?? 0)
                let end = slice.startSeconds + (seg.end ?? seg.start ?? 0)
                return GapiTranscription.Segment(
                    index: 0,
                    start: start,
                    end: max(start, end),
                    speaker: speaker,
                    text: cleaned,
                    languageCode: decoded.language ?? "ru",
                    languageConfidence: nil
                )
            }
            if !mapped.isEmpty {
                return mapped
            }
        }
        let fallbackRaw = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fallback = WhisperWindowsClient.sanitizeSegmentText(fallbackRaw, avgLogProb: nil) else {
            return []
        }
        return [
            GapiTranscription.Segment(
                index: 0,
                start: slice.startSeconds,
                end: slice.startSeconds + slice.durationSeconds,
                speaker: speaker,
                text: fallback,
                languageCode: decoded.language ?? "ru",
                languageConfidence: nil
            )
        ]
    }

    private static func prepareChunkForOpenAI(from fileURL: URL) throws -> (data: Data, filename: String, mimeType: String) {
        let rawData = try Data(contentsOf: fileURL)
        if rawData.count > maxUploadBytes {
            let compressed = try AudioCompressor().encodeAACM4A(from: fileURL, bitRate: 64_000)
            return (compressed, "audio.m4a", "audio/mp4")
        }
        let ext = fileURL.pathExtension.lowercased()
        let mime = ext == "m4a" ? "audio/mp4" : "audio/wav"
        return (rawData, fileURL.lastPathComponent.isEmpty ? "audio.\(ext)" : fileURL.lastPathComponent, mime)
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
            let message: String?
        }
        if let decoded = try? JSONDecoder().decode(Envelope.self, from: data),
           let msg = decoded.error?.message ?? decoded.message,
           !msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return msg
        }
        return String(data: data, encoding: .utf8).map { String($0.prefix(240)) }
    }
}
