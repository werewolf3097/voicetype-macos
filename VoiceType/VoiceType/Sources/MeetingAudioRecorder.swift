import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

struct MeetingRecordingOutput {
    let micFileURL: URL
    let sysFileURL: URL?
    let stereoParties: Bool

    var fileURL: URL { micFileURL }
}

final class MeetingAudioRecorder: NSObject {
    private var micRecorder: AVAudioRecorder?
    private var scStream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    private var sysCaptureTask: Task<Void, Never>?
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

        let micURL = directory.appendingPathComponent("mic.wav")
        let sysURL = directory.appendingPathComponent("sys.wav")
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
        let hostStartSeconds = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        self.micRecorder = recorder

        if source == .micAndSystem {
            sysCaptureTask?.cancel()
            sysCaptureTask = Task { [weak self] in
                await self?.startSystemAudioCapture(to: sysURL, hostStartSeconds: hostStartSeconds)
            }
        }
    }

    private func startSystemAudioCapture(to sysURL: URL, hostStartSeconds: Double) async {
        do {
            try Task.checkCancellation()
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
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

            let output = try SystemAudioStreamOutput(outputURL: sysURL, hostStartSeconds: hostStartSeconds)
            let stream = SCStream(filter: filter, configuration: config, delegate: nil)
            try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "uz.gapi.voicetype.sysaudio"))
            try await stream.startCapture()

            if Task.isCancelled {
                try? await stream.stopCapture()
                output.close()
                return
            }

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

        if let task = sysCaptureTask {
            task.cancel()
            await task.value
            sysCaptureTask = nil
        }

        if let stream = scStream {
            try? await stream.stopCapture()
            scStream = nil
        }
        let capturedSysSamples = streamOutput?.totalSamplesWritten ?? 0
        streamOutput?.close()
        streamOutput = nil
        systemAudioActive = false

        guard let micURL = micFileURL,
              FileManager.default.fileExists(atPath: micURL.path) else {
            return nil
        }

        if requestedSource == .micAndSystem,
           let sysURL = sysFileURL,
           capturedSysSamples > 1_600,
           FileManager.default.fileExists(atPath: sysURL.path) {
            return MeetingRecordingOutput(micFileURL: micURL, sysFileURL: sysURL, stereoParties: true)
        }

        if let sysURL = sysFileURL {
            try? FileManager.default.removeItem(at: sysURL)
        }
        return MeetingRecordingOutput(micFileURL: micURL, sysFileURL: nil, stereoParties: false)
    }

    func cancel() async {
        micRecorder?.stop()
        micRecorder = nil
        if let task = sysCaptureTask {
            task.cancel()
            await task.value
            sysCaptureTask = nil
        }
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

    /// Streaming combination of two 16kHz 1-channel WAV files into a 16kHz 2-channel stereo WAV file
    /// where Left (Channel 0) = Microphone ("Вы") and Right (Channel 1) = System Audio ("Собеседники").
    static func combineMonoWAVsIntoStereo(leftURL: URL, rightURL: URL, outputURL: URL) -> Bool {
        guard let leftFile = try? AVAudioFile(forReading: leftURL),
              let rightFile = try? AVAudioFile(forReading: rightURL) else {
            return false
        }

        let totalFrames = max(leftFile.length, rightFile.length)
        guard totalFrames > 0 else { return false }

        let stereoSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        guard let stereoFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 2,
            interleaved: true
        ),
        let outFile = try? AVAudioFile(
            forWriting: outputURL,
            settings: stereoSettings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        ) else {
            return false
        }

        let chunkSize: AVAudioFrameCount = 65_536
        guard let leftBuf = AVAudioPCMBuffer(pcmFormat: leftFile.processingFormat, frameCapacity: chunkSize),
              let rightBuf = AVAudioPCMBuffer(pcmFormat: rightFile.processingFormat, frameCapacity: chunkSize),
              let stereoBuf = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: chunkSize),
              let outInt16 = stereoBuf.int16ChannelData?[0] else {
            return false
        }

        while leftFile.framePosition < leftFile.length || rightFile.framePosition < rightFile.length {
            let leftRemaining = max(0, leftFile.length - leftFile.framePosition)
            let rightRemaining = max(0, rightFile.length - rightFile.framePosition)
            let leftToRead = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), leftRemaining))
            let rightToRead = AVAudioFrameCount(min(AVAudioFramePosition(chunkSize), rightRemaining))

            leftBuf.frameLength = 0
            rightBuf.frameLength = 0

            if leftToRead > 0 {
                do {
                    try leftFile.read(into: leftBuf, frameCount: leftToRead)
                } catch {
                    return false
                }
            }
            if rightToRead > 0 {
                do {
                    try rightFile.read(into: rightBuf, frameCount: rightToRead)
                } catch {
                    return false
                }
            }

            let actualLeft = Int(leftBuf.frameLength)
            let actualRight = Int(rightBuf.frameLength)
            let framesInChunk = max(actualLeft, actualRight)
            guard framesInChunk > 0 else { break }

            stereoBuf.frameLength = AVAudioFrameCount(framesInChunk)
            let leftPtr = leftBuf.floatChannelData?[0]
            let rightPtr = rightBuf.floatChannelData?[0]

            for i in 0..<framesInChunk {
                let lSample: Float = i < actualLeft ? (leftPtr?[i] ?? 0) : 0
                let rSample: Float = i < actualRight ? (rightPtr?[i] ?? 0) : 0
                let lClamped = max(-1.0, min(1.0, lSample))
                let rClamped = max(-1.0, min(1.0, rSample))
                outInt16[i * 2] = Int16(lClamped * Float(Int16.max))
                outInt16[i * 2 + 1] = Int16(rClamped * Float(Int16.max))
            }

            do {
                try outFile.write(from: stereoBuf)
            } catch {
                return false
            }
        }

        return true
    }
}

