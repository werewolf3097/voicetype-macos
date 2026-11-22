import SwiftUI

struct DashboardHomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    @State private var copiedLast = false
    @State private var reinsertedFeedback = false

    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    private var hasRequiredPermissionIssue: Bool {
        !appState.hotkeyActive
            || !appState.microphoneAuthorized
            || (settings.pasteMode == .autoPaste && !appState.accessibilityAuthorized)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PaperPageHeader(
                    "Диктовка",
                    subtitle: "Надиктуйте текст в любом приложении с помощью клавиши.",
                    systemImage: "waveform",
                    tileTint: PaperTokens.dictationBlue
                )

                if case .error(let message) = appState.status {
                    errorBanner(message)
                }

                if hasRequiredPermissionIssue {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(permissionHeadline)
                            .font(fonts.uiMedium)
                            .foregroundStyle(paperTheme.errorColor)

                        PermissionsChecklistView(includeScreenCapture: false, showAllWhenGranted: true)
                    }
                } else {
                    readyStatusRow
                }

                hotkeyCard

                if let lastRecord = history.records.first {
                    lastDictationSection(lastRecord)
                }

                cleanupStyleSection

                weeklyStatsLine
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(PaperTokens.contentPadding)
        }
        .scrollIndicators(.hidden)
        .background { PaperBackground() }
    }

    // MARK: - Status & Permissions

    private var permissionHeadline: String {
        if !appState.microphoneAuthorized || !appState.hotkeyActive {
            return "Хоткей пока не работает. Проверьте системные разрешения."
        }
        return "Для автовставки нужен «Универсальный доступ». Без него текст останется в буфере."
    }

    private var readyStatusRow: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(fonts.uiMedium)
                .foregroundStyle(paperTheme.inkColor)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            paperTheme.isDark ? paperTheme.surfaceColor.opacity(0.92) : paperTheme.surfaceColor.opacity(0.84),
            in: RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous)
                .strokeBorder(paperTheme.borderColor, lineWidth: 0.75)
        )
    }

    private var statusDotColor: Color {
        switch appState.status {
        case .idle: return paperTheme.successColor
        case .recording: return PaperTokens.recordingRed
        case .transcribing, .cleaning: return paperTheme.clipboardWarningColor
        case .error: return paperTheme.errorColor
        }
    }

    private var statusText: String {
        switch appState.status {
        case .idle: return "Готов. Работает в любом приложении."
        case .recording: return "Идёт запись…"
        case .transcribing: return "Распознаю речь…"
        case .cleaning: return "Привожу текст в порядок…"
        case .error: return "Ошибка диктовки."
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(paperTheme.errorColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(fonts.uiMedium)
                    .foregroundStyle(paperTheme.inkColor)
                Text("Если текст распознался ранее, он сохранён в истории и буфере.")
                    .font(fonts.caption)
                    .foregroundStyle(paperTheme.secondaryInkColor)
            }

            Spacer(minLength: 8)

            Button("Настройки") {
                appState.selectedSection = .settings
            }
            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
        }
        .padding(14)
        .background(
            paperTheme.errorColor.opacity(0.08),
            in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                .strokeBorder(paperTheme.errorColor.opacity(0.28), lineWidth: PaperTokens.hairline)
        )
    }

    // MARK: - Hotkey Card (L2 keycap)

    private var hotkeyCard: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(spacing: 4) {
                Text(settings.shortcutKey.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(paperTheme.inkColor)
                Text(settings.shortcutDisplayLabel)
                    .font(fonts.captionMedium)
                    .foregroundStyle(paperTheme.secondaryInkColor)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(minWidth: 112)
            .paperSurface(level: .l2OnPaper, cornerRadius: PaperTokens.controlRadius)
            .accessibilityLabel("Клавиша диктовки: \(settings.shortcutDisplayLabel)")

            VStack(alignment: .leading, spacing: 4) {
                Text(settings.shortcutMode.rawValue)
                    .font(fonts.bodyMedium)
                    .foregroundStyle(paperTheme.inkColor)

                Text(settings.shortcutMode.descriptionText)
                    .font(fonts.caption)
                    .foregroundStyle(paperTheme.secondaryInkColor)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Текст появится там, где стоит курсор. Escape отменяет запись.")
                    .font(fonts.caption)
                    .foregroundStyle(paperTheme.tertiaryInkColor)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            paperTheme.isDark ? paperTheme.surfaceColor.opacity(0.92) : paperTheme.surfaceColor.opacity(0.84),
            in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                .strokeBorder(paperTheme.borderColor, lineWidth: 0.75)
        )
    }

    // MARK: - Last Dictation

    private func lastDictationSection(_ record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Последняя диктовка")
                    .font(fonts.sectionTitle)
                    .foregroundStyle(paperTheme.inkColor)

                Spacer()

                Text(lastMetaString(for: record))
                    .font(fonts.caption)
                    .foregroundStyle(statusMetaColor(for: record.status))
                    .lineLimit(1)
            }

            PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 12, verticalPadding: 10) {
                Group {
                    if record.text.isEmpty {
                        Text(record.errorMessage ?? "Не удалось распознать речь")
                            .font(fonts.body)
                            .italic()
                            .foregroundStyle(paperTheme.secondaryInkColor)
                    } else {
                        Text(record.text)
                            .font(fonts.body)
                            .lineSpacing(3)
                            .foregroundStyle(paperTheme.inkColor)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !record.text.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        TextInjector.copyToClipboard(record.text)
                        copiedLast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedLast = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: copiedLast ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .regular))
                            Text(copiedLast ? "Скопировано" : "Копировать")
                        }
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))

                    Button {
                        _ = appState.insertTextAgain(record.text)
                        reinsertedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            reinsertedFeedback = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: reinsertedFeedback ? "checkmark" : "arrow.turn.down.left")
                                .font(.system(size: 11, weight: .regular))
                            Text(reinsertedFeedback ? "Отправлено" : "Вставить снова")
                        }
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))

                    Spacer()

                    Button("Вся история") {
                        appState.selectedSection = .history
                    }
                    .buttonStyle(.plain)
                    .font(fonts.captionMedium)
                    .foregroundStyle(paperTheme.secondaryInkColor)
                }
            }
        }
    }

    private func lastMetaString(for record: TranscriptionRecord) -> String {
        let timeStr = record.date.formatted(.dateTime.hour().minute())
        switch record.status {
        case .inserted:
            if let app = record.targetApp, !app.isEmpty {
                return "Вставлено в \(app) · \(timeStr)"
            }
            return "Вставлено · \(timeStr)"
        case .clipboardOnly:
            if let app = record.targetApp, !app.isEmpty {
                return "В буфере (\(app)) · \(timeStr)"
            }
            return "В буфере · \(timeStr)"
        case .failed:
            return "Ошибка · \(timeStr)"
        }
    }

    private func statusMetaColor(for status: InsertStatus) -> Color {
        switch status {
        case .inserted: return paperTheme.successColor
        case .clipboardOnly: return paperTheme.clipboardWarningColor
        case .failed: return paperTheme.errorColor
        }
    }

    // MARK: - Cleanup Style (4 Capsules)

    private var cleanupStyleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Обработка текста")
                .font(fonts.sectionTitle)
                .foregroundStyle(paperTheme.inkColor)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CleanupStyle.allCases) { style in
                        let isSelected = settings.cleanupStyle == style
                        Button {
                            settings.cleanupStyle = style
                        } label: {
                            Text(style.shortTitle)
                        }
                        .buttonStyle(
                            PaperButtonStyle(
                                role: isSelected ? .primary : .secondary,
                                compact: true,
                                isCapsule: true
                            )
                        )
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }

            Text(settings.cleanupStyle.oneLineDescription)
                .font(fonts.caption)
                .foregroundStyle(paperTheme.inkColor)

            Text("Текст отправляется в Anthropic API. Без ключа текст вставляется как распознан.")
                .font(fonts.caption)
                .foregroundStyle(paperTheme.secondaryInkColor)
        }
    }

    // MARK: - Quiet Weekly Stat Line

    private var weeklyStatsLine: some View {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = history.records.filter { $0.date >= weekAgo && !$0.text.isEmpty }
        let words = recent.reduce(0) { $0 + $1.wordCount }
        let timed = recent.filter { $0.durationSeconds > 1 }
        let totalMinutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60.0
        let wpmText: String = {
            guard totalMinutes > 0 else { return "" }
            let timedWords = timed.reduce(0) { $0 + $1.wordCount }
            let wpm = Int((Double(timedWords) / totalMinutes).rounded())
            return " · \(wpm) сл/мин"
        }()

        return HStack(spacing: 6) {
            if words > 0 {
                Text("За неделю: \(words) слов\(wpmText)")
            } else {
                Text("За неделю диктовок ещё не было.")
            }
        }
        .font(fonts.caption)
        .foregroundStyle(paperTheme.tertiaryInkColor)
        .padding(.top, 4)
    }
}
