import AVFoundation
import Foundation

enum SoundCueKind {
    case startRecording
    case stopRecording
    case inserted
}

/// Воспроизводит короткие тихие сигналы начала, завершения и вставки.
@MainActor
final class SoundCuePlayer {
    static let shared = SoundCuePlayer()

    private var activePlayer: AVAudioPlayer?
    private lazy var startCueData: Data = Self.buildToneWAV(frequencies: [520, 660], duration: 0.075)
    private lazy var stopCueData: Data = Self.buildToneWAV(frequencies: [580, 430], duration: 0.075)
    private lazy var insertedCueData: Data = Self.buildToneWAV(frequencies: [740], duration: 0.055)

    func play(_ kind: SoundCueKind, enabled: Bool, volume: Double) {
        guard enabled else { return }
        let clampedVolume = Float(min(1, max(0, volume)))
        guard clampedVolume > 0.01 else { return }

        let data: Data
        switch kind {
        case .startRecording: data = startCueData
        case .stopRecording: data = stopCueData
        case .inserted: data = insertedCueData
        }

        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = clampedVolume * 0.45
            player.prepareToPlay()
            player.play()
            activePlayer = player
        } catch {
            // Игнорируем ошибки аудиовывода, чтобы никогда не мешать диктовке.
        }
    }

    nonisolated static func buildToneWAV(frequencies: [Double], duration: Double, sampleRate: Int = 44_100) -> Data {
        let totalSamples = max(1, Int(Double(sampleRate) * duration))
        let fadeSamples = max(1, Int(Double(sampleRate) * 0.012))
        var pcm = Data(capacity: totalSamples * 2)

        for i in 0..<totalSamples {
            let progress = Double(i) / Double(totalSamples)
            let freq: Double
            if frequencies.count >= 2 {
                let first = frequencies[0]
                let last = frequencies[frequencies.count - 1]
                freq = first + (last - first) * progress
            } else {
                freq = frequencies.first ?? 600
            }

            let t = Double(i) / Double(sampleRate)
            var env = 1.0
            if i < fadeSamples {
                env = Double(i) / Double(fadeSamples)
            } else if i > totalSamples - fadeSamples {
                env = Double(totalSamples - i) / Double(fadeSamples)
            }
            let sample = sin(2.0 * .pi * freq * t) * env * 0.55
            var intSample = Int16(max(-1.0, min(1.0, sample)) * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &intSample) { pcm.append(contentsOf: $0) }
        }

        return wrapPCMAsWAV(pcmData: pcm, sampleRate: UInt32(sampleRate), channels: 1, bitsPerSample: 16)
    }

    nonisolated private static func wrapPCMAsWAV(pcmData: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let dataSize = UInt32(pcmData.count)
        let chunkSize = 36 + dataSize

        var wav = Data(capacity: 44 + pcmData.count)
        wav.append(contentsOf: "RIFF".utf8)
        wav.appendUInt32LE(chunkSize)
        wav.append(contentsOf: "WAVE".utf8)
        wav.append(contentsOf: "fmt ".utf8)
        wav.appendUInt32LE(16)
        wav.appendUInt16LE(1)
        wav.appendUInt16LE(channels)
        wav.appendUInt32LE(sampleRate)
        wav.appendUInt32LE(byteRate)
        wav.appendUInt16LE(blockAlign)
        wav.appendUInt16LE(bitsPerSample)
        wav.append(contentsOf: "data".utf8)
        wav.appendUInt32LE(dataSize)
        wav.append(pcmData)
        return wav
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }
}
