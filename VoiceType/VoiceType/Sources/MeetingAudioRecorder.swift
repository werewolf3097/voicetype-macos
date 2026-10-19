import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

struct MeetingRecordingOutput {
    let fileURL: URL
    let stereoParties: Bool
}

final class MeetingAudioRecorder: NSObject {
    private var micRecorder: AVAudioRecorder?
    private var scStream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    private var activeDirectory: URL?
    private var micFileURL: URL?
    private var sysFileURL: URL?
    private var requestedSource: MeetingAudioSource = .micAndSystem
    private(set) var systemAudioActive: Bool = false

    func start(in directory: URL, source: MeetingAudioSource) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        activeDirectory = directory
        requestedSource = source
        systemAudioActive = false

        let micURL = directory.appendingPathComponent("mic_raw.wav")
        let sysURL = directory.appendingPathComponent("sys_raw.wav")
        try? FileManager.default.removeItem(at: micURL)
        try? FileManager.default.removeItem(at: sysURL)
        self.micFileURL = micURL
        self.sysFileURL = sysURL

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: micURL, settings: settings)
        guard recorder.record() else {
            throw NSError(
                domain: "MeetingAudioRecorder",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Не удалось запустить запись с микрофона."]
            )
        }
        self.micRecorder = recorder

        if source == .micAndSystem {
            Task { [weak self] in
                await self?.startSystemAudioCapture(to: sysURL)
            }
        }
    }

    private func startSystemAudioCapture(to sysURL: URL) async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 16_000
            config.channelCount = 1
            // Minimize video overhead since we only care about audio
            config.width = 2
            config.height = 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

            let output = try SystemAudioStreamOutput(outputURL: sysURL)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "uz.gapi.voicetype.sysaudio"))
            try await stream.startCapture()

            await MainActor.run {
                self.streamOutput = output
                self.scStream = stream
                self.systemAudioActive = true
            }
        } catch {
            // Graceful fallback to microphone-only if Screen/Audio capture is denied or unavailable
            await MainActor.run {
                self.systemAudioActive = false
            }
        }
    }

    func stop() async -> MeetingRecordingOutput? {
        micRecorder?.stop()
        micRecorder = nil

        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
        }
        let capturedSysSamples = streamOutput?.totalSamplesWritten ?? 0
        streamOutput?.close()
        streamOutput = nil
        systemAudioActive = false

        guard let dir = activeDirectory, let micURL = micFileURL else { return nil }
        let finalURL = dir.appendingPathComponent("recording.wav")
        try? FileManager.default.removeItem(at: finalURL)

        if requestedSource == .micAndSystem,
           let sysURL = sysFileURL,
           capturedSysSamples > 1_600,
           FileManager.default.fileExists(atPath: sysURL.path),
           Self.combineMonoWAVsIntoStereo(leftURL: micURL, rightURL: sysURL, outputURL: finalURL) {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: sysURL)
            return MeetingRecordingOutput(fileURL: finalURL, stereoParties: true)
        }

        if let sysURL = sysFileURL {
            try? FileManager.default.removeItem(at: sysURL)
        }
        do {
            if FileManager.default.fileExists(atPath: micURL.path) {
                try FileManager.default.moveItem(at: micURL, to: finalURL)
                return MeetingRecordingOutput(fileURL: finalURL, stereoParties: false)
            }
        } catch {
            return MeetingRecordingOutput(fileURL: micURL, stereoParties: false)
        }
        return nil
    }

    func cancel() async {
        micRecorder?.stop()
        micRecorder = nil
        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
        }
        streamOutput?.close()
        streamOutput = nil
        systemAudioActive = false

        if let micURL = micFileURL {
            try? FileManager.default.removeItem(at: micURL)
        }
        if let sysURL = sysFileURL {
            try? FileManager.default.removeItem(at: sysURL)
        }
    }

    /// Combines two 16kHz 1-channel audio files into a 16kHz 2-channel stereo WAV file
    /// where Left (Channel 0) = Microphone ("Вы") and Right (Channel 1) = System Audio ("Собеседник").
    private static func combineMonoWAVsIntoStereo(leftURL: URL, rightURL: URL, outputURL: URL) -> Bool {
        guard let leftFile = try? AVAudioFile(forReading: leftURL),
              let rightFile = try? AVAudioFile(forReading: rightURL) else {
            return false
        }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ),
        let stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 2,
            interleaved: true
        ) else {
            return false
        }

        let leftFrames = AVAudioFrameCount(leftFile.length)
        let rightFrames = AVAudioFrameCount(rightFile.length)
        let totalFrames = max(leftFrames, rightFrames)
        guard totalFrames > 0 else { return false }

        guard let leftBuf = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: max(1, leftFrames)),
              let rightBuf = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: max(1, rightFrames)) else {
            return false
        }

        if leftFrames > 0 {
            try? leftFile.read(into: leftBuf)
        }
        if rightFrames > 0 {
            try? rightFile.read(into: rightBuf)
        }

        guard let outFile = try? AVAudioFile(
            forWriting: outputURL,
            settings: stereoFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        ),
        let stereoBuf = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: totalFrames),
        let outInt16 = stereoBuf.int16ChannelData?[0] else {
            return false
        }

        stereoBuf.frameLength = totalFrames
        let leftPtr = leftBuf.floatChannelData?[0]
        let rightPtr = rightBuf.floatChannelData?[0]
        let actualLeft = Int(leftBuf.frameLength)
        let actualRight = Int(rightBuf.frameLength)

        for i in 0..<Int(totalFrames) {
            let lSample: Float = i < actualLeft ? (leftPtr?[i] ?? 0) : 0
            let rSample: Float = i < actualRight ? (rightPtr?[i] ?? 0) : 0
            let lClamped = max(-1.0, min(1.0, lSample))
            let rClamped = max(-1.0, min(1.0, rSample))
            outInt16[i * 2] = Int16(lClamped * Float(Int16.max))
            outInt16[i * 2 + 1] = Int16(rClamped * Float(Int16.max))
        }

        do {
            try outFile.write(from: stereoBuf)
            return true
        } catch {
            return false
        }
    }
}

