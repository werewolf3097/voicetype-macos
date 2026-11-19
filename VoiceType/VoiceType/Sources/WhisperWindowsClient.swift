import AVFoundation
import Foundation

enum WhisperWindowsError: Error, LocalizedError {
    case invalidURL(String)
    case serverUnavailable(String)
    case unreadableAudio(String)
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Некорректный адрес Whisper-сервера: \(url)"
        case .serverUnavailable(let msg):
            return "Сервер распознавания недоступен: \(msg)"
        case .unreadableAudio(let msg):
            return "Не удалось прочитать аудиофайл: \(msg)"
        case .serverError(let code, let body):
            return "Сервер распознавания вернул ошибку \(code): \(body)"
        }
    }
}

struct WhisperWindowsClient: Sendable {
    static let defaultVocabularyPrompt = "Korzinka, Yango, SuperApp, SuperPortal, EPAM, Brander, Omni, SAP, CIAM, CDP, CVM, Atlant, Lokalise, 2GIS, OpenMaps, De Factum, Tez, Uzum, Infinbank"

    private let baseURLString: String

    init(baseURLString: String = "") {
        self.baseURLString = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var engineDisplayName: String {
        if let host = (try? resolvedBaseURL())?.host, !host.isEmpty {
            return "Whisper (\(host))"
        }
        return "Внешний сервер"
    }

    private func resolvedBaseURL() throws -> URL {
        let cleaned = baseURLString.hasSuffix("/") ? String(baseURLString.dropLast()) : baseURLString
        guard !cleaned.isEmpty, let url = URL(string: cleaned), url.scheme != nil, url.host != nil else {
            throw WhisperWindowsError.invalidURL(baseURLString)
        }
        return url
    }

    func isReachable(timeout: TimeInterval = 2.5) async -> Bool {
        guard let baseURL = try? resolvedBaseURL() else { return false }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private static let preparationBarShare: Double = 0.05

    func transcribeMeeting(
        micURL: URL,
        sysURL: URL?,
        customTerms: [String] = [],
        expectedDuration: Double? = nil,
        onProgress: (@Sendable (MeetingTranscriptionProgress) -> Void)? = nil
    ) async throws -> GapiTranscription {
        let baseURL = try resolvedBaseURL()
        let prompt = Self.buildPrompt(customTerms: customTerms)
        let prepWeight = Self.preparationBarShare

        onProgress?(
            MeetingTranscriptionProgress(
                stage: .preparingAudio,
                overallFraction: 0.02,
                uploadPhaseEndFraction: prepWeight,
                uploadCompleted: false,
                processedSeconds: 0,
                totalSeconds: expectedDuration
            )
        )

        let micScan = try await Task.detached(priority: .userInitiated) {
            try Self.analyzeSpeechSlices(fileURL: micURL)
        }.value

        let sysScan: AudioScanResult?
        if let sysURL, FileManager.default.fileExists(atPath: sysURL.path) {
            sysScan = try await Task.detached(priority: .userInitiated) {
                try Self.analyzeSpeechSlices(fileURL: sysURL)
            }.value
        } else {
            sysScan = nil
        }

        let meetingDuration = max(micScan.totalDurationSeconds, sysScan?.totalDurationSeconds ?? 0, expectedDuration ?? 0)
        let totalDurationOpt: Double? = meetingDuration > 0 ? meetingDuration : nil
        let totalSpeechWork = max(1.0, micScan.totalSpeechDuration + (sysScan?.totalSpeechDuration ?? 0))
        var completedSpeechWork = 0.0

        var workItems: [(sourceURL: URL, slice: SpeechSlice, speaker: Int)] = micScan.slices.map {
            (sourceURL: micURL, slice: $0, speaker: 0)
        }
        if let sysURL, let sysScan {
            workItems.append(contentsOf: sysScan.slices.map {
                (sourceURL: sysURL, slice: $0, speaker: 1)
            })
        }

        let totalChunks = workItems.count
        var allSegments: [GapiTranscription.Segment] = []

        for (index, item) in workItems.enumerated() {
            try Task.checkCancellation()
            let chunkIndex = index + 1
            let sliceBaseRatio = completedSpeechWork / totalSpeechWork
            let sliceSpanRatio = item.slice.durationSeconds / totalSpeechWork
            let processedBefore = meetingDuration > 0 ? sliceBaseRatio * meetingDuration : completedSpeechWork

            let sliceSegments = try await transcribeSlice(
                sourceURL: item.sourceURL,
                slice: item.slice,
                speaker: item.speaker,
                baseURL: baseURL,
                prompt: prompt
            ) { sent, expected, isUploadDone in
                if isUploadDone {
                    let overall = prepWeight + (1.0 - prepWeight) * (sliceBaseRatio + sliceSpanRatio * 0.15)
                    onProgress?(
                        MeetingTranscriptionProgress(
                            stage: .transcribing(
                                processedSeconds: processedBefore,
                                totalSeconds: totalDurationOpt,
                                chunkIndex: chunkIndex,
                                totalChunks: totalChunks
                            ),
                            overallFraction: overall,
                            uploadPhaseEndFraction: prepWeight,
                            uploadCompleted: true,
                            processedSeconds: processedBefore,
                            totalSeconds: totalDurationOpt
                        )
                    )
                } else {
                    let uploadRatio = expected > 0 ? min(1.0, Double(sent) / Double(expected)) : 0
                    let overall = prepWeight + (1.0 - prepWeight) * (sliceBaseRatio + sliceSpanRatio * 0.15 * uploadRatio)
                    onProgress?(
                        MeetingTranscriptionProgress(
                            stage: .uploading(
                                bytesSent: sent,
                                totalBytes: expected,
                                chunkIndex: chunkIndex,
                                totalChunks: totalChunks
                            ),
                            overallFraction: overall,
                            uploadPhaseEndFraction: prepWeight,
                            uploadCompleted: false,
                            processedSeconds: processedBefore,
                            totalSeconds: totalDurationOpt
                        )
                    )
                }
            }

            allSegments.append(contentsOf: sliceSegments)
            completedSpeechWork += item.slice.durationSeconds
            let newRatio = min(1.0, completedSpeechWork / totalSpeechWork)
            let newProcessed = meetingDuration > 0 ? newRatio * meetingDuration : completedSpeechWork
            let overall = prepWeight + (1.0 - prepWeight) * newRatio
            onProgress?(
                MeetingTranscriptionProgress(
                    stage: .transcribing(
                        processedSeconds: newProcessed,
                        totalSeconds: totalDurationOpt,
                        chunkIndex: chunkIndex,
                        totalChunks: totalChunks
                    ),
                    overallFraction: overall,
                    uploadPhaseEndFraction: prepWeight,
                    uploadCompleted: true,
                    processedSeconds: newProcessed,
                    totalSeconds: totalDurationOpt
                )
            )
        }

        let merged = Self.mergeAndCleanSegments(allSegments)
        let fullText = merged
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        return GapiTranscription(
            text: fullText,
            languageCode: "ru",
            languageConfidence: nil,
            languageShare: nil,
            segments: merged,
            summaryText: nil,
            stereoParties: sysScan != nil,
            speakerCount: sysScan != nil ? 2 : 1,
            audioSeconds: meetingDuration > 0 ? meetingDuration : nil
        )
    }

    // MARK: - VAD & Audio Slicing

    private struct SpeechSlice: Sendable {
        let startFrame: AVAudioFramePosition
        let endFrame: AVAudioFramePosition
        let startSeconds: Double
        let durationSeconds: Double
    }

    private struct AudioScanResult: Sendable {
        let totalDurationSeconds: Double
        let slices: [SpeechSlice]
        var totalSpeechDuration: Double {
            slices.reduce(0) { $0 + $1.durationSeconds }
        }
    }

    private static func analyzeSpeechSlices(fileURL: URL) throws -> AudioScanResult {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw WhisperWindowsError.unreadableAudio(error.localizedDescription)
        }

        let sampleRate = audioFile.processingFormat.sampleRate
        let totalFrames = audioFile.length
        guard sampleRate > 0, totalFrames > 0 else {
            return AudioScanResult(totalDurationSeconds: 0, slices: [])
        }
        let totalDuration = Double(totalFrames) / sampleRate

        let windowDuration = 0.1 // 100 ms
        let windowFrames = max(1, AVAudioFrameCount((sampleRate * windowDuration).rounded()))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: windowFrames) else {
            throw WhisperWindowsError.unreadableAudio("Не удалось выделить буфер для чтения аудио.")
        }

        var windowRMS: [Float] = []
        windowRMS.reserveCapacity(Int(totalFrames / AVAudioFramePosition(windowFrames)) + 1)

        audioFile.framePosition = 0
        while audioFile.framePosition < totalFrames {
            buffer.frameLength = 0
            try audioFile.read(into: buffer, frameCount: windowFrames)
            let count = Int(buffer.frameLength)
            guard count > 0, let channelData = buffer.floatChannelData?[0] else { break }
            var sumSq: Float = 0
            for i in 0..<count {
                let s = channelData[i]
                sumSq += s * s
            }
            windowRMS.append(sqrt(sumSq / Float(count)))
        }

        let n = windowRMS.count
        guard n > 0 else {
            return AudioScanResult(totalDurationSeconds: totalDuration, slices: [])
        }

        // Adaptive threshold calibrated from the recording's noise floor (median p50 RMS)
        let sortedRMS = windowRMS.sorted()
        let p50 = sortedRMS[sortedRMS.count / 2]
        let rmsThreshold = max(Float(420.0 / 32_768.0), min(Float(1200.0 / 32_768.0), p50 * 1.85))

        let rawActive = windowRMS.map { $0 > rmsThreshold }
        var active = [Bool](repeating: false, count: n)
        for i in 0..<n where rawActive[i] {
            let hasNeighbor = (i > 0 && rawActive[i - 1]) || (i + 1 < n && rawActive[i + 1])
            if hasNeighbor || windowRMS[i] > rmsThreshold * 1.35 {
                active[i] = true
            }
        }
        guard active.contains(true) else {
            return AudioScanResult(totalDurationSeconds: totalDuration, slices: [])
        }

        // Bridge silence gaps shorter than 1.0s (10 windows)
        let maxGapWindows = 10
        var idx = 0
        while idx < n {
            if !active[idx] {
                let gapStart = idx
                while idx < n && !active[idx] {
                    idx += 1
                }
                let gapEnd = idx
                if gapStart > 0 && gapEnd < n && (gapEnd - gapStart) <= maxGapWindows {
                    for g in gapStart..<gapEnd {
                        active[g] = true
                    }
                }
            } else {
                idx += 1
            }
        }

        // Pad active spans by 0.3s (3 windows) before and 0.4s (4 windows) after
        let padBefore = 3
        let padAfter = 4
        var padded = active
        for i in 0..<n where active[i] {
            let start = max(0, i - padBefore)
            let end = min(n - 1, i + padAfter)
            for j in start...end {
                padded[j] = true
            }
        }

        // Extract contiguous spans and split long spans (> 75s) at lowest-energy windows
        let maxSliceWindows = 750 // 75s
        let splitSearchStartOffset = 500 // 50s
        var slices: [SpeechSlice] = []

        var i = 0
        while i < n {
            guard padded[i] else {
                i += 1
                continue
            }
            let spanStart = i
            while i < n && padded[i] {
                i += 1
            }
            let spanEnd = i // exclusive

            var curStart = spanStart
            while curStart < spanEnd {
                let remaining = spanEnd - curStart
                let curEnd: Int
                if remaining <= maxSliceWindows {
                    curEnd = spanEnd
                } else {
                    let searchLo = curStart + splitSearchStartOffset
                    let searchHi = min(spanEnd - 1, curStart + maxSliceWindows)
                    var bestSplit = curStart + maxSliceWindows
                    var lowestRMS = Float.greatestFiniteMagnitude
                    if searchLo < searchHi {
                        for k in searchLo...searchHi {
                            if windowRMS[k] < lowestRMS {
                                lowestRMS = windowRMS[k]
                                bestSplit = k + 1
                            }
                        }
                    }
                    curEnd = bestSplit
                }

                let startFrame = min(totalFrames, AVAudioFramePosition(curStart) * AVAudioFramePosition(windowFrames))
                let endFrame = min(totalFrames, AVAudioFramePosition(curEnd) * AVAudioFramePosition(windowFrames))
                if endFrame > startFrame {
                    let startSec = Double(startFrame) / sampleRate
                    let durSec = Double(endFrame - startFrame) / sampleRate
                    let peakRMS = windowRMS[curStart..<curEnd].max() ?? 0
                    if durSec >= 0.3 && !(durSec < 0.8 && peakRMS <= rmsThreshold * 1.25) {
                        slices.append(
                            SpeechSlice(
                                startFrame: startFrame,
                                endFrame: endFrame,
                                startSeconds: startSec,
                                durationSeconds: durSec
                            )
                        )
                    }
                }
                curStart = curEnd
            }
        }

        return AudioScanResult(totalDurationSeconds: totalDuration, slices: slices)
    }

