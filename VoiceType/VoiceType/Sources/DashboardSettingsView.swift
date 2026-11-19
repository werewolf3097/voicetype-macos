import AppKit
import SwiftUI

struct DashboardSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

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

                    settingRow(
                        "Сохранять аудиозаписи",
                        caption: "Если выключено, временные аудиофайлы удаляются после успешной расшифровки."
                    ) {
                        Toggle("", isOn: $settings.keepMeetingAudio)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(theme.accent)
                    }
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
