import Foundation

struct GapiError: Error, LocalizedError {
    let code: String
    let hint: String?

    var errorDescription: String? {
        hint ?? code
    }
}

struct GapiTranscription: Equatable {
    struct Segment: Equatable, Codable, Identifiable {
        var id: Int { index }
        let index: Int
        let start: Double?
        let end: Double?
        let speaker: Int?
        let text: String
        let languageCode: String?
        let languageConfidence: Double?

        init(
            index: Int,
            start: Double? = nil,
            end: Double? = nil,
            speaker: Int? = nil,
            text: String,
            languageCode: String? = nil,
            languageConfidence: Double? = nil
        ) {
            self.index = index
            self.start = start
            self.end = end
            self.speaker = speaker
            self.text = text
            self.languageCode = languageCode
            self.languageConfidence = languageConfidence
        }
    }

    let text: String
    let languageCode: String?
    let languageConfidence: Double?
    let languageShare: [String: Double]?
    let segments: [Segment]
    let summaryText: String?
    let stereoParties: Bool?
    let speakerCount: Int?
    let audioSeconds: Double?

    init(
        text: String,
        languageCode: String?,
        languageConfidence: Double?,
        languageShare: [String: Double]?,
        segments: [Segment],
        summaryText: String? = nil,
        stereoParties: Bool? = nil,
        speakerCount: Int? = nil,
        audioSeconds: Double? = nil
    ) {
        self.text = text
        self.languageCode = languageCode
        self.languageConfidence = languageConfidence
        self.languageShare = languageShare
        self.segments = segments
        self.summaryText = summaryText
        self.stereoParties = stereoParties
        self.speakerCount = speakerCount
        self.audioSeconds = audioSeconds
    }

    /// Человекочитаемая метка языка (например: "O‘zbek", "Русский", или "O‘zbek 70% · Русский 30%")
    var languageSummary: String? {
        if let share = languageShare, share.count > 1 {
            let sorted = share
                .filter { $0.value >= 0.1 }
                .sorted { $0.value > $1.value }
            if sorted.count > 1 {
                return sorted
                    .map { "\(Self.displayName(for: $0.key)) \(Int(($0.value * 100).rounded()))%" }
                    .joined(separator: " · ")
            }
        }
        guard let code = languageCode, !code.isEmpty else { return nil }
        return Self.displayName(for: code)
    }

    static func displayName(for code: String) -> String {
        switch code.lowercased() {
        case "uz": return "O‘zbek"
        case "uz-khorezm": return "O‘zbek (Xorazm)"
        case "kaa": return "Qaraqalpaq"
        case "ru": return "Русский"
        case "en": return "English"
        case "kk": return "Қазақ"
        case "ky": return "Кыргызча"
        case "tg": return "Тоҷикӣ"
        case "tk": return "Türkmen"
        default: return code.uppercased()
        }
    }
}

struct GapiClient {
    let token: String
    private let baseURL = URL(string: "https://console.gapi.uz")!

    private struct TranscribeResult: Decodable {
        struct LanguageInfo: Decodable {
            let code: String?
            let confidence: Double?
            let speech_seconds: Double?
            let share: [String: Double]?
            let reason: String?
        }

        struct SummaryInfo: Decodable {
            let text: String?
            let lines: Int?
            let read_lines: Int?
        }

        struct SegmentResult: Decodable {
            struct SegmentLanguage: Decodable {
                let code: String?
                let confidence: Double?
                let reason: String?
            }

            let index: Int?
            let start: Double?
            let end: Double?
            let speaker: Int?
            let text: String?
            let formatted_text: String?
            let raw_asr_text: String?
            let language: SegmentLanguage?
        }

        let audio_seconds: Double?
        let stereo_parties: Bool?
        let speakers: Int?
        let text: String?
        let language: LanguageInfo?
        let summary: SummaryInfo?
        let segments: [SegmentResult]?

