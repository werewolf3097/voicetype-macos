import AppKit
import SwiftUI

struct DashboardSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var audioStats = MeetingsStore.AudioStorageStats(
        meetingsWithAudioCount: 0,
        totalBytes: 0,
        expiredMeetingsCount: 0,
        expiredBytes: 0
    )

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Настройки")
                        .font(.system(size: 24, weight: .medium, design: .serif))
                        .foregroundStyle(theme.ink)
                    Text("API-ключи, поведение хоткея, параметры встреч и системные разрешения")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryInk)
                }

                settingsCard("Ключи API") {
                    settingRow(
                        "Токен gapi",
                        caption: "Создаётся в кабинете console.gapi.uz на вкладке «API-токены»."
                    ) {
                        SecureField("Вставьте API-токен", text: $settings.gapiToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180, maxWidth: 280)
                    }

                    Divider().overlay(theme.border)

                    settingRow(
                        "Anthropic API key",
                        caption: "Необязательно. Используется для LLM-очистки диктовки и генерации рекапов."
                    ) {
                        SecureField("sk-ant-...", text: $settings.anthropicApiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180, maxWidth: 280)
                    }
                }

                settingsCard("Приложение") {
                    settingRow(
                        "Оформление",
                        caption: "По умолчанию совпадает с темой macOS."
                    ) {
                        Picker("", selection: $settings.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    Divider().overlay(theme.border)

                    settingRow(
                        "Значок в Dock",
                        caption: "Иконка в строке меню доступна всегда."
                    ) {
                        Toggle("", isOn: $settings.showDockIcon)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.accent)
                    }
                }

                settingsCard("Голос и диктовка") {
                    settingRow("Клавиша записи") {
                        Picker("", selection: $settings.hotkey) {
                            ForEach(PushToTalkKey.allCases) { key in
                                Text(key.rawValue).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: settings.hotkey) { _, _ in
                            appState.restartHotkeyListener()
                        }
                    }

                    Divider().overlay(theme.border)

                    settingRow(
                        "Режим записи",
                        caption: "«По нажатию» — один раз для старта, ещё раз для отправки. Escape отменяет запись."
                    ) {
                        Picker("", selection: $settings.recordingMode) {
                            ForEach(RecordingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .onChange(of: settings.recordingMode) { _, _ in
                            appState.refreshPermissionsAndHotkey()
                        }
                    }

                    Divider().overlay(theme.border)

                    settingRow("Автовставка (Cmd+V)") {
                        Toggle("", isOn: $settings.autoPaste)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.accent)
                    }

                    Divider().overlay(theme.border)

                    settingRow("Обработка текста") {
                        Picker("", selection: $settings.cleanupStyle) {
                            ForEach(CleanupStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    Divider().overlay(theme.border)

                    settingRow(
                        "Узбекский диалект",
                        caption: "«Ташкентский» сохраняет живую разговорную речь (qivommiz, kevotti, qatta)."
                    ) {
                        Picker("", selection: $settings.uzbekStyle) {
                            ForEach(UzbekStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                settingsCard("Встречи") {
                    settingRow(
                        "Сервер распознавания",
                        caption: "Необязательно. URL внешнего сервера транскрибации; если поле пустое — используется облако gapi.uz."
                    ) {
                        TextField("https://... или http://...", text: $settings.whisperServerURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180, maxWidth: 280)
                    }

                    Divider().overlay(theme.border)

                    settingRow(
                        "Источник звука встреч",
                        caption: "«Микрофон + Системный звук» разделяет каналы («Вы» и «Собеседники»)."
                    ) {
                        Picker("", selection: $settings.meetingAudioSource) {
                            ForEach(MeetingAudioSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    Divider().overlay(theme.border)

                    exportDestinationRow

                    Divider().overlay(theme.border)

                    settingRow(
                        "Резюме на стороне gapi (×1.3)",
                        caption: "Применимо при отправке в gapi.uz. По умолчанию выключено."
                    ) {
                        Toggle("", isOn: $settings.enableGapiSummary)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.accent)
                    }

                    Divider().overlay(theme.border)

                    audioRetentionRow
                }

                settingsCard("Разрешения macOS") {
                    settingRow(
                        "Мониторинг ввода",
                        caption: "Нужен для работы глобального хоткея поверх всех окон."
                    ) {
                        if appState.hotkeyActive {
                            permissionStatus(status: "Разрешён", granted: true, buttonTitle: "Настройки") {
                                PermissionsHelper.openInputMonitoringSettings()
                            }
                        } else if appState.inputMonitoringAuthorized {
                            permissionStatus(status: "Нужен перезапуск", granted: false, buttonTitle: "Перезапустить") {
                                PermissionsHelper.relaunchApp()
                            }
                        } else {
                            permissionStatus(status: "Нужно разрешить", granted: false, buttonTitle: "Разрешить") {
                                PermissionsHelper.openInputMonitoringSettings()
                            }
                        }
                    }

                    Divider().overlay(theme.border)

                    settingRow("Микрофон", caption: "Нужен для диктовки и записи встреч.") {
                        permissionStatus(
                            status: appState.microphoneAuthorized ? "Разрешён" : "Нужно разрешить",
                            granted: appState.microphoneAuthorized,
                            buttonTitle: appState.microphoneAuthorized ? "Настройки" : "Разрешить"
                        ) {
                            PermissionsHelper.openMicrophoneSettings()
                        }
                    }

                    Divider().overlay(theme.border)

                    settingRow("Accessibility", caption: "Нужен для автовставки (Cmd+V) и отмены по Escape.") {
                        permissionStatus(
                            status: appState.accessibilityAuthorized ? "Разрешён" : "Нужно разрешить",
                            granted: appState.accessibilityAuthorized,
                            buttonTitle: appState.accessibilityAuthorized ? "Настройки" : "Разрешить"
                        ) {
                            PermissionsHelper.openAccessibilitySettings()
                        }
                    }

                    Divider().overlay(theme.border)

                    settingRow(
                        "Системный звук",
                        caption: "Запись системного звука во время встреч для распознавания речи собеседников. Если тумблер уже включён после пересборки, переключите его заново и перезапустите."
                    ) {
                        HStack(spacing: 6) {
                            permissionStatus(
                                status: appState.screenCaptureAuthorized ? "Разрешён" : "Нужно разрешить",
                                granted: appState.screenCaptureAuthorized,
                                buttonTitle: appState.screenCaptureAuthorized ? "Настройки" : "Разрешить"
                            ) {
                                PermissionsHelper.openScreenCaptureSettings()
                            }
                            if !appState.screenCaptureAuthorized {
                                Button("Перезапустить") {
                                    PermissionsHelper.relaunchApp()
                                }
                                .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 740, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(theme.canvas)
        .onAppear {
            if PermissionsHelper.microphoneStatus() == .notDetermined {
                PermissionsHelper.requestMicrophone { _ in
                    appState.refreshPermissionsAndHotkey()
                }
            } else {
                appState.refreshPermissionsAndHotkey()
            }
            refreshAudioStats()
        }
        .onChange(of: settings.meetingAudioRetention) { _, _ in
            refreshAudioStats()
        }
        .onChange(of: meetingsStore.meetings) { _, _ in
            refreshAudioStats()
        }
    }

    private var audioRetentionRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 16) {
                settingLabel(
                    "Хранение аудиозаписей",
                    caption: "Оригиналы аудио встреч автоматически удаляются по истечении срока (рекап и транскрипт сохраняются). Записи в очереди и с ошибкой не удаляются."
                )
                Spacer(minLength: 8)
                Picker("", selection: $settings.meetingAudioRetention) {
                    ForEach(MeetingAudioRetention.allCases) { retention in
                        Text(retention.rawValue).tag(retention)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            HStack(spacing: 10) {
                if audioStats.totalBytes > 0 {
                    Label(
                        "На диске: \(formattedBytes(audioStats.totalBytes)) (\(meetingsCountLabel(audioStats.meetingsWithAudioCount)))",
                        systemImage: "waveform"
                    )
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryInk)
                } else {
                    Label("Сохранённых аудиофайлов нет", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryInk)
                }

                Spacer(minLength: 8)

                if audioStats.expiredMeetingsCount > 0 {
                    Button("Очистить устаревшие (\(formattedBytes(audioStats.expiredBytes)))") {
                        appState.cleanupExpiredMeetingAudio()
                        refreshAudioStats()
                    }
                    .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func refreshAudioStats() {
        audioStats = meetingsStore.audioStorageStats(retention: settings.meetingAudioRetention)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func meetingsCountLabel(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        if mod100 >= 11 && mod100 <= 14 {
            return "\(count) встреч"
        }
        switch mod10 {
        case 1: return "\(count) встреча"
        case 2, 3, 4: return "\(count) встречи"
        default: return "\(count) встреч"
        }
    }

    private var exportDestinationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingLabel(
                "Автоэкспорт рекапов",
                caption: "Необязательно. Вставьте путь к папке для сохранения Markdown-файлов (*_vt.md) или URL внешнего сервиса (Webhook JSON). Оставьте пустым, чтобы отключить."
            )

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField("Путь к папке или https://...", text: $settings.exportDestination)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .foregroundStyle(theme.ink)

                    if !settings.exportDestination.isEmpty {
                        Button {
                            settings.exportDestination = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(theme.secondaryInk)
                        }
                        .buttonStyle(.plain)
                        .help("Очистить")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )

                Button("Выбрать папку…") {
                    chooseExportFolder()
                }
                .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
            }

            exportDestinationStatusHint
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var exportDestinationStatusHint: some View {
        switch MeetingsStore.resolvedExportDestination(from: settings.exportDestination) {
        case .none:
            EmptyView()
        case .webhook(let url):
            Label("Экспорт по Webhook URL (\(url.host ?? url.absoluteString))", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(theme.success)
        case .folder(let folderURL):
            let exists = FileManager.default.fileExists(atPath: folderURL.path)
            Label(
                exists ? "Папка найдена: \(folderURL.lastPathComponent)" : "Папка будет создана при экспорте",
                systemImage: exists ? "checkmark.circle.fill" : "folder.badge.plus"
            )
            .font(.caption2)
            .foregroundStyle(exists ? theme.success : theme.secondaryInk)
        }
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Выбрать"
        panel.message = "Выберите папку для автоматического экспорта рекапов"
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportDestination = url.path
        }
    }

    private func settingsCard<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryInk)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
            .shadow(color: theme.cardShadow, radius: 8, y: 2)
        }
    }

    private func settingRow<Control: View>(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                settingLabel(title, caption: caption)
                    .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                control()
                    .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 10) {
                settingLabel(title, caption: caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                control()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func settingLabel(_ title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(theme.ink)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func permissionStatus(
        status: String,
        granted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? theme.success : theme.warning)
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(granted ? theme.secondaryInk : theme.warning)
            if granted {
                Button(buttonTitle, action: action)
                    .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
            }
        }
    }
}