private final class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private var audioFile: AVAudioFile?
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private let hostStartSeconds: Double
    private var firstPTS: Double?
    private var useRelativePTS: Bool = false
    private let silenceChunkFrames = 16_000
    private let silenceBuffer: AVAudioPCMBuffer?
    private(set) var totalSamplesWritten: Int = 0

    init(outputURL: URL, hostStartSeconds: Double) throws {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw NSError(domain: "SystemAudioStreamOutput", code: 1)
        }
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        self.targetFormat = fmt
        self.hostStartSeconds = hostStartSeconds
        self.audioFile = try AVAudioFile(
            forWriting: outputURL,
            settings: fileSettings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        if let sBuf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(silenceChunkFrames)),
           let ptr = sBuf.int16ChannelData?[0] {
            memset(ptr, 0, silenceChunkFrames * MemoryLayout<Int16>.size)
            sBuf.frameLength = AVAudioFrameCount(silenceChunkFrames)
            self.silenceBuffer = sBuf
        } else {
            self.silenceBuffer = nil
        }
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

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        lock.lock()
        defer { lock.unlock() }
        guard let file = audioFile else { return }

        if pts.isValid && pts.isNumeric {
            let ptsSeconds = pts.seconds
            if firstPTS == nil {
                firstPTS = ptsSeconds
                // If SCStream PTS uses host clock, align against mic start time;
                // otherwise fall back to relative PTS from the first sample.
                if abs(ptsSeconds - hostStartSeconds) > 30.0 {
                    useRelativePTS = true
                }
            }
            let anchor = useRelativePTS ? (firstPTS ?? ptsSeconds) : hostStartSeconds
            let expectedSamples = max(0, Int(((ptsSeconds - anchor) * 16_000.0).rounded()))
            let rawGap = expectedSamples - totalSamplesWritten
            // Cap single-jump gap padding at 6 hours to guard against clock anomalies
            let maxSafeGap = 16_000 * 3600 * 6
            if rawGap > 320 && rawGap < maxSafeGap, let sBuf = silenceBuffer {
                var remaining = rawGap
                while remaining > 0 {
                    let chunk = min(remaining, silenceChunkFrames)
                    sBuf.frameLength = AVAudioFrameCount(chunk)
                    do {
                        try file.write(from: sBuf)
                        totalSamplesWritten += chunk
                    } catch {
                        break
                    }
                    remaining -= chunk
                }
            }
        }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(numSamples)),
              let dst = pcmBuffer.int16ChannelData?[0] else {
            return
        }

        let channels = max(1, Int(asbdPtr.pointee.mChannelsPerFrame))
        let isFloat = (asbdPtr.pointee.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let actualCount: Int

        if isFloat {
            let floatPtr = rawPtr.assumingMemoryBound(to: Float.self)
            let totalFloats = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            actualCount = min(numSamples, totalFloats / channels)
            for i in 0..<actualCount {
                let sample: Float
                if channels == 1 {
                    sample = floatPtr[i]
                } else {
                    var sum: Float = 0
                    for c in 0..<channels {
                        sum += floatPtr[i * channels + c]
                    }
                    sample = sum / Float(channels)
                }
                let clamped = max(-1.0, min(1.0, sample))
                dst[i] = Int16(clamped * Float(Int16.max))
            }
        } else {
            let int16Ptr = rawPtr.assumingMemoryBound(to: Int16.self)
            let totalInts = Int(buf.mDataByteSize) / MemoryLayout<Int16>.size
            actualCount = min(numSamples, totalInts / channels)
            for i in 0..<actualCount {
                if channels == 1 {
                    dst[i] = int16Ptr[i]
                } else {
                    var sum = 0
                    for c in 0..<channels {
                        sum += Int(int16Ptr[i * channels + c])
                    }
                    dst[i] = Int16(max(Int(Int16.min), min(Int(Int16.max), sum / channels)))
                }
            }
        }

        guard actualCount > 0 else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(actualCount)

        do {
            try file.write(from: pcmBuffer)
            totalSamplesWritten += actualCount
        } catch {
            // Ignore single-buffer write glitches
        }
    }
}
