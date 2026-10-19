import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusLine

            if case .error(let message) = appState.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !appState.hotkeyActive || !appState.microphoneAuthorized || (settings.autoPaste && !appState.accessibilityAuthorized) {
                permissionWarning
            }

            Divider()

            if settings.recordingMode == .toggle {
                Text("Нажмите \(settings.hotkey.rawValue) для старта и ещё раз для стопа.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Зажмите \(settings.hotkey.rawValue), говорите, отпустите.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if appState.activeMeetingID != nil {
                HStack {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Встреча: \(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))")
                        .font(.caption.monospacedDigit())
                }
                Button("Завершить встречу и создать рекап") {
                    appState.finishMeeting()
                    DashboardWindowController.shared.show(section: .meetings)
                }
                Button("Открыть блокнот встречи…") {
                    DashboardWindowController.shared.show(section: .meetings)
                }
            } else {
                Button("Начать запись встречи (Granola)…") {
                    _ = appState.startMeeting(
                        template: .general,
                        audioSource: settings.meetingAudioSource
                    )
                    DashboardWindowController.shared.show(section: .meetings)
                }
            }

            Divider()

            Button("Открыть VoiceType") {
                DashboardWindowController.shared.show(section: .home)
            }

            Button("Встречи и рекапы…") {
                DashboardWindowController.shared.show(section: .meetings)
            }

            Button("Настройки…") {
                DashboardWindowController.shared.show(section: .settings)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button("Выйти") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 260)
        .onAppear { appState.refreshPermissionsAndHotkey() }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch appState.status {
        case .idle:
            Label("Готов", systemImage: "mic")
        case .recording:
            Label("Запись…", systemImage: "mic.fill").foregroundStyle(.red)
        case .transcribing:
            Label("Распознавание…", systemImage: "waveform")
        case .cleaning:
            Label("Обработка текста…", systemImage: "wand.and.stars")
        case .error:
            Label("Ошибка", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !appState.hotkeyActive {
                if appState.inputMonitoringAuthorized {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Мониторинг ввода: нужен перезапуск.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Перезапустить VoiceType") {
                            PermissionsHelper.relaunchApp()
                        }
                        .font(.caption)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Нет доступа к чтению клавиш (хоткей).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Разрешить «Мониторинг ввода»") {
                            PermissionsHelper.openInputMonitoringSettings()
                        }
                        .font(.caption)
                    }
                }
            }

            if !appState.microphoneAuthorized {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Нет доступа к микрофону.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Разрешить «Микрофон»") {
                        PermissionsHelper.openMicrophoneSettings()
                    }
                    .font(.caption)
                }
            }

            if settings.autoPaste && !appState.accessibilityAuthorized {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Нет доступа к Accessibility (автовставка).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Разрешить «Accessibility»") {
                        PermissionsHelper.openAccessibilitySettings()
                    }
                    .font(.caption)
                }
            }
        }
    }
}
