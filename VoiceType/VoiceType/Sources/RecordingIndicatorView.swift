import SwiftUI

enum RecordingStatus: Equatable {
    case idle
    case recording
    case transcribing
    case cleaning
    case error(String)
}

enum RecordingIndicatorState: Equatable {
    case hidden
    case recording
    case transcribing(targetApp: String?)
    case cleaning(targetApp: String?)
    case inserted(targetApp: String?)
    case clipboardOnly(targetApp: String?)
    case error(String)
}

@MainActor
final class RecordingIndicatorModel: ObservableObject {
    @Published var state: RecordingIndicatorState = .hidden
    @Published var audioLevel: CGFloat = 0
    @Published var levelSamples: [CGFloat] = Array(repeating: 0.08, count: 18)
    @Published var processingLook: ProcessingLook = .flow

    func pushLevel(_ level: Float) {
        let clamped = CGFloat(min(max(level, 0), 1))
        audioLevel = clamped
        var updated = levelSamples
        if !updated.isEmpty {
            updated.removeFirst()
        }
        updated.append(max(0.08, clamped))
        levelSamples = updated
    }

    func resetLevels() {
        audioLevel = 0
        levelSamples = Array(repeating: 0.08, count: 18)
    }
}

struct RecordingIndicatorView: View {
    @ObservedObject var model: RecordingIndicatorModel
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperDepth) private var depth
    @Environment(\.paperFontPreset) private var fontPreset
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let fonts = PaperFonts(preset: fontPreset)
        Group {
            switch model.state {
            case .hidden:
                EmptyView()

            case .recording:
                VoiceLevelWaveView(
                    level: model.audioLevel,
                    samples: model.levelSamples,
                    reduceMotion: reduceMotion
                )
                .frame(width: 80, height: 14)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(capsuleBackground)
                .overlay(capsuleBorder)
                .shadow(color: shadowColor, radius: 10, y: 4)
                .accessibilityLabel("Идёт запись голоса")

            case .transcribing(let targetApp):
                statusCapsule(
                    icon: {
                        ProcessingLookView(
                            look: model.processingLook,
                            tint: theme.inkColor,
                            reduceMotion: reduceMotion
                        )
                    },
                    text: "Распознаю…",
                    targetApp: targetApp,
                    textColor: theme.inkColor,
                    fonts: fonts
                )

            case .cleaning(let targetApp):
                statusCapsule(
                    icon: {
                        ProcessingLookView(
                            look: model.processingLook,
                            tint: theme.inkColor,
                            reduceMotion: reduceMotion
                        )
                    },
                    text: "Привожу в порядок…",
                    targetApp: targetApp,
                    textColor: theme.inkColor,
                    fonts: fonts
                )

            case .inserted(let targetApp):
                let message = targetApp.map { "Вставлено в \($0)" } ?? "Вставлено"
                statusCapsule(
                    icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(theme.successColor)
                    },
                    text: message,
                    targetApp: nil,
                    textColor: theme.inkColor,
                    fonts: fonts
                )

            case .clipboardOnly(let targetApp):
                statusCapsule(
                    icon: {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme.clipboardWarningColor)
                    },
                    text: "Не вставилось: текст в буфере, нажмите ⌘V",
                    targetApp: targetApp,
                    textColor: theme.inkColor,
                    fonts: fonts
                )

            case .error(let message):
                statusCapsule(
                    icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(theme.errorColor)
                    },
                    text: message,
                    targetApp: nil,
                    textColor: theme.inkColor,
                    fonts: fonts
                )
            }
        }
        .fixedSize()
    }

    private func statusCapsule<Icon: View>(
        @ViewBuilder icon: () -> Icon,
        text: String,
        targetApp: String?,
        textColor: Color,
        fonts: PaperFonts
    ) -> some View {
        HStack(spacing: 8) {
            icon()
            Text(text)
                .font(fonts.captionMedium)
                .foregroundStyle(textColor)
                .lineLimit(1)
            if let targetApp, !targetApp.isEmpty {
                Text("→ \(targetApp)")
                    .font(fonts.caption)
                    .foregroundStyle(theme.secondaryInkColor)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(capsuleBackground)
        .overlay(capsuleBorder)
        .shadow(color: shadowColor, radius: 12, y: 4)
    }

    private var capsuleBackground: some View {
        Capsule(style: .continuous)
            .fill(theme.surfaceColor.opacity(reduceTransparency ? 1.0 : 0.95))
    }

    private var capsuleBorder: some View {
        Capsule(style: .continuous)
            .strokeBorder(theme.borderColor, lineWidth: PaperTokens.hairline)
    }

    private var shadowColor: Color {
        theme.shadowRGB.color.opacity((theme.isDark ? 0.55 : 0.22) * (0.4 + 0.6 * min(1, max(0, depth))))
    }
}

// MARK: - Live Voice Waveform (80x14 pt)

private struct VoiceLevelWaveView: View {
    let level: CGFloat
    let samples: [CGFloat]
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(PaperTokens.recordingRed.opacity(0.22))
                    Capsule()
                        .fill(PaperTokens.recordingRed)
                        .frame(width: max(6, geo.size.width * max(0.08, level)))
                }
            }
        } else {
            Canvas { context, size in
                let count = max(1, samples.count)
                let spacing: CGFloat = 2
                let totalSpacing = spacing * CGFloat(count - 1)
                let barWidth = max(1.5, (size.width - totalSpacing) / CGFloat(count))
                let midY = size.height / 2

                for (index, sample) in samples.enumerated() {
                    let centerBias = 1.0 - abs(CGFloat(index) - CGFloat(count - 1) / 2.0) / CGFloat(max(1, count)) * 0.35
                    let amplitude = min(1.0, max(0.14, sample * centerBias))
                    let barHeight = max(2.5, size.height * amplitude)
                    let x = CGFloat(index) * (barWidth + spacing)
                    let rect = CGRect(
                        x: x,
                        y: midY - barHeight / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                    context.fill(path, with: .color(PaperTokens.recordingRed.opacity(0.35)))
                    context.fill(path, with: .color(PaperTokens.recordingRed))
                }
            }
            .shadow(color: PaperTokens.recordingRed.opacity(0.45), radius: 3)
        }
    }
}

// MARK: - Processing Animations (flow / pulse / sweep)

private struct ProcessingLookView: View {
    let look: ProcessingLook
    let tint: Color
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Circle()
                .fill(tint.opacity(0.75))
                .frame(width: 7, height: 7)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                switch look {
                case .flow:
                    HStack(spacing: 2.5) {
                        ForEach(0..<4, id: \.self) { idx in
                            let phase = sin(t * 6.0 - Double(idx) * 0.9) * 0.5 + 0.5
                            RoundedRectangle(cornerRadius: 1)
                                .fill(tint.opacity(0.45 + 0.55 * phase))
                                .frame(width: 2.2, height: 4 + 7 * phase)
                        }
                    }
                    .frame(width: 18, height: 12)

                case .pulse:
                    let phase = sin(t * 4.5) * 0.5 + 0.5
                    Circle()
                        .fill(tint.opacity(0.4 + 0.6 * phase))
                        .frame(width: 6 + 3 * phase, height: 6 + 3 * phase)
                        .frame(width: 12, height: 12)

                case .sweep:
                    let phase = (t * 1.4).truncatingRemainder(dividingBy: 1.0)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(tint.opacity(0.18))
                            .frame(width: 22, height: 3.5)
                        Capsule()
                            .fill(tint)
                            .frame(width: 8, height: 3.5)
                            .offset(x: 14 * phase)
                    }
                    .frame(width: 22, height: 12)
                }
            }
        }
    }
}
