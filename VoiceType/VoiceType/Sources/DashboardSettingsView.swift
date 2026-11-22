import AppKit
import SwiftUI

struct DashboardSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset
    private enum HomeServerCheckState: Equatable {
        case idle
        case checking
        case success(String)
        case failure(String)
    }

    @State private var audioStats = MeetingsStore.AudioStorageStats(
        meetingsWithAudioCount: 0,
        totalBytes: 0,
        expiredMeetingsCount: 0,
        expiredBytes: 0
    )
    @State private var homeServerCheckState: HomeServerCheckState = .idle

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }
    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaperPageHeader(
                    "Настройки",
                    subtitle: "API-ключи, поведение хоткея, параметры встреч и системные разрешения",
                    systemImage: "gearshape",
                    tileTint: PaperTokens.settingsSlate
                )

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

                homeServerSettingsCard

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

                    Divider().overlay(paperTheme.borderColor)

                    settingRow(
                        "Шрифт интерфейса",
                        caption: "Выбор между New York + SF, Cormorant + Inter и системным SF."
                    ) {
                        Picker("", selection: $settings.fontPreset) {
                            ForEach(FontPreset.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    Divider().overlay(paperTheme.borderColor)

                    settingRow(
                        "Значок в Dock",
                        caption: "Иконка в строке меню доступна всегда."
                    ) {
                        Toggle("", isOn: $settings.showDockIcon)
                            .labelsHidden()
                            .toggleStyle(PaperToggleStyle())
                    }
                }

                settingsCard("Индикатор записи") {
                    settingRow("Положение на экране") {
                        Picker("", selection: $settings.indicatorPosition) {
                            ForEach(IndicatorPosition.allCases) { pos in
                                Text(pos.rawValue).tag(pos)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    if settings.indicatorPosition == .top {
                        Divider().overlay(paperTheme.borderColor)

                        settingRow(
                            "Размещение",
                            caption: "На Mac без выреза «Из выреза» работает как «Под строкой меню»."
                        ) {
                            Picker("", selection: $settings.indicatorPlacement) {
                                ForEach(IndicatorPlacement.allCases) { placement in
                                    Text(placement.rawValue).tag(placement)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                    }

                    Divider().overlay(paperTheme.borderColor)

                    settingRow("Вид обработки") {
                        Picker("", selection: $settings.processingLook) {
                            ForEach(ProcessingLook.allCases) { look in
                                Text(look.rawValue).tag(look)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                settingsCard("Голос и диктовка") {
                    settingRow("Клавиша записи") {
                        HStack(spacing: 8) {
                            Picker("", selection: $settings.shortcutKey) {
                                ForEach(ShortcutKey.allCases) { key in
                                    Text(key.displayName).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                            .onChange(of: settings.shortcutKey) { _, _ in
                                appState.restartHotkeyListener()
                            }

                            Picker("", selection: $settings.shortcutSide) {
                                ForEach(ShortcutSide.allCases) { side in
                                    Text(side.rawValue).tag(side)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            .onChange(of: settings.shortcutSide) { _, _ in
                                appState.restartHotkeyListener()
                            }
                        }
                    }

                    Divider().overlay(paperTheme.borderColor)

                    settingRow(
                        "Режим записи",
                        caption: settings.shortcutMode.descriptionText
                    ) {
                        Picker("", selection: $settings.shortcutMode) {
                            ForEach(ShortcutMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                        .onChange(of: settings.shortcutMode) { _, _ in
                            appState.refreshPermissionsAndHotkey()
                        }
                    }

                    Divider().overlay(paperTheme.borderColor)

                    settingRow("Вставка текста") {
                        Picker("", selection: $settings.pasteMode) {
                            ForEach(PasteMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }

                    Divider().overlay(paperTheme.borderColor)

                    settingRow(
                        "Восстанавливать буфер обмена",
                        caption: "Возвращает прежнее содержимое буфера через ~400 мс после автовставки."
                    ) {
                        Toggle("", isOn: $settings.restoreClipboard)
                            .labelsHidden()
                            .toggleStyle(PaperToggleStyle())
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
        .background { PaperBackground() }
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

    private var homeServerSettingsCard: some View {
        settingsCard("Домашний сервер (шлюз диктовки)") {
            settingRow(
                "Использовать домашний сервер",
                caption: "Отправляет сжатое аудио (Opus 24 кбит/с) на шлюз в Tailscale. При недоступности за 3 с автоматически переключается на gapi.uz."
            ) {
                Toggle("", isOn: $settings.useHomeServer)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(theme.accent)
            }

            Divider().overlay(theme.border)

            settingRow(
                "Адрес шлюза",
                caption: "Например: http://100.79.78.37:8790"
            ) {
                TextField(HomeServerConfig.defaultURLString, text: $settings.homeServerURL)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: 280)
                    .onChange(of: settings.homeServerURL) { _, _ in
                        homeServerCheckState = .idle
                    }
            }

            Divider().overlay(theme.border)

            settingRow(
                "Токен авторизации",
                caption: "Хранится только в macOS Keychain, не сохраняется в настройках и логах."
            ) {
                SecureField("Bearer-токен шлюза", text: $settings.homeServerToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180, maxWidth: 280)
                    .onChange(of: settings.homeServerToken) { _, _ in
                        homeServerCheckState = .idle
                    }
            }

            Divider().overlay(theme.border)

            settingRow(
                "Режим распознавания",
                caption: "«Авто» выбирает Gapi для узбекского и Parakeet → Whisper → Gapi для русского и английского."
            ) {
                Picker("", selection: $settings.homeServerEngine) {
                    ForEach(HomeServerEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider().overlay(theme.border)

            settingRow(
                "Подсказка языка",
                caption: "Передаётся в параметр lang шлюза (auto, ru, uz, en)."
            ) {
                Picker("", selection: $settings.homeServerLanguage) {
                    ForEach(HomeServerLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider().overlay(theme.border)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 16) {
                    settingLabel(
                        "Проверка соединения",
                        caption: "Запрос GET /v1/health с проверкой токена и доступных движков."
                    )
                    Spacer(minLength: 8)
                    Button {
                        checkHomeServerConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if case .checking = homeServerCheckState {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("Проверить соединение")
                        }
                    }
                    .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                    .disabled(homeServerCheckState == .checking)
                }

                homeServerCheckStatusView
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var homeServerCheckStatusView: some View {
        switch homeServerCheckState {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 5) {
                ClaudeIcon(name: "network", size: 10.5, weight: .light)
                Text("Подключаюсь к шлюзу…")
                    .font(ClaudeFonts.micro)
            }
            .foregroundStyle(theme.secondaryInk)
        case .success(let summary):
            HStack(spacing: 5) {
                ClaudeIcon(name: "checkmark.circle", size: 10.5, weight: .light)
                Text(summary)
                    .font(ClaudeFonts.micro)
            }
            .foregroundStyle(theme.success)
        case .failure(let message):
            HStack(spacing: 5) {
                ClaudeIcon(name: "exclamationmark.triangle", size: 10.5, weight: .light)
                Text(message)
                    .font(ClaudeFonts.micro)
            }
            .foregroundStyle(theme.warning)
        }
    }

    private func checkHomeServerConnection() {
        homeServerCheckState = .checking
        let config = settings.homeServerConfig
        Task {
            do {
                let health = try await HomeServerProvider(config: config).checkHealth()
                let available = health.availableEngines
                let enginesText = available.isEmpty ? "нет активных движков" : available.joined(separator: ", ")
                if health.ok {
                    homeServerCheckState = .success("Подключено (\(health.latencyMs) мс) · движки: \(enginesText)")
                } else {
                    homeServerCheckState = .failure("Шлюз ответил ok=false (\(health.latencyMs) мс) · движки: \(enginesText)")
                }
            } catch {
                homeServerCheckState = .failure(error.localizedDescription)
            }
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
                    HStack(spacing: 5) {
                        ClaudeIcon(name: "waveform", size: 10.5, weight: .light)
                        Text("На диске: \(formattedBytes(audioStats.totalBytes)) (\(meetingsCountLabel(audioStats.meetingsWithAudioCount)))")
                            .font(ClaudeFonts.micro)
                    }
                    .foregroundStyle(theme.secondaryInk)
                } else {
                    HStack(spacing: 5) {
                        ClaudeIcon(name: "checkmark.circle", size: 10.5, weight: .light)
                        Text("Сохранённых аудиофайлов нет")
                            .font(ClaudeFonts.micro)
                    }
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
                        .font(ClaudeFonts.ui)
                        .foregroundStyle(theme.ink)

                    if !settings.exportDestination.isEmpty {
                        Button {
                            settings.exportDestination = ""
                        } label: {
                            ClaudeIcon(name: "xmark", size: 10, weight: .regular)
                                .foregroundStyle(theme.secondaryInk)
                        }
                        .buttonStyle(.plain)
                        .help("Очистить")
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
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
            HStack(spacing: 5) {
                ClaudeIcon(name: "checkmark.circle", size: 10.5, weight: .light)
                Text("Экспорт по Webhook URL (\(url.host ?? url.absoluteString))")
                    .font(ClaudeFonts.micro)
            }
            .foregroundStyle(theme.success)
        case .folder(let folderURL):
            let exists = FileManager.default.fileExists(atPath: folderURL.path)
            HStack(spacing: 5) {
                ClaudeIcon(name: exists ? "checkmark.circle" : "folder.badge.plus", size: 10.5, weight: .light)
                Text(exists ? "Папка найдена: \(folderURL.lastPathComponent)" : "Папка будет создана при экспорте")
                    .font(ClaudeFonts.micro)
            }
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
        PaperSettingGroup(title, content: content)
    }

    private func settingRow<Control: View>(
        _ title: String,
        caption: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        PaperSettingRow(title, caption: caption, control: control)
    }

    private func settingLabel(_ title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(fonts.uiMedium)
                .foregroundStyle(paperTheme.inkColor)
            if let caption {
                Text(caption)
                    .font(fonts.caption)
                    .foregroundStyle(paperTheme.secondaryInkColor)
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
            ClaudeIcon(name: granted ? "checkmark.circle" : "exclamationmark.triangle", size: 12.5, weight: .light)
                .foregroundStyle(granted ? theme.success : theme.warning)
            Text(status)
                .font(ClaudeFonts.smallMedium)
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
