import SwiftUI

struct DashboardHomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var quickMeetingTitle: String = ""
    @State private var selectedTemplate: MeetingTemplate = .general
    @State private var copiedLast = false

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroHeader
                    .padding(.top, 8)

                if case .error(let message) = appState.status {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.warning)
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(theme.ink)
                        Spacer()
                    }
                    .padding(12)
                    .background(theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.warning.opacity(0.25))
                    )
                }

                if showsPermissionCard {
                    permissionBanner
                }

                claudeComposerCard

                templateChipsRow

                statsStrip

                lastTranscriptSection
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .scrollIndicators(.hidden)
        .background(theme.canvas)
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 14) {
                heroTitleBlock
                Spacer(minLength: 12)
                statusPill
            }

            VStack(alignment: .leading, spacing: 10) {
                heroTitleBlock
                statusPill
            }
        }
    }

    private var heroTitleBlock: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 38, height: 38)
                .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Говорите, не печатайте")
                    .font(.system(size: 26, weight: .medium, design: .serif))
                    .foregroundStyle(theme.ink)
                Text(hotkeyHintText)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryInk)
            }
        }
    }

    private var hotkeyHintText: String {
        settings.recordingMode == .toggle
            ? "Диктовка: нажмите \(settings.hotkey.rawValue) для старта и ещё раз для вставки · Esc отменяет"
            : "Диктовка: удерживайте \(settings.hotkey.rawValue), говорите и отпустите · Esc отменяет"
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            statusIcon
                .font(.caption.weight(.semibold))
            Text(statusTitle)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(theme.ink)
        }
        .fixedSize()
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
    }

    // MARK: - Claude Composer Card

    private var claudeComposerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if appState.activeMeetingID != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        activeRecordingInfo
                        Spacer()
                        activeRecordingControls
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        activeRecordingInfo
                        activeRecordingControls
                    }
                }
                .padding(.vertical, 4)
            } else {
                TextField("О чём будет встреча? (необязательно — можно оставить пустым)", text: $quickMeetingTitle)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .foregroundStyle(theme.ink)
                    .onSubmit {
                        startQuickMeeting(template: selectedTemplate)
                    }

                // Bottom toolbar inside composer
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        composerPickers
                        Spacer(minLength: 8)
                        startMeetingButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        composerPickers
                        HStack {
                            Spacer()
                            startMeetingButton
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.border, lineWidth: 1)
        )
        .shadow(color: theme.cardShadow, radius: 14, y: 5)
    }

    private var activeRecordingInfo: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.title3)
                .symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(theme.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Сейчас идёт запись встречи")
                    .font(.headline)
                    .foregroundStyle(theme.ink)
                Text("Время записи: \(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(theme.secondaryInk)
            }
        }
    }

    private var activeRecordingControls: some View {
        ClaudeFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
            Button("Открыть блокнот") {
                appState.selectedMeetingID = appState.activeMeetingID
                appState.selectedSection = .meetings
            }
            .buttonStyle(ClaudeSecondaryButtonStyle())

            Button("Завершить и создать рекап") {
                appState.finishMeeting()
                appState.selectedSection = .meetings
            }
            .buttonStyle(ClaudePrimaryButtonStyle(tintColor: theme.danger))
        }
    }

    private var composerPickers: some View {
        ClaudeFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
            Menu {
                ForEach(MeetingTemplate.allCases) { tpl in
                    Button {
                        selectedTemplate = tpl
                    } label: {
                        Label(tpl.rawValue, systemImage: tpl.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: selectedTemplate.systemImage)
                        .font(.caption)
                    Text(selectedTemplate.rawValue)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.secondaryInk)
                }
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                ForEach(MeetingAudioSource.allCases) { source in
                    Button {
                        settings.meetingAudioSource = source
                    } label: {
                        Text(source.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: settings.meetingAudioSource == .micAndSystem ? "speaker.wave.2" : "mic")
                        .font(.caption)
                    Text(settings.meetingAudioSource.rawValue)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.secondaryInk)
                }
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var startMeetingButton: some View {
        Button {
            startQuickMeeting(template: selectedTemplate)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "record.circle")
                Text("Начать встречу")
            }
        }
        .buttonStyle(ClaudePrimaryButtonStyle())
    }

    private var templateChipsRow: some View {
        ClaudeFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(MeetingTemplate.allCases) { tpl in
                Button {
                    selectedTemplate = tpl
                    startQuickMeeting(template: tpl)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tpl.systemImage)
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryInk)
                        Text(tpl.rawValue)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundStyle(theme.secondaryInk)
                    }
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func startQuickMeeting(template: MeetingTemplate) {
        let title = quickMeetingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        quickMeetingTitle = ""
        if let id = appState.startMeeting(
            title: title,
            template: template,
            audioSource: settings.meetingAudioSource
        ) {
            appState.selectedMeetingID = id
            appState.selectedSection = .meetings
        }
    }

    // MARK: - Permissions

    private var showsPermissionCard: Bool {
        !appState.hotkeyActive
            || !appState.microphoneAuthorized
            || (settings.autoPaste && !appState.accessibilityAuthorized)
            || (settings.meetingAudioSource == .micAndSystem && !appState.screenCaptureAuthorized)
    }

    private var permissionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.hotkeyActive {
                permissionRow(systemImage: "keyboard") {
                    if appState.inputMonitoringAuthorized {
                        Text("Мониторинг ввода разрешён, нужен перезапуск приложения.")
                        Spacer(minLength: 8)
                        Button("Перезапустить") { PermissionsHelper.relaunchApp() }
                            .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
                    } else {
                        Text("Мониторинг ввода не разрешён — хоткей не работает вне окна.")
                        Spacer(minLength: 8)
                        Button("Разрешить") { PermissionsHelper.openInputMonitoringSettings() }
                            .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
                    }
                }
            }

            if !appState.microphoneAuthorized {
                if !appState.hotkeyActive { Divider().overlay(theme.border) }
                permissionRow(systemImage: "mic.slash") {
                    Text("Доступ к микрофону не разрешён — запись невозможна.")
                    Spacer(minLength: 8)
                    Button("Разрешить") { PermissionsHelper.openMicrophoneSettings() }
                        .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
                }
            }

            if settings.autoPaste && !appState.accessibilityAuthorized {
                if !appState.hotkeyActive || !appState.microphoneAuthorized { Divider().overlay(theme.border) }
                permissionRow(systemImage: "hand.raised") {
                    Text("Accessibility не разрешён — автовставка (Cmd+V) не сработает.")
                    Spacer(minLength: 8)
                    Button("Разрешить") { PermissionsHelper.openAccessibilitySettings() }
                        .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                }
            }

            if settings.meetingAudioSource == .micAndSystem && !appState.screenCaptureAuthorized {
                if !appState.hotkeyActive || !appState.microphoneAuthorized || (settings.autoPaste && !appState.accessibilityAuthorized) {
                    Divider().overlay(theme.border)
                }
                permissionRow(systemImage: "speaker.wave.2") {
                    Text("Системный звук не разрешён — во встречах запишется только ваш микрофон.")
                    Spacer(minLength: 8)
                    Button("Разрешить") { PermissionsHelper.openScreenCaptureSettings() }
                        .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                    Button("Перезапустить") { PermissionsHelper.relaunchApp() }
                        .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
                }
            }
        }
        .padding(12)
        .background(theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.warning.opacity(0.25))
        )
    }

    private func permissionRow<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(theme.warning)
                .frame(width: 16)
            content()
                .font(.caption)
                .foregroundStyle(theme.ink)
        }
    }

    // MARK: - Stats & Last Transcript

    private var statsStrip: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 10)], spacing: 10) {
            statPill(title: "Расшифровок", value: "\(history.records.count)")
            statPill(title: "Слов надиктовано", value: "\(totalWords)")
            if let wpm = averageWordsPerMinute {
                statPill(title: "Скорость", value: "\(wpm) сл/мин")
            }
            statPill(title: "Активных дней", value: "\(activeDaysCount)")
        }
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(theme.ink)
            Text(title)
                .font(.caption)
                .foregroundStyle(theme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .claudeCard(theme, cornerRadius: 12, padding: 12)
    }

    @ViewBuilder
    private var lastTranscriptSection: some View {
        if let last = history.records.first {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Последняя диктовка")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(theme.ink)

                    if let lang = last.languageSummary, !lang.isEmpty {
                        Text(lang)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(theme.accentInk)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(theme.accentSoft, in: Capsule())
                    }

                    Spacer()

                    Text(last.date, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(theme.secondaryInk)
                        .lineLimit(1)

                    Button {
                        TextInjector.copyToClipboard(last.text)
                        copiedLast = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedLast = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedLast ? "checkmark" : "doc.on.doc")
                            Text(copiedLast ? "Скопировано" : "Копировать")
                        }
                    }
                    .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                }

                Text(last.text)
                    .font(.body)
                    .foregroundStyle(theme.ink)
                    .textSelection(.enabled)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Button {
                        appState.selectedSection = .history
                    } label: {
                        HStack(spacing: 4) {
                            Text("Вся история")
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }
            .claudeCard(theme, cornerRadius: 14, padding: 16)
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.status {
        case .idle:
            Image(systemName: "mic.fill").foregroundStyle(theme.accent)
        case .recording:
            Image(systemName: "waveform")
                .symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(theme.danger)
        case .transcribing, .cleaning:
            Image(systemName: "waveform")
                .symbolEffect(.pulse, isActive: true)
                .foregroundStyle(theme.accent)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(theme.warning)
        }
    }

    private var statusTitle: String {
        switch appState.status {
        case .idle: return "Готов слушать"
        case .recording: return "Идёт запись…"
        case .transcribing: return "Распознаю речь…"
        case .cleaning: return "Обрабатываю текст…"
        case .error: return "Ошибка"
        }
    }

    private var totalWords: Int {
        history.records.reduce(0) { $0 + $1.wordCount }
    }

    private var averageWordsPerMinute: Int? {
        let timed = history.records.filter { $0.durationSeconds > 1 }
        guard !timed.isEmpty else { return nil }
        let totalMinutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60
        guard totalMinutes > 0 else { return nil }
        let words = timed.reduce(0) { $0 + $1.wordCount }
        return Int((Double(words) / totalMinutes).rounded())
    }

    private var activeDaysCount: Int {
        let calendar = Calendar.current
        let days = Set(history.records.map { calendar.startOfDay(for: $0.date) })
        return days.count
    }
}
