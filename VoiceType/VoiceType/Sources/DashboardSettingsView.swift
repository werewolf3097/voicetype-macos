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
                    row("Режим записи", caption: "«По нажатию» — нажали один раз для старта, нажали ещё раз для завершения (Esc — отмена).") {
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

                settingsGroup("Встречи (Granola)") {
                    row(
                        "Источник звука встреч",
                        caption: "«Микрофон + Системный звук» разделяет каналы («Вы» и «Собеседник») через бесплатный стерео-режим gapi."
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
                        "Резюме от gapi (×1.3)",
                        caption: "Если выключено (по умолчанию), используется бесплатный тариф ×1.0, а рекап строится локально или через Claude."
                    ) {
                        Toggle("", isOn: $settings.enableGapiSummary)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    row(
                        "Сохранять аудиозаписи",
                        caption: "Если выключено (как в Granola), WAV-файл встречи удаляется после успешной транскрибации, оставляя только рекап и транскрипт."
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
