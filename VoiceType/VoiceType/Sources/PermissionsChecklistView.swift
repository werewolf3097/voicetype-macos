import SwiftUI

/// Единый компонент чеклиста системных разрешений для экрана «Диктовка» (при проблемах) и «Настройки → Разрешения».
struct PermissionsChecklistView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.paperTheme) private var theme
    @Environment(\.paperFontPreset) private var fontPreset

    let includeScreenCapture: Bool
    let showAllWhenGranted: Bool

    init(includeScreenCapture: Bool = true, showAllWhenGranted: Bool = true) {
        self.includeScreenCapture = includeScreenCapture
        self.showAllWhenGranted = showAllWhenGranted
    }

    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showAllWhenGranted || !appState.microphoneAuthorized {
                permissionItem(
                    title: "Микрофон",
                    summary: "Нужен для записи речи во время диктовки и встреч.",
                    detailWhenMissing: "Аудио записывается только в момент диктовки и отправляется только в выбранный сервис распознавания.",
                    isGranted: appState.microphoneAuthorized,
                    isOptional: false,
                    needsRelaunch: false,
                    openAction: { PermissionsHelper.openMicrophoneSettings() },
                    recheckAction: {
                        if PermissionsHelper.microphoneStatus() == .notDetermined {
                            PermissionsHelper.requestMicrophone { _ in
                                appState.refreshPermissionsAndHotkey()
                            }
                        } else {
                            appState.refreshPermissionsAndHotkey()
                        }
                    }
                )
            }

            if showAllWhenGranted || !appState.hotkeyActive {
                if showAllWhenGranted || !appState.microphoneAuthorized {
                    Divider().overlay(theme.borderColor)
                }
                let inputNeedsRelaunch = !appState.hotkeyActive && appState.inputMonitoringAuthorized
                permissionItem(
                    title: "Мониторинг ввода",
                    summary: "Нужен, чтобы клавиша диктовки срабатывала в любом приложении.",
                    detailWhenMissing: inputNeedsRelaunch
                        ? "Доступ уже выдан, но macOS применяет «Мониторинг ввода» только после перезапуска приложения."
                        : "Клавиши не записываются и никуда не уходят. Приложение проверяет только выбранный модификатор.",
                    isGranted: appState.hotkeyActive,
                    isOptional: false,
                    needsRelaunch: inputNeedsRelaunch,
                    openAction: { PermissionsHelper.openInputMonitoringSettings() },
                    recheckAction: { appState.refreshPermissionsAndHotkey(forceRestartTap: true) }
                )
            }

            if showAllWhenGranted || (settings.pasteMode == .autoPaste && !appState.accessibilityAuthorized) {
                if showAllWhenGranted || !appState.microphoneAuthorized || !appState.hotkeyActive {
                    Divider().overlay(theme.borderColor)
                }
                permissionItem(
                    title: "Универсальный доступ",
                    summary: "Необязательно. Нужен только для автовставки, без него текст попадёт в буфер.",
                    detailWhenMissing: "Без этого разрешения диктовка всё равно работает: текст копируется в буфер для ручной вставки ⌘V.",
                    isGranted: appState.accessibilityAuthorized,
                    isOptional: true,
                    needsRelaunch: false,
                    openAction: { PermissionsHelper.openAccessibilitySettings() },
                    recheckAction: { appState.refreshPermissionsAndHotkey(forceRestartTap: true) }
                )
            }

            if includeScreenCapture && (showAllWhenGranted || (settings.meetingAudioSource == .micAndSystem && !appState.screenCaptureAuthorized)) {
                Divider().overlay(theme.borderColor)
                permissionItem(
                    title: "Запись системного звука",
                    summary: "Необязательно. Используется во встречах для записи речи собеседников.",
                    detailWhenMissing: "Если доступ не выдан, во встречах запишется только ваш микрофон. После выдачи может потребоваться перезапуск.",
                    isGranted: appState.screenCaptureAuthorized,
                    isOptional: true,
                    needsRelaunch: !appState.screenCaptureAuthorized,
                    openAction: { PermissionsHelper.openScreenCaptureSettings() },
                    recheckAction: { appState.refreshPermissionsAndHotkey() }
                )
            }
        }
        .background(
            theme.isDark ? theme.surfaceColor.opacity(0.92) : theme.surfaceColor.opacity(0.84),
            in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                .strokeBorder(theme.borderColor, lineWidth: 0.75)
        )
    }

    private func permissionItem(
        title: String,
        summary: String,
        detailWhenMissing: String,
        isGranted: Bool,
        isOptional: Bool,
        needsRelaunch: Bool,
        openAction: @escaping () -> Void,
        recheckAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                checkboxIndicator(isGranted: isGranted, isOptional: isOptional)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(fonts.uiMedium)
                            .foregroundStyle(theme.inkColor)

                        if isOptional {
                            Text("Необязательно")
                                .font(fonts.micro)
                                .foregroundStyle(theme.secondaryInkColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(theme.insetColor, in: Capsule())
                        }
                    }

                    Text(summary)
                        .font(fonts.caption)
                        .foregroundStyle(theme.secondaryInkColor)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(isGranted ? "Выдано" : (needsRelaunch ? "Нужен перезапуск" : "Не выдано"))
                    .font(fonts.captionMedium)
                    .foregroundStyle(isGranted ? theme.successColor : (isOptional ? theme.clipboardWarningColor : theme.errorColor))
            }

            if !isGranted {
                VStack(alignment: .leading, spacing: 10) {
                    Text(detailWhenMissing)
                        .font(fonts.caption)
                        .foregroundStyle(theme.secondaryInkColor)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        if needsRelaunch {
                            Button("Перезапустить", action: PermissionsHelper.relaunchApp)
                                .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
                        }
                        Button("Открыть системные настройки", action: openAction)
                            .buttonStyle(PaperButtonStyle(role: needsRelaunch ? .secondary : .primary, compact: true))
                        Button("Проверить снова", action: recheckAction)
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .paperSurface(level: .l1Inset, cornerRadius: PaperTokens.controlRadius)
                .padding(.leading, 28)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func checkboxIndicator(isGranted: Bool, isOptional: Bool) -> some View {
        let strokeColor: Color = isGranted ? theme.successColor : (isOptional ? theme.clipboardWarningColor : theme.errorColor)
        return ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isGranted ? theme.successColor : theme.insetColor)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(strokeColor.opacity(isGranted ? 1 : 0.6), lineWidth: 1)
                )

            if isGranted {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel(isGranted ? "Разрешение выдано" : "Разрешение не выдано")
    }
}
