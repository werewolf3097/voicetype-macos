import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var windowBox = MenuBarWindowBox()

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }

    private func dismissMenuBar() {
        dismiss()
        if let window = windowBox.window, window.isVisible {
            window.close()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusHeader

            if case .error(let message) = appState.status {
                HStack(spacing: 7) {
                    ClaudeIcon(name: "exclamationmark.triangle", size: 12, weight: .light)
                    Text(message)
                        .font(ClaudeFonts.small)
                }
                .foregroundStyle(theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !appState.hotkeyActive || !appState.microphoneAuthorized || (settings.autoPaste && !appState.accessibilityAuthorized) {
                permissionWarning
            }

            Divider().overlay(theme.border)

            if appState.activeMeetingID != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(theme.danger)
                            .frame(width: 7, height: 7)
                        Text("Запись встречи")
                            .font(ClaudeFonts.smallSemibold)
                            .foregroundStyle(theme.danger)
                        Spacer()
                        Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                            .font(ClaudeFonts.smallMedium.monospacedDigit())
                            .foregroundStyle(theme.secondaryInk)
                    }

                    Button {
                        dismissMenuBar()
                        appState.finishMeeting()
                        DashboardWindowController.shared.show(section: .meetings)
                    } label: {
                        HStack(spacing: 6) {
                            ClaudeIcon(name: "stop.circle", size: 12, weight: .regular)
                            Text("Завершить и создать рекап")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ClaudePrimaryButtonStyle(compact: true, tintColor: theme.danger))

                    ClaudeMenuRowButton("Открыть блокнот встречи…", systemImage: "doc.text") {
                        dismissMenuBar()
                        DashboardWindowController.shared.show(section: .meetings)
                    }
                }
            } else {
                Button {
                    dismissMenuBar()
                    if let id = appState.startMeeting(
                        template: .general,
                        audioSource: settings.meetingAudioSource
                    ) {
                        appState.selectedMeetingID = id
                    }
                    DashboardWindowController.shared.show(section: .meetings)
                } label: {
                    HStack(spacing: 6) {
                        ClaudeIcon(name: "plus", size: 11.5, weight: .medium)
                        Text("Начать запись встречи")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
            }

            Divider().overlay(theme.border)

            VStack(alignment: .leading, spacing: 2) {
                ClaudeMenuRowButton("Открыть VoiceType", systemImage: "macwindow") {
                    dismissMenuBar()
                    DashboardWindowController.shared.show(section: .home)
                }

                ClaudeMenuRowButton("Встречи и рекапы…", systemImage: "person.2") {
                    dismissMenuBar()
                    DashboardWindowController.shared.show(section: .meetings)
                }

                ClaudeMenuRowButton("Настройки…", systemImage: "gearshape", shortcut: "⌘,") {
                    dismissMenuBar()
                    DashboardWindowController.shared.show(section: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            Divider().overlay(theme.border)

            ClaudeMenuRowButton("Выйти из VoiceType", systemImage: "power", shortcut: "⌘Q") {
                dismissMenuBar()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(10)
        .frame(width: 274)
        .background(theme.canvas)
        .background(MenuBarWindowAccessor(box: windowBox))
        .tint(theme.accent)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onAppear { appState.refreshPermissionsAndHotkey() }
    }

    private var statusHeader: some View {
        HStack(spacing: 9) {
            statusIcon
                .frame(width: 24, height: 24)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(ClaudeFonts.uiMedium)
                    .foregroundStyle(theme.ink)
                Text(hotkeyHint)
                    .font(ClaudeFonts.micro)
                    .foregroundStyle(theme.secondaryInk)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }

    private var hotkeyHint: String {
        settings.recordingMode == .toggle
            ? "\(settings.hotkey.rawValue) · старт/стоп"
            : "\(settings.hotkey.rawValue) · удержание"
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.status {
        case .idle:
            ClaudeIcon(name: "mic", size: 12.5, weight: .light)
                .foregroundStyle(theme.accent)
        case .recording:
            ClaudeIcon(name: "waveform", size: 12.5, weight: .regular)
                .symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(theme.danger)
        case .transcribing, .cleaning:
            ClaudeIcon(name: "waveform", size: 12.5, weight: .regular)
                .symbolEffect(.pulse, isActive: true)
                .foregroundStyle(theme.accent)
        case .error:
            ClaudeIcon(name: "exclamationmark.triangle", size: 12.5, weight: .light)
                .foregroundStyle(theme.warning)
        }
    }

    private var statusTitle: String {
        switch appState.status {
        case .idle: return "Готов к диктовке"
        case .recording: return "Идёт запись…"
        case .transcribing: return "Распознавание…"
        case .cleaning: return "Обработка текста…"
        case .error: return "Ошибка"
        }
    }

    @ViewBuilder
    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !appState.hotkeyActive {
                if appState.inputMonitoringAuthorized {
                    permissionAction("Мониторинг ввода: нужен перезапуск", buttonTitle: "Перезапустить") {
                        dismissMenuBar()
                        PermissionsHelper.relaunchApp()
                    }
                } else {
                    permissionAction("Нет доступа к «Мониторингу ввода»", buttonTitle: "Разрешить") {
                        dismissMenuBar()
                        PermissionsHelper.openInputMonitoringSettings()
                    }
                }
            }

            if !appState.microphoneAuthorized {
                permissionAction("Нет доступа к микрофону", buttonTitle: "Разрешить") {
                    dismissMenuBar()
                    PermissionsHelper.openMicrophoneSettings()
                }
            }

            if settings.autoPaste && !appState.accessibilityAuthorized {
                permissionAction("Нет доступа к Accessibility", buttonTitle: "Разрешить") {
                    dismissMenuBar()
                    PermissionsHelper.openAccessibilitySettings()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func permissionAction(_ title: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(ClaudeFonts.small)
                .foregroundStyle(theme.warning)
                .lineLimit(2)
            Spacer()
            Button(buttonTitle, action: action)
                .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
        }
    }
}

private final class MenuBarWindowBox {
    weak var window: NSWindow?
}

private struct MenuBarWindowAccessor: NSViewRepresentable {
    let box: MenuBarWindowBox

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.onWindowChange = { [box] window in
            if let window {
                box.window = window
            }
        }
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        if let window = nsView.window, box.window !== window {
            box.window = window
        }
    }

    final class WindowObserverView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }
}

private struct ClaudeMenuRowButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String
    let shortcut: String?
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, systemImage: String, shortcut: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        let theme = ClaudeTheme(scheme: colorScheme)
        Button {
            isHovered = false
            action()
        } label: {
            HStack(spacing: 8) {
                ClaudeIcon(name: systemImage, size: 12.5, weight: isHovered ? .regular : .light)
                    .frame(width: 16)
                    .foregroundStyle(isHovered ? theme.ink : theme.secondaryInk)
                Text(title)
                    .font(ClaudeFonts.ui)
                    .foregroundStyle(theme.ink)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(ClaudeFonts.micro)
                        .foregroundStyle(isHovered ? theme.secondaryInk : theme.tertiaryInk)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? theme.hoverFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isHovered ? theme.border : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDisappear { isHovered = false }
    }
}
