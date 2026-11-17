import SwiftUI

struct DashboardSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore

    private let labelWidth: CGFloat = 190

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                settingsGroup("Ключи API") {
                    row("Токен gapi", caption: "Создаётся в кабинете console.gapi.uz на вкладке «API-токены».") {
                        SecureField("", text: $settings.gapiToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 380)
                    }
                    row("Anthropic API key", caption: "Нужен только для очистки текста стилем ниже (необязательно). Получить: console.anthropic.com.") {
                        SecureField("", text: $settings.anthropicApiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 380)
                    }
                }

                settingsGroup("Приложение") {
                    row("Оформление", caption: "По умолчанию окно совпадает с темой macOS.") {
                        Picker("", selection: $settings.appearance) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    row("Значок в Dock", caption: "Меню в строке статуса доступно в любом случае — это только про значок в Dock.") {
                        Toggle("", isOn: $settings.showDockIcon)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                settingsGroup("Голос") {
                    row("Клавиша записи") {
                        Picker("", selection: $settings.hotkey) {
                            ForEach(PushToTalkKey.allCases) { key in
                                Text(key.rawValue).tag(key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                        .onChange(of: settings.hotkey) { _, _ in
                            appState.restartHotkeyListener()
                        }
                    }
                    row("Режим записи", caption: "«По нажатию» — нажали один раз для старта, нажали ещё раз для отправки. Escape отменяет запись: файл удаляется и на сервер не уходит.") {
                        Picker("", selection: $settings.recordingMode) {
                            ForEach(RecordingMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                        .onChange(of: settings.recordingMode) { _, _ in
                            appState.refreshPermissionsAndHotkey()
                        }
                    }
                    row("Автовставка (Cmd+V)") {
                        Toggle("", isOn: $settings.autoPaste)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    row("Обработка текста") {
                        Picker("", selection: $settings.cleanupStyle) {
                            ForEach(CleanupStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    row(
                        "Узбекский диалект",
                        caption: "«Ташкентский» сохраняет живую разговорную речь (qivommiz, kevotti, qatta) вместо книжного литературного формата."
                    ) {
                        Picker("", selection: $settings.uzbekStyle) {
                            ForEach(UzbekStyle.allCases) { style in
                                Text(style.rawValue).tag(style)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                }

                settingsGroup("Встречи") {
                    row(
                        "Сервер Whisper (farrukh-pc)",
                        caption: "Основной вычислитель по Tailscale (whisper large-v3-turbo). Если недоступен, запись ждёт в очереди или отправляется вручную в gapi.uz."
                    ) {
                        TextField("", text: $settings.whisperServerURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 380)
                    }
                    row(
                        "Источник звука встреч",
                        caption: "«Микрофон + Системный звук» разделяет каналы («Вы» и «Собеседники») без нагрузки на CPU."
                    ) {
                        Picker("", selection: $settings.meetingAudioSource) {
                            ForEach(MeetingAudioSource.allCases) { source in
                                Text(source.rawValue).tag(source)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    row(
                        "Автоэкспорт в Obsidian",
                        caption: "Сохранять готовый Markdown-рекап (*_vt.md) в «\(settings.obsidianRecapsFolder)»."
                    ) {
                        Toggle("", isOn: $settings.autoExportToObsidian)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    row(
                        "Резюме от gapi (×1.3)",
                        caption: "Применимо только при экстренной отправке в gapi.uz. По умолчанию выключено (бесплатный тариф ×1.0)."
                    ) {
                        Toggle("", isOn: $settings.enableGapiSummary)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    row(
                        "Сохранять аудиозаписи",
                        caption: "Если выключено, mic.wav и sys.wav удаляются после успешной расшифровки. Пока запись в очереди или в ошибке, файлы сохраняются всегда."
                    ) {
                        Toggle("", isOn: $settings.keepMeetingAudio)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                settingsGroup("Разрешения", isLast: true) {
                    row("Мониторинг ввода", caption: "Нужен для работы глобального хоткея поверх всех окон.") {
                        if appState.hotkeyActive {
                            permissionControl(status: "Разрешён", granted: true, buttonTitle: "Открыть настройки") {
                                PermissionsHelper.openInputMonitoringSettings()
                            }
                        } else if appState.inputMonitoringAuthorized {
                            permissionControl(status: "Нужен перезапуск", granted: false, buttonTitle: "Перезапустить") {
                                PermissionsHelper.relaunchApp()
                            }
                        } else {
                            permissionControl(status: "Нужно разрешить", granted: false, buttonTitle: "Разрешить") {
                                PermissionsHelper.openInputMonitoringSettings()
                            }
                        }
                    }
                    row("Микрофон", caption: "Нужен для записи голоса при удержании хоткея.") {
                        permissionControl(
                            status: appState.microphoneAuthorized ? "Разрешён" : "Нужно разрешить",
                            granted: appState.microphoneAuthorized,
                            buttonTitle: appState.microphoneAuthorized ? "Открыть настройки" : "Разрешить"
                        ) {
                            PermissionsHelper.openMicrophoneSettings()
                        }
                    }
                    row("Accessibility", caption: "Нужен для автовставки текста (Cmd+V) в активное поле и отмены записи по Escape.") {
                        permissionControl(
                            status: appState.accessibilityAuthorized ? "Разрешён" : "Нужно разрешить",
                            granted: appState.accessibilityAuthorized,
                            buttonTitle: appState.accessibilityAuthorized ? "Открыть настройки" : "Разрешить"
                        ) {
                            PermissionsHelper.openAccessibilitySettings()
                        }
                    }
                    row("Системный звук (Screen Recording)", caption: "Нужен для записи голоса собеседников (sys.wav) во время встреч. После пересборки тумблер может потребоваться переключить.") {
                        permissionControl(
                            status: appState.screenCaptureAuthorized ? "Разрешён" : "Нужно разрешить",
                            granted: appState.screenCaptureAuthorized,
                            buttonTitle: appState.screenCaptureAuthorized ? "Открыть настройки" : "Разрешить"
                        ) {
                            PermissionsHelper.openScreenCaptureSettings()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
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

    @ViewBuilder
    private func settingsGroup<Content: View>(
        _ title: String,
        isLast: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(.vertical, 18)
        if !isLast {
            Divider()
        }
    }

    @ViewBuilder
    private func row<Content: View>(
        _ label: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: labelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                content()
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
    }

    @ViewBuilder
    private func permissionControl(
        status: String,
        granted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(status)
                .foregroundStyle(granted ? Color.secondary : Color.orange)
            Button(buttonTitle, action: action)
        }
    }
}