    private static func exportSliceToTempWAV(sourceURL: URL, slice: SpeechSlice) throws -> URL {
        let srcFile = try AVAudioFile(forReading: sourceURL)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetype-slice-\(UUID().uuidString).wav")

        let wavSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let outFile = try? AVAudioFile(
            forWriting: tempURL,
            settings: wavSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        ) else {
            throw WhisperWindowsError.unreadableAudio("Не удалось создать временный WAV-срез.")
        }

        let chunkSize: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: srcFile.processingFormat, frameCapacity: chunkSize) else {
            throw WhisperWindowsError.unreadableAudio("Не удалось выделить буфер для нарезки WAV.")
        }

        srcFile.framePosition = slice.startFrame
        var framesLeft = slice.endFrame - slice.startFrame

        while framesLeft > 0 {
            let toRead = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), framesLeft))
            buffer.frameLength = 0
            try srcFile.read(into: buffer, frameCount: toRead)
            let readCount = AVAudioFramePosition(buffer.frameLength)
            guard readCount > 0 else { break }
            try outFile.write(from: buffer)
            framesLeft -= readCount
        }

        return tempURL
    }

    // MARK: - Inference HTTP Request

    private struct VerboseResponse: Decodable {
        struct Segment: Decodable {
            let id: Int?
            let text: String?
            let start: Double?
            let end: Double?
            let avg_logprob: Double?
            let no_speech_prob: Double?
        }

        let text: String?
        let language: String?
        let duration: Double?
        let segments: [Segment]?
    }

    private func transcribeSlice(
        sourceURL: URL,
        slice: SpeechSlice,
        speaker: Int,
        baseURL: URL,
        prompt: String,
        onUploadProgress: (@Sendable (Int64, Int64, Bool) -> Void)? = nil
    ) async throws -> [GapiTranscription.Segment] {
        let tempURL = try await Task.detached(priority: .userInitiated) {
            try Self.exportSliceToTempWAV(sourceURL: sourceURL, slice: slice)
        }.value
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let boundary = "voicetype-whisper-\(UUID().uuidString)"
        let wavData = try Data(contentsOf: tempURL)
        let body = Self.buildMultipartBody(
            wavData: wavData,
            filename: tempURL.lastPathComponent,
            boundary: boundary,
            prompt: prompt
        )
        let bodySize = Int64(body.count)

        var request = URLRequest(url: baseURL.appendingPathComponent("inference"))
        request.httpMethod = "POST"
        request.timeoutInterval = max(90.0, slice.durationSeconds * 2.5 + 45.0)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        onUploadProgress?(0, bodySize, false)

        let delegate = UploadProgressDelegate(fallbackTotalBytes: bodySize) { sent, expected, isDone in
            onUploadProgress?(sent, expected, isDone)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.upload(for: request, from: body, delegate: delegate)
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch let error as URLError {
            throw WhisperWindowsError.serverUnavailable(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WhisperWindowsError.serverUnavailable("Пустой ответ от сервера")
        }
        guard http.statusCode == 200 else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw WhisperWindowsError.serverError(http.statusCode, bodyText)
        }

        let decoded = try JSONDecoder().decode(VerboseResponse.self, from: data)
        if let segments = decoded.segments, !segments.isEmpty {
            return segments.compactMap { seg -> GapiTranscription.Segment? in
                let rawText = (seg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawText.isEmpty else { return nil }
                if let noSpeech = seg.no_speech_prob, let logProb = seg.avg_logprob,
                   noSpeech > 0.85 && logProb < -1.0 {
                    return nil
                }
                guard let cleanedText = Self.sanitizeSegmentText(rawText, avgLogProb: seg.avg_logprob) else {
                    return nil
                }

                let absStart = slice.startSeconds + (seg.start ?? 0)
                let absEnd = slice.startSeconds + (seg.end ?? seg.start ?? 0)
                return GapiTranscription.Segment(
                    index: 0,
                    start: absStart,
                    end: max(absStart, absEnd),
                    speaker: speaker,
                    text: cleanedText,
                    languageCode: "ru",
                    languageConfidence: nil
                )
            }
        }

        let fallbackRaw = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fallbackText = Self.sanitizeSegmentText(fallbackRaw, avgLogProb: nil) else {
            return []
        }
        return [
            GapiTranscription.Segment(
                index: 0,
                start: slice.startSeconds,
                end: slice.startSeconds + slice.durationSeconds,
                speaker: speaker,
                text: fallbackText,
                languageCode: "ru",
                languageConfidence: nil
            )
        ]
    }

    private static func buildPrompt(customTerms: [String]) -> String {
        var terms = defaultVocabularyPrompt
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for term in customTerms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                terms.append(trimmed)
            }
        }
        return "Коллеги, добрый день! Обсуждаем задачи по \(terms.joined(separator: ", "))."
    }

    private static func buildMultipartBody(
        wavData: Data,
        filename: String,
        boundary: String,
        prompt: String
    ) -> Data {
        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        appendField("language", "ru")
        appendField("response_format", "verbose_json")
        appendField("temperature", "0.0")
        appendField("temperature_inc", "0.2")
        appendField("no_speech_thold", "0.6")
        appendField("prompt", prompt)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: - Post-Processing

    private static let hallucinationMarkers: [String] = [
        "субтитры",
        "редактор субтитров",
        "dimatorzok",
        "dima torzok",
        "дубровск",
        "продолжение следует",
        "пределение следует",
        "в следующей серии",
        "подписывайтесь",
        "спасибо за просмотр",
        "поставить на русском языке",
        "запятыми, точками",
        "вопросительными знаками",
        "обсуждаем задачи по korzinka"
    ]

    private static func isKnownHallucination(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if lower.isEmpty { return true }
        return hallucinationMarkers.contains(where: { lower.contains($0) })
    }

    private static func sanitizeSegmentText(_ raw: String, avgLogProb: Double?) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        // Strip prompt prefix leaks ("Термин:", "Термина:", "Термины:", "Термин,")
        if let prefixRx = try? NSRegularExpression(pattern: #"(?i)(?:^|(?<=\s))термин[аы]?[:,]\s*"#) {
            s = prefixRx.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !s.isEmpty, !isKnownHallucination(s) else { return nil }

        // Split into sentence chunks and collapse consecutive duplicate loops
        if let sentRx = try? NSRegularExpression(pattern: #"[^.!?]+(?:[.!?]+|$)"#) {
            let ns = s as NSString
            let matches = sentRx.matches(in: s, range: NSRange(location: 0, length: ns.length))
            var sentences: [String] = []
            for m in matches {
                let part = ns.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty {
                    sentences.append(part)
                }
            }

            if sentences.count >= 2 {
                var deduped: [String] = []
                var maxConsecutiveRun = 1
                var currentRun = 1
                var lastNorm = ""

                for sent in sentences {
                    let norm = sent.lowercased()
                        .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
                    guard !norm.isEmpty else { continue }
                    if norm == lastNorm {
                        currentRun += 1
                        maxConsecutiveRun = max(maxConsecutiveRun, currentRun)
                    } else {
                        currentRun = 1
                        lastNorm = norm
                        deduped.append(sent)
                    }
                }

                // Drop entire segment if it is a low-confidence repetition loop (>= 3 repeats)
                if maxConsecutiveRun >= 3, (avgLogProb ?? 0) < -0.55 {
                    return nil
                }
                s = deduped.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !s.isEmpty, !isKnownHallucination(s) else { return nil }
        return s
    }

    private static func mergeAndCleanSegments(_ segments: [GapiTranscription.Segment]) -> [GapiTranscription.Segment] {
        let sorted = segments.sorted { a, b in
            let sa = a.start ?? 0
            let sb = b.start ?? 0
            if sa != sb { return sa < sb }
            return (a.speaker ?? 0) < (b.speaker ?? 0)
        }

        var merged: [GapiTranscription.Segment] = []
        for seg in sorted {
            let clean = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }

            if let last = merged.last,
               last.speaker == seg.speaker,
               last.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == clean.lowercased() {
                continue
            }

            if let last = merged.last,
               last.speaker == seg.speaker,
               let lastEnd = last.end,
               let curStart = seg.start,
               (curStart - lastEnd) < 0.6,
               (last.text.count + clean.count + 1) < 260 {
                let joinedText = last.text + " " + clean
                merged[merged.count - 1] = GapiTranscription.Segment(
                    index: last.index,
                    start: last.start,
                    end: max(lastEnd, seg.end ?? curStart),
                    speaker: last.speaker,
                    text: joinedText,
                    languageCode: last.languageCode,
                    languageConfidence: last.languageConfidence
                )
            } else {
                merged.append(
                    GapiTranscription.Segment(
                        index: merged.count,
                        start: seg.start,
                        end: seg.end,
                        speaker: seg.speaker,
                        text: clean,
                        languageCode: seg.languageCode,
                        languageConfidence: seg.languageConfidence
                    )
                )
            }
        }

        return merged.enumerated().map { idx, seg in
            GapiTranscription.Segment(
                index: idx,
                start: seg.start,
                end: seg.end,
                speaker: seg.speaker,
                text: seg.text,
                languageCode: seg.languageCode,
                languageConfidence: seg.languageConfidence
            )
        }
    }
}
