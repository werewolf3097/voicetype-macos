import SwiftUI

struct RecordingIndicatorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let status: RecordingStatus

    var body: some View {
        let theme = ClaudeTheme(scheme: colorScheme)
        HStack(spacing: 10) {
            icon(theme: theme)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.surface.opacity(0.96), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 12, y: 4)
        .fixedSize()
    }

    @ViewBuilder
    private func icon(theme: ClaudeTheme) -> some View {
        switch status {
        case .recording:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(theme.danger)
        case .transcribing, .cleaning:
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(theme.warning)
        case .idle:
            EmptyView()
        }
    }

    private var title: String {
        switch status {
        case .idle: return ""
        case .recording: return "Слушаю…"
        case .transcribing: return "Распознаю речь…"
        case .cleaning: return "Обрабатываю текст…"
        case .error(let message): return message
        }
    }
}