        func toTranscription() -> GapiTranscription {
            let mappedSegments: [GapiTranscription.Segment] = (segments ?? []).enumerated().map { idx, seg in
                let segText = seg.formatted_text ?? seg.text ?? seg.raw_asr_text ?? ""
                return GapiTranscription.Segment(
                    index: seg.index ?? idx,
                    start: seg.start,
                    end: seg.end,
                    speaker: seg.speaker,
                    text: segText,
                    languageCode: seg.language?.code,
                    languageConfidence: seg.language?.confidence
                )
            }

            let fullText: String
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fullText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                fullText = mappedSegments
                    .map(\.text)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // По документации gapi: общий language.code считается при >= 2 сек речи,
            // а segments[].language.code — при >= 1 сек речи. Если запись была 1–2 сек,
            // берём язык из первого сегмента, где он определился.
            let fallbackSegmentLang = mappedSegments.first(where: { $0.languageCode != nil })
            let resolvedCode = language?.code ?? fallbackSegmentLang?.languageCode
            let resolvedConfidence = language?.confidence ?? fallbackSegmentLang?.languageConfidence

            let rawTranscription = GapiTranscription(
                text: fullText,
                languageCode: resolvedCode,
                languageConfidence: resolvedConfidence,
                languageShare: language?.share,
                segments: mappedSegments,
                summaryText: summary?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                stereoParties: stereo_parties,
                speakerCount: speakers,
                audioSeconds: audio_seconds
            )
            return RussianTransliterator.applyIfNeeded(rawTranscription)
        }
    }

    private struct JobAccepted: Decodable {
        let id: String?
        let job_id: String?
        let state: String?
        let estimated_seconds: Double?

        var resolvedId: String? { id ?? job_id }
    }

    private struct JobStatus: Decodable {
        let id: String?
        let state: String
        let progress_seconds: Double?
        let audio_seconds: Double?
        let error: String?
    }

    private struct VocabularyResponse: Decodable {
        let terms: [String]
    }

