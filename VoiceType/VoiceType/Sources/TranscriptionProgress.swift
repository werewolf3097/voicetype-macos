import Foundation
import os

struct MeetingTranscriptionProgress: Equatable, Sendable {
    enum Stage: Equatable, Sendable {
        case preparingAudio
        case uploading(bytesSent: Int64, totalBytes: Int64, chunkIndex: Int? = nil, totalChunks: Int? = nil)
        case waitingInServerQueue
        case transcribing(processedSeconds: Double, totalSeconds: Double?, chunkIndex: Int? = nil, totalChunks: Int? = nil)
    }

    let stage: Stage
    let overallFraction: Double
    let uploadPhaseEndFraction: Double?
    let uploadCompleted: Bool
    let processedSeconds: Double
    let totalSeconds: Double?

    init(
        stage: Stage,
        overallFraction: Double,
        uploadPhaseEndFraction: Double?,
        uploadCompleted: Bool,
        processedSeconds: Double,
        totalSeconds: Double?
    ) {
        self.stage = stage
        self.overallFraction = Self.clamp(overallFraction)
        self.uploadPhaseEndFraction = uploadPhaseEndFraction.map(Self.clamp)
        self.uploadCompleted = uploadCompleted
        self.processedSeconds = max(0, processedSeconds.isFinite ? processedSeconds : 0)
        if let totalSeconds, totalSeconds.isFinite, totalSeconds > 0 {
            self.totalSeconds = totalSeconds
        } else {
            self.totalSeconds = nil
        }
    }

    static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1.0, max(0.0, value))
    }
}

final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    private struct ThrottleState: Sendable {
        var lastReportTime: TimeInterval = 0
        var didReportCompletion = false
    }

    private let fallbackTotalBytes: Int64
    private let minInterval: TimeInterval
    private let state = OSAllocatedUnfairLock(initialState: ThrottleState())
    private let onProgress: @Sendable (Int64, Int64, Bool) -> Void

    init(
        fallbackTotalBytes: Int64 = 0,
        minInterval: TimeInterval = 0.08,
        onProgress: @escaping @Sendable (Int64, Int64, Bool) -> Void
    ) {
        self.fallbackTotalBytes = fallbackTotalBytes
        self.minInterval = minInterval
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let expected = totalBytesExpectedToSend > 0 ? totalBytesExpectedToSend : fallbackTotalBytes
        let isUploadDone = expected > 0 && totalBytesSent >= expected
        let now = ProcessInfo.processInfo.systemUptime

        let shouldEmit = state.withLock { s -> Bool in
            if isUploadDone {
                guard !s.didReportCompletion else { return false }
                s.didReportCompletion = true
                s.lastReportTime = now
                return true
            }
            if now - s.lastReportTime >= minInterval {
                s.lastReportTime = now
                return true
            }
            return false
        }

        if shouldEmit {
            onProgress(totalBytesSent, expected, isUploadDone)
        }
    }
}
