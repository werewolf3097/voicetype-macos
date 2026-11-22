import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

enum AudioRecorderError: Error {
    case alreadyRecording
    case notRecording
    case failedToStart
}

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var engine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private let writeQueue = DispatchQueue(label: "com.farrukh.voicetype.audiorecorder.write")
    private var fileURL: URL?
    private var meterTimer: Timer?
    private var smoothedLevel: Float = 0

    var onAudioLevel: ((Float) -> Void)?
    var isRecording: Bool { (recorder?.isRecording ?? false) || (engine?.isRunning ?? false) }

    func start(deviceID: AudioDeviceID? = nil) throws {
        guard recorder == nil, engine == nil else { throw AudioRecorderError.alreadyRecording }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetype-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        if let deviceID, deviceID != AudioInputDeviceManager.defaultInputDeviceID() {
            do {
                try startEngineRecording(url: url, deviceID: deviceID)
                return
            } catch {
                // Если конкретное устройство недоступно, откатываемся на системный вход.
                stopEngineRecording()
            }
        }

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
        if let recorder {
            recorder.stop()
            self.recorder = nil
            let url = fileURL
            fileURL = nil
            return url
        }
        if engine != nil {
            stopEngineRecording()
            let url = fileURL
            fileURL = nil
            return url
        }
        return nil
    }

    func cancel() {
        stopMetering()
        recorder?.stop()
        recorder = nil
        if engine != nil {
            stopEngineRecording()
        }
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        fileURL = nil
    }

    // MARK: - Targeted Device Recording via AVAudioEngine

    private func startEngineRecording(url: URL, deviceID: AudioDeviceID) throws {
        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        guard let audioUnit = inputNode.audioUnit else {
            throw AudioRecorderError.failedToStart
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioRecorderError.failedToStart
        }

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
              ),
              let audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.failedToStart
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        self.outputFile = file
        self.converter = audioConverter
        self.fileURL = url
        self.smoothedLevel = 0

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.levelFromPCMBuffer(buffer)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.engine != nil else { return }
                self.pushSmoothedLevel(level)
            }
            self.writeQueue.async { [weak self] in
                guard let self, let file = self.outputFile, let conv = self.converter else { return }
                self.convertAndWrite(buffer: buffer, converter: conv, targetFormat: targetFormat, to: file)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        self.engine = audioEngine
    }

    private func stopEngineRecording() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        writeQueue.sync {
            outputFile = nil
            converter = nil
        }
    }

    private func convertAndWrite(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        to file: AVAudioFile
    ) {
        let ratio = targetFormat.sampleRate / max(1, buffer.format.sampleRate)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var provided = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }
        if error == nil, converted.frameLength > 0 {
            try? file.write(from: converted)
        }
    }

    private static func levelFromPCMBuffer(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }
        let samples = channelData[0]
        var sumSquares: Float = 0
        for i in 0..<frameCount {
            let s = samples[i]
            sumSquares += s * s
        }
        let rms = sqrtf(sumSquares / Float(frameCount))
        let db = rms > 0.00001 ? 20.0 * log10f(rms) : -160.0
        return normalizeDecibels(db)
    }

    // MARK: - Metering

    private func startMetering() {
        stopMetering()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.recorder, recorder.isRecording else { return }
            recorder.updateMeters()
            let avgDb = recorder.averagePower(forChannel: 0)
            let normalized = Self.normalizeDecibels(avgDb)
            self.pushSmoothedLevel(normalized)
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func pushSmoothedLevel(_ normalized: Float) {
        if normalized > smoothedLevel {
            smoothedLevel = smoothedLevel * 0.35 + normalized * 0.65
        } else {
            smoothedLevel = smoothedLevel * 0.72 + normalized * 0.28
        }
        onAudioLevel?(smoothedLevel)
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