    func transcribe(fileURL: URL) async throws -> GapiTranscription {
        let boundary = "voicetype-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/transcribe"))
        request.httpMethod = "POST"
        request.timeoutInterval = 190
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try multipartBody(fileURL: fileURL, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GapiError(code: "no_response", hint: nil)
        }

        if http.statusCode == 200 {
            let result = try JSONDecoder().decode(TranscribeResult.self, from: data)
            return result.toTranscription()
        }

        if http.statusCode == 202 {
            let accepted = try JSONDecoder().decode(JobAccepted.self, from: data)
            guard let jobId = accepted.resolvedId else {
                throw GapiError(code: "missing_job_id", hint: "Сервер вернул 202 без идентификатора задачи")
            }
            return try await pollForResult(jobId: jobId)
        }

        throw try decodeError(data)
    }

    func transcribeMeeting(
        fileURL: URL,
        stereoParties: Bool,
        enableSummary: Bool,
        onProgress: (@Sendable (Double?) -> Void)? = nil
    ) async throws -> GapiTranscription {
        let boundary = "voicetype-meeting-\(UUID().uuidString)"
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/jobs"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try meetingMultipartBody(
            fileURL: fileURL,
            boundary: boundary,
            stereoParties: stereoParties,
            enableSummary: enableSummary
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GapiError(code: "no_response", hint: nil)
        }

        if http.statusCode == 200 {
            let result = try JSONDecoder().decode(TranscribeResult.self, from: data)
            return result.toTranscription()
        }

        if http.statusCode == 202 {
            let accepted = try JSONDecoder().decode(JobAccepted.self, from: data)
            guard let jobId = accepted.resolvedId else {
                throw GapiError(code: "missing_job_id", hint: "Сервер вернул 202 без идентификатора задачи")
            }
            return try await pollForResult(jobId: jobId, maxPolls: 900, onProgress: onProgress)
        }

        throw try decodeError(data)
    }

    func getVocabulary() async throws -> [String] {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/vocabulary"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw try decodeError(data)
        }
        return try JSONDecoder().decode(VocabularyResponse.self, from: data).terms
    }

    func setVocabulary(_ terms: [String]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/vocabulary"))
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["terms": terms])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw try decodeError(data)
        }
    }

    private func pollForResult(
        jobId: String,
        maxPolls: Int = 60,
        onProgress: (@Sendable (Double?) -> Void)? = nil
    ) async throws -> GapiTranscription {
        let statusURL = baseURL.appendingPathComponent("v1/jobs/\(jobId)")
        let resultURL = baseURL.appendingPathComponent("v1/jobs/\(jobId)/result")

        for _ in 0..<maxPolls {
            try await Task.sleep(nanoseconds: 2_000_000_000)

            var statusRequest = URLRequest(url: statusURL)
            statusRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (statusData, _) = try await URLSession.shared.data(for: statusRequest)
            let status = try JSONDecoder().decode(JobStatus.self, from: statusData)

            if let prog = status.progress_seconds {
                onProgress?(prog)
            }

            switch status.state {
            case "done":
                var resultRequest = URLRequest(url: resultURL)
                resultRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (resultData, resultResp) = try await URLSession.shared.data(for: resultRequest)
                if let http = resultResp as? HTTPURLResponse, http.statusCode == 409 {
                    continue
                }
                let result = try JSONDecoder().decode(TranscribeResult.self, from: resultData)
                return result.toTranscription()
            case "failed", "cancelled":
                let reason = status.error ?? "Задача распознавания завершилась со статусом \(status.state)"
                throw GapiError(code: "job_\(status.state)", hint: reason)
            default:
                continue
            }
        }
        throw GapiError(code: "timeout", hint: "Распознавание заняло слишком много времени")
    }

    private func decodeError(_ data: Data) throws -> GapiError {
        struct Body: Decodable { let error: String; let hint: String? }
        if let body = try? JSONDecoder().decode(Body.self, from: data) {
            return GapiError(code: body.error, hint: body.hint)
        }
        return GapiError(code: "unknown_error", hint: String(data: data, encoding: .utf8))
    }

    private func multipartBody(fileURL: URL, boundary: String) throws -> Data {
        var body = Data()
        let audioData = try Data(contentsOf: fileURL)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Согласовано с документацией console.gapi.uz/docs/ru/options.html:
        // Включаем пунктуацию (formatting), нормализацию чисел (itn) и определение языка (language_detection: uz, ru, en и др.).
        // Явно выключаем платные (pii ×1.2, voice_events ×1.2, summary ×1.3) и колл-центровые опции,
        // которые в новом проекте gapi включены по умолчанию и иначе замедляют каждый запрос диктовки.
        let settingsDict: [String: Any] = [
            "formatting": true,
            "itn": true,
            "fuzzy_itn": true,
            "language_detection": true,
            "diarization": false,
            "stereo_channels_as_speakers": false,
            "gender": false,
            "call_outcome": false,
            "speaker_roles": false,
            "speaker_identification": false,
            "voice_events": false,
            "summary": false,
            "pii": false,
            "word_timestamps": false
        ]
        let settingsData = try JSONSerialization.data(withJSONObject: settingsDict)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"settings\"\r\n\r\n".data(using: .utf8)!)
        body.append(settingsData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func meetingMultipartBody(
        fileURL: URL,
        boundary: String,
        stereoParties: Bool,
        enableSummary: Bool
    ) throws -> Data {
        var body = Data()
        let audioData = try Data(contentsOf: fileURL)
        let mimeType = fileURL.pathExtension.lowercased() == "m4a" ? "audio/mp4" : "audio/wav"

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        let settingsDict: [String: Any] = [
            "formatting": true,
            "itn": true,
            "fuzzy_itn": true,
            "language_detection": true,
            "stereo_channels_as_speakers": stereoParties,
            "diarization": !stereoParties,
            "gender": false,
            "call_outcome": false,
            "speaker_roles": false,
            "speaker_identification": false,
            "voice_events": false,
            "summary": enableSummary,
            "pii": false,
            "word_timestamps": false
        ]
        let settingsData = try JSONSerialization.data(withJSONObject: settingsDict)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"settings\"\r\n\r\n".data(using: .utf8)!)
        body.append(settingsData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
