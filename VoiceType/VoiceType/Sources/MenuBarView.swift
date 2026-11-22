import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset
    @Environment(\.dismiss) private var dismiss

    @State private var windowBox = MenuBarWindowBox()
    @State private var copiedLast = false

    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

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
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11.5))
                    Text(message)
                        .font(fonts.caption)
                }
                .foregroundStyle(paperTheme.errorColor)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(paperTheme.errorColor.opacity(0.08), in: RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous))
            }

            if !appState.hotkeyActive || !appState.microphoneAuthorized || (settings.pasteMode == .autoPaste && !appState.accessibilityAuthorized) {
                permissionWarning
            }

            if let last = history.records.first, !last.text.isEmpty {
                hairlineDivider
                lastDictationCompact(last)
            }

            hairlineDivider

            if appState.activeMeetingID != nil {
                HStack(spacing: 8) {
                    Circle()
                        .fill(PaperTokens.recordingRed)
                        .frame(width: 7, height: 7)
                    Text("Встреча · \(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))")
                        .font(fonts.captionMedium.monospacedDigit())
                        .foregroundStyle(paperTheme.inkColor)
                    Spacer()
                    Button("Завершить") {
                        dismissMenuBar()
                        appState.finishMeeting()
                        DashboardWindowController.shared.show(section: .meetings)
                    }
                    .buttonStyle(PaperButtonStyle(role: .destructive, compact: true))
                }
                .padding(.horizontal, 4)
            } else {
                PaperMenuRowButton("Начать запись встречи", systemImage: "person.2") {
                    dismissMenuBar()
                    if let id = appState.startMeeting(
                        template: .general,
                        audioSource: settings.meetingAudioSource
                    ) {
                        appState.selectedMeetingID = id
                    }
                    DashboardWindowController.shared.show(section: .meetings)
                }
            }

            hairlineDivider

            VStack(alignment: .leading, spacing: 2) {
                PaperMenuRowButton("Открыть VoiceType", systemImage: "macwindow") {
                    dismissMenuBar()
                    DashboardWindowController.shared.show(section: .home)
                }

                PaperMenuRowButton("Настройки…", systemImage: "gearshape", shortcut: "⌘,") {
                    dismissMenuBar()
                    DashboardWindowController.shared.show(section: .settings)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            hairlineDivider

            PaperMenuRowButton("Выйти из VoiceType", systemImage: "power", shortcut: "⌘Q") {
                dismissMenuBar()
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(10)
        .frame(width: 280)
        .background(paperTheme.baseColor)
        .background(MenuBarWindowAccessor(box: windowBox))
        .onAppear { appState.refreshPermissionsAndHotkey() }
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(paperTheme.borderColor)
            .frame(height: PaperTokens.hairline)
    }

    private var statusHeader: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 8, height: 8)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 1) {
                Text(statusTitle)
                    .font(fonts.uiMedium)
                    .foregroundStyle(paperTheme.inkColor)
                Text(hotkeyHint)
                    .font(fonts.micro)
                    .foregroundStyle(paperTheme.secondaryInkColor)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var statusDotColor: Color {
        if !appState.hotkeyActive || !appState.microphoneAuthorized {
            return paperTheme.errorColor
        }
        switch appState.status {
        case .idle: return paperTheme.successColor
        case .recording: return PaperTokens.recordingRed
        case .transcribing, .cleaning: return paperTheme.clipboardWarningColor
        case .error: return paperTheme.errorColor
        }
    }

    private var hotkeyHint: String {
        "\(settings.shortcutDisplayLabel) · \(settings.shortcutMode.shortTitle)"
    }

    private var statusTitle: String {
        if !appState.microphoneAuthorized {
            return "Нет доступа к микрофону"
        }
        if !appState.hotkeyActive {
            return "Хоткей не работает"
        }
        switch appState.status {
        case .idle: return "Готов"
        case .recording: return "Идёт запись…"
        case .transcribing: return "Распознаю…"
        case .cleaning: return "Привожу в порядок…"
        case .error: return "Ошибка"
        }
    }

    private func lastDictationCompact(_ record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Последняя диктовка")
                    .font(fonts.micro)
                    .foregroundStyle(paperTheme.secondaryInkColor)
                Spacer()
                Button {
                    TextInjector.copyToClipboard(record.text)
                    copiedLast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedLast = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedLast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copiedLast ? "Скопировано" : "Копировать")
                    }
                }
                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
            }

            Text(record.text)
                .font(fonts.caption)
                .foregroundStyle(paperTheme.inkColor)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .paperSurface(level: .l1Inset, cornerRadius: PaperTokens.chipRadius)
        }
        .padding(.vertical, 2)
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

            if settings.pasteMode == .autoPaste && !appState.accessibilityAuthorized {
                permissionAction("Нет «Универсального доступа» (в буфер)", buttonTitle: "Открыть") {
                    dismissMenuBar()
                    PermissionsHelper.openAccessibilitySettings()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(paperTheme.clipboardWarningColor.opacity(0.10), in: RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous))
    }

    private func permissionAction(_ title: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(fonts.caption)
                .foregroundStyle(paperTheme.inkColor)
                .lineLimit(2)
            Spacer()
            Button(buttonTitle, action: action)
                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
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

private struct PaperMenuRowButton: View {
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

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
        let fonts = PaperFonts(preset: fontPreset)
        Button {
            isHovered = false
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12.5, weight: isHovered ? .medium : .regular))
                    .frame(width: 16)
                    .foregroundStyle(isHovered ? paperTheme.inkColor : paperTheme.secondaryInkColor)
                Text(title)
                    .font(fonts.ui)
                    .foregroundStyle(paperTheme.inkColor)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(fonts.micro)
                        .foregroundStyle(isHovered ? paperTheme.secondaryInkColor : paperTheme.tertiaryInkColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PaperTokens.chipRadius, style: .continuous)
                    .fill(isHovered ? paperTheme.hoverColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PaperTokens.chipRadius, style: .continuous)
                    .strokeBorder(isHovered ? paperTheme.borderColor : Color.clear, lineWidth: PaperTokens.hairline)
            )
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .onDisappear { isHovered = false }
    }
}
