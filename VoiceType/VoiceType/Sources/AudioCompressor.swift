import AVFoundation
import AudioToolbox
import Foundation
import os

struct CompressedAudio: Equatable, Sendable {
    let data: Data
    let contentType: String
    let codecName: String
    let inputBytes: Int
    let outputBytes: Int
    let encodingMs: Int
}

enum AudioCompressionError: Error, LocalizedError, Equatable {
    case unreadableInput(String)
    case converterCreationFailed(String)
    case encodingFailed(String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .unreadableInput(let detail):
            return "Не удалось прочитать аудиофайл: \(detail)"
        case .converterCreationFailed(let detail):
            return "Не удалось инициализировать аудиокодер: \(detail)"
        case .encodingFailed(let detail):
            return "Ошибка сжатия аудио: \(detail)"
        case .emptyOutput:
            return "Сжатый аудиофайл оказался пустым."
        }
    }
}

protocol AudioCompressing: Sendable {
    func compressForGateway(fileURL: URL) throws -> CompressedAudio
}

/// Кодирует запись диктовки (WAV) в компактный формат для отправки на домашний шлюз:
/// - основной формат: Opus ~24 кбит/с в контейнере CAF через AVAudioConverter;
/// - резервный формат: AAC >= 48 кбит/с (64 кбит/с) в M4A, если Opus-кодер недоступен.
/// В логи пишутся только метаданные (кодек, размеры, время кодирования), без содержимого аудио.
struct AudioCompressor: AudioCompressing {
    static let defaultOpusBitRate = 24_000
    static let minimumAACBitRate = 48_000
    static let defaultAACBitRate = 64_000

    private static let logger = Logger(subsystem: "com.farrukh.voicetype", category: "AudioCompressor")
    private static let opusSupportedSampleRates: Set<Double> = [8_000, 12_000, 16_000, 24_000, 48_000]

    let opusBitRate: Int
    let aacBitRate: Int

    init(
        opusBitRate: Int = AudioCompressor.defaultOpusBitRate,
        aacBitRate: Int = AudioCompressor.defaultAACBitRate
    ) {
        self.opusBitRate = opusBitRate
        self.aacBitRate = max(Self.minimumAACBitRate, aacBitRate)
    }

