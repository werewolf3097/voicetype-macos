import AVFoundation
import Foundation

enum AudioRecorderError: Error {
    case alreadyRecording
    case notRecording
    case failedToStart
}

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private var meterTimer: Timer?
    private var smoothedLevel: Float = 0

    var onAudioLevel: ((Float) -> Void)?
    var isRecording: Bool { recorder?.isRecording ?? false }

    func start() throws {
        guard recorder == nil else { throw AudioRecorderError.alreadyRecording }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetype-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        newRecorder.isMeteringEnabled = true
        guard newRecorder.record() else {
            throw AudioRecorderError.failedToStart
        }
        recorder = newRecorder
        fileURL = url
        smoothedLevel = 0
        startMetering()
    }

    @discardableResult
    func stop() -> URL? {
        stopMetering()
        guard let recorder else { return nil }
        recorder.stop()
        self.recorder = nil
        return fileURL
    }

    func cancel() {
        stopMetering()
        recorder?.stop()
        recorder = nil
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    private func startMetering() {
        stopMetering()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let avgDb = recorder.averagePower(forChannel: 0)
            let normalized = Self.normalizeDecibels(avgDb)
            // Плавное сглаживание: быстрый отклик на пик, мягкое затухание
            if normalized > self.smoothedLevel {
                self.smoothedLevel = self.smoothedLevel * 0.35 + normalized * 0.65
            } else {
                self.smoothedLevel = self.smoothedLevel * 0.72 + normalized * 0.28
            }
            self.onAudioLevel?(self.smoothedLevel)
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
        smoothedLevel = 0
        onAudioLevel?(0)
    }

    static func normalizeDecibels(_ db: Float) -> Float {
        guard db.isFinite else { return 0 }
        let floorDb: Float = -52.0
        let ceilingDb: Float = -4.0
        let clamped = min(max((db - floorDb) / (ceilingDb - floorDb), 0), 1)
        return powf(clamped, 1.35)
    }
}