private final class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private var audioFile: AVAudioFile?
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private(set) var totalSamplesWritten: Int = 0

    init(outputURL: URL) throws {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "SystemAudioStreamOutput", code: 1)
        }
        self.targetFormat = fmt
        self.audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: fmt.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        super.init()
    }

    func close() {
        lock.lock()
        audioFile = nil
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .audio, sampleBuffer.isValid else { return }
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return
        }

        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
        guard numSamples > 0 else { return }

        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil)
        )

        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return }

        let buf = audioBufferList.mBuffers
        guard let rawPtr = buf.mData else { return }

        lock.lock()
        defer { lock.unlock() }
        guard let file = audioFile,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(numSamples)),
              let dst = pcmBuffer.floatChannelData?[0] else {
            return
        }

        pcmBuffer.frameLength = AVAudioFrameCount(numSamples)
        let isFloat = (asbdPtr.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        if isFloat {
            let floatPtr = rawPtr.assumingMemoryBound(to: Float.self)
            let count = min(numSamples, Int(buf.mDataByteSize) / MemoryLayout<Float>.size)
            for i in 0..<count {
                dst[i] = floatPtr[i]
            }
        } else {
            let int16Ptr = rawPtr.assumingMemoryBound(to: Int16.self)
            let count = min(numSamples, Int(buf.mDataByteSize) / MemoryLayout<Int16>.size)
            for i in 0..<count {
                dst[i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        do {
            try file.write(from: pcmBuffer)
            totalSamplesWritten += numSamples
        } catch {
            // Ignore single-buffer write glitches
        }
    }
}