    func compressForGateway(fileURL: URL) throws -> CompressedAudio {
        let inputBytes = Self.fileSize(at: fileURL)
        let startedAt = CFAbsoluteTimeGetCurrent()

        do {
            let data = try encodeOpusCAF(from: fileURL, bitRate: opusBitRate)
            let encodingMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - startedAt) * 1000).rounded()))
            Self.logger.info(
                "Encoded audio: codec=opus/caf inputBytes=\(inputBytes, privacy: .public) outputBytes=\(data.count, privacy: .public) encodingMs=\(encodingMs, privacy: .public)"
            )
            return CompressedAudio(
                data: data,
                contentType: "audio/x-caf",
                codecName: "opus/caf",
                inputBytes: inputBytes,
                outputBytes: data.count,
                encodingMs: encodingMs
            )
        } catch {
            Self.logger.warning(
                "Opus/CAF encoding failed, falling back to AAC/M4A (\(self.aacBitRate, privacy: .public) bps)"
            )
            let fallbackStart = CFAbsoluteTimeGetCurrent()
            let data = try encodeAACM4A(from: fileURL, bitRate: aacBitRate)
            let encodingMs = max(0, Int(((CFAbsoluteTimeGetCurrent() - fallbackStart) * 1000).rounded()))
            Self.logger.info(
                "Encoded audio: codec=aac/m4a inputBytes=\(inputBytes, privacy: .public) outputBytes=\(data.count, privacy: .public) encodingMs=\(encodingMs, privacy: .public)"
            )
            return CompressedAudio(
                data: data,
                contentType: "audio/mp4",
                codecName: "aac/m4a",
                inputBytes: inputBytes,
                outputBytes: data.count,
                encodingMs: encodingMs
            )
        }
    }

    func encodeOpusCAF(from inputURL: URL, bitRate: Int) throws -> Data {
        let inFile: AVAudioFile
        do {
            inFile = try AVAudioFile(forReading: inputURL)
        } catch {
            throw AudioCompressionError.unreadableInput(error.localizedDescription)
        }

        let inputFormat = inFile.processingFormat
        guard inFile.length > 0 else {
            throw AudioCompressionError.emptyOutput
        }

        let targetSampleRate = Self.opusSupportedSampleRates.contains(inputFormat.sampleRate)
            ? inputFormat.sampleRate
            : 16_000
        let channels = max(1, min(inputFormat.channelCount, 2))
        let framesPerPacket = UInt32(targetSampleRate * 0.02) // 20 ms Opus frame

        var opusASBD = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: framesPerPacket,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        guard let opusFormat = AVAudioFormat(streamDescription: &opusASBD),
              let converter = AVAudioConverter(from: inputFormat, to: opusFormat) else {
            throw AudioCompressionError.converterCreationFailed("Opus \(Int(targetSampleRate)) Hz")
        }
        converter.bitRate = bitRate

        return try writeConvertedFile(
            inputFile: inFile,
            inputFormat: inputFormat,
            converter: converter,
            outputFormat: opusFormat,
            fileType: kAudioFileCAFType,
            fileExtension: "caf",
            fileFlags: [.eraseFile, .dontPageAlignAudioData]
        )
    }

    func encodeAACM4A(from inputURL: URL, bitRate: Int) throws -> Data {
        let safeBitRate = max(Self.minimumAACBitRate, bitRate)
        let inFile: AVAudioFile
        do {
            inFile = try AVAudioFile(forReading: inputURL)
        } catch {
            throw AudioCompressionError.unreadableInput(error.localizedDescription)
        }

        let inputFormat = inFile.processingFormat
        guard inFile.length > 0 else {
            throw AudioCompressionError.emptyOutput
        }

        // AAC at >= 48 kbps works reliably across 16 kHz / 24 kHz / 44.1 kHz / 48 kHz
        let targetSampleRate = inputFormat.sampleRate >= 16_000 ? inputFormat.sampleRate : 16_000
        let channels = max(1, min(inputFormat.channelCount, 2))

        var aacASBD = AudioStreamBasicDescription(
            mSampleRate: targetSampleRate,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 0,
            mReserved: 0
        )

        guard let aacFormat = AVAudioFormat(streamDescription: &aacASBD),
              let converter = AVAudioConverter(from: inputFormat, to: aacFormat) else {
            throw AudioCompressionError.converterCreationFailed("AAC \(Int(targetSampleRate)) Hz")
        }
        converter.bitRate = safeBitRate

        return try writeConvertedFile(
            inputFile: inFile,
            inputFormat: inputFormat,
            converter: converter,
            outputFormat: aacFormat,
            fileType: kAudioFileM4AType,
            fileExtension: "m4a",
            fileFlags: [.eraseFile]
        )
    }

    private func writeConvertedFile(
        inputFile: AVAudioFile,
        inputFormat: AVAudioFormat,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        fileType: AudioFileTypeID,
        fileExtension: String,
        fileFlags: AudioFileFlags
    ) throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voicetype-enc-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var audioFileID: AudioFileID?
        var outASBD = outputFormat.streamDescription.pointee
        let createStatus = AudioFileCreateWithURL(
            tempURL as CFURL,
            fileType,
            &outASBD,
            fileFlags,
            &audioFileID
        )
        guard createStatus == noErr, let audioFile = audioFileID else {
            throw AudioCompressionError.encodingFailed("AudioFileCreateWithURL status=\(createStatus)")
        }

        var closed = false
        defer {
            if !closed {
                AudioFileClose(audioFile)
            }
        }

        if let magicCookie = converter.magicCookie, !magicCookie.isEmpty {
            magicCookie.withUnsafeBytes { rawBuf in
                if let base = rawBuf.baseAddress {
                    AudioFileSetProperty(
                        audioFile,
                        kAudioFilePropertyMagicCookieData,
                        UInt32(magicCookie.count),
                        base
                    )
                }
            }
        }

        let maxPacketSize = max(converter.maximumOutputPacketSize, 1024)
        let packetCapacity: AVAudioPacketCount = 64
        let compressedBuffer = AVAudioCompressedBuffer(
            format: outputFormat,
            packetCapacity: packetCapacity,
            maximumPacketSize: maxPacketSize
        )
        let readChunkFrames: AVAudioFrameCount = 4096
        guard let readBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: readChunkFrames) else {
            throw AudioCompressionError.encodingFailed("Не удалось выделить PCM-буфер")
        }

        var packetOffset: Int64 = 0
        var reachedEOF = false

        while true {
            var conversionError: NSError?
            let status = converter.convert(to: compressedBuffer, error: &conversionError) { _, outStatus in
                if reachedEOF || inputFile.framePosition >= inputFile.length {
                    reachedEOF = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try inputFile.read(into: readBuffer, frameCount: readChunkFrames)
                    if readBuffer.frameLength == 0 {
                        reachedEOF = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    outStatus.pointee = .haveData
                    return readBuffer
                } catch {
                    reachedEOF = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
            }

            if let conversionError {
                throw AudioCompressionError.encodingFailed(conversionError.localizedDescription)
            }

            if compressedBuffer.packetCount > 0 {
                var numPackets = compressedBuffer.packetCount
                let writeStatus = AudioFileWritePackets(
                    audioFile,
                    false,
                    compressedBuffer.byteLength,
                    compressedBuffer.packetDescriptions,
                    packetOffset,
                    &numPackets,
                    compressedBuffer.data
                )
                guard writeStatus == noErr else {
                    throw AudioCompressionError.encodingFailed("AudioFileWritePackets status=\(writeStatus)")
                }
                packetOffset += Int64(numPackets)
            }

            if status == .endOfStream {
                break
            }
            if status == .error {
                throw AudioCompressionError.encodingFailed("AVAudioConverter вернул .error")
            }
            if status == .inputRanDry && compressedBuffer.packetCount == 0 {
                break
            }
        }

        let closeStatus = AudioFileClose(audioFile)
        closed = true
        guard closeStatus == noErr else {
            throw AudioCompressionError.encodingFailed("AudioFileClose status=\(closeStatus)")
        }

        let encodedData = try Data(contentsOf: tempURL)
        guard !encodedData.isEmpty else {
            throw AudioCompressionError.emptyOutput
        }
        return encodedData
    }

    private static func fileSize(at url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? 0
    }
}
