import AppKit
import SwiftUI

struct DashboardSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore
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
    @State private var showAdvanced = false

    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PaperPageHeader(
                        "Настройки",
                        subtitle: "Клавиша диктовки, индикатор, внешний вид, ключи API и разрешения.",
                        systemImage: "gearshape",
                        tileTint: PaperTokens.settingsSlate
                    )

                    dictationGroup
                    indicatorGroup
                    appearanceGroup
                    apiKeysGroup
                    permissionsGroup
                        .id("permissions")
                    advancedGroup
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(PaperTokens.contentPadding)
            }
            .onAppear {
                if appState.focusPermissionsInSettings {
                    appState.focusPermissionsInSettings = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            scrollProxy.scrollTo("permissions", anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: appState.focusPermissionsInSettings) { _, shouldScroll in
                if shouldScroll {
                    appState.focusPermissionsInSettings = false
                    withAnimation(.easeOut(duration: 0.2)) {
                        scrollProxy.scrollTo("permissions", anchor: .top)
                    }
                }
            }
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

    // MARK: - Groups

    private var dictationGroup: some View {
        PaperSettingGroup("Диктовка") {
            PaperSettingRow(
                "Клавиша и сторона",
                caption: "Клавиша-модификатор для запуска диктовки из любого приложения.",
                systemImage: "command",
                tileTint: PaperTokens.dictationBlue
            ) {
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

            hairlineDivider

            PaperSettingRow(
                "Режим клавиши",
                caption: settings.shortcutMode.descriptionText,
                systemImage: "hand.tap",
                tileTint: PaperTokens.dictationBlue
            ) {
                PaperSegmentedControl(
                    options: ShortcutMode.allCases.map { .init(id: $0, title: $0.shortTitle) },
                    selection: $settings.shortcutMode,
                    compact: true
                )
                .onChange(of: settings.shortcutMode) { _, _ in
                    appState.refreshPermissionsAndHotkey()
                }
            }

            hairlineDivider

            PaperSettingRow(
                "Вставка текста",
                caption: "Если автовставка невозможна, текст останется в буфере обмена.",
                systemImage: "doc.on.clipboard",
                tileTint: PaperTokens.dictationBlue
            ) {
                PaperSegmentedControl(
                    options: PasteMode.allCases.map { .init(id: $0, title: $0.shortTitle) },
                    selection: $settings.pasteMode,
                    compact: true
                )
            }

            hairlineDivider

            PaperSettingRow(
                "Восстанавливать буфер обмена",
                caption: "Возвращает прежнее содержимое буфера через ~400 мс после автовставки.",
                systemImage: "arrow.uturn.backward",
                tileTint: PaperTokens.dictationBlue
            ) {
                Toggle("", isOn: $settings.restoreClipboard)
                    .labelsHidden()
                    .toggleStyle(PaperToggleStyle())
            }

            hairlineDivider

            PaperSettingRow(
                "Обработка текста",
                caption: "Текст отправляется в Anthropic API. Без ключа текст вставляется как распознан.",
                systemImage: "sparkles",
                tileTint: PaperTokens.dictationBlue
            ) {
                Picker("", selection: $settings.cleanupStyle) {
                    ForEach(CleanupStyle.allCases) { style in
                        Text(style.shortTitle).tag(style)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
        }
    }

    private var indicatorGroup: some View {
        PaperSettingGroup("Индикатор записи") {
            PaperSettingRow(
                "Положение на экране",
                caption: "Плавающая волна видна только во время диктовки и не забирает фокус.",
                systemImage: "rectangle.topthird.inset.filled",
                tileTint: PaperTokens.historyGreen
            ) {
                PaperSegmentedControl(
                    options: IndicatorPosition.allCases.map { .init(id: $0, title: $0.rawValue) },
                    selection: $settings.indicatorPosition,
                    compact: true
                )
            }

            if settings.indicatorPosition == .top {
                hairlineDivider

                PaperSettingRow(
                    "Размещение",
                    caption: "На Mac без выреза «Из выреза» работает как «Под строкой меню».",
                    systemImage: "menubar.rectangle",
                    tileTint: PaperTokens.historyGreen
                ) {
                    Picker("", selection: $settings.indicatorPlacement) {
                        ForEach(IndicatorPlacement.allCases) { placement in
                            Text(placement.rawValue).tag(placement)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)
                }
            }

            hairlineDivider

            PaperSettingRow(
                "Вид обработки",
                caption: "Анимация на время распознавания и обработки текста.",
                systemImage: "waveform.path",
                tileTint: PaperTokens.historyGreen
            ) {
                Picker("", selection: $settings.processingLook) {
                    ForEach(ProcessingLook.allCases) { look in
                        Text(look.rawValue).tag(look)
                    }
                }
                .labelsHidden()
                .frame(width: 210)
            }
        }
    }

    private var appearanceGroup: some View {
        PaperSettingGroup("Внешний вид") {
            PaperSettingRow(
                "Оформление",
                caption: "По умолчанию совпадает с системной темой macOS.",
                systemImage: "circle.lefthalf.filled",
                tileTint: PaperTokens.settingsSlate
            ) {
                PaperSegmentedControl(
                    options: AppearanceMode.allCases.map { .init(id: $0, title: $0.rawValue) },
                    selection: $settings.appearance,
                    compact: true
                )
            }

            hairlineDivider

            PaperSettingRow(
                "Шрифт интерфейса",
                caption: "Выбор между New York + SF, Cormorant + Inter и системным SF.",
                systemImage: "textformat",
                tileTint: PaperTokens.settingsSlate
            ) {
                Picker("", selection: $settings.fontPreset) {
                    ForEach(FontPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            hairlineDivider

            PaperSettingRow(
                "Значок в Dock",
                caption: "Значок в строке меню доступен всегда.",
                systemImage: "dock.rectangle",
                tileTint: PaperTokens.settingsSlate
            ) {
                Toggle("", isOn: $settings.showDockIcon)
                    .labelsHidden()
                    .toggleStyle(PaperToggleStyle())
            }
        }
    }

    private var apiKeysGroup: some View {
        PaperSettingGroup("Ключи API") {
            PaperSettingRow(
                "Токен gapi.uz",
                caption: "Аудио для распознавания отправляется на console.gapi.uz. Токен хранится в Keychain.",
                systemImage: "key",
                tileTint: PaperTokens.dictionaryTeal
            ) {
                PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                    SecureField("Вставьте API-токен", text: $settings.gapiToken)
                        .textFieldStyle(.plain)
                        .font(fonts.ui)
                }
                .frame(width: 240)
            }

            hairlineDivider

            PaperSettingRow(
                "Anthropic API key",
                caption: "Необязательно. Используется для обработки диктовки и рекапов встреч. Хранится в Keychain.",
                systemImage: "lock.shield",
                tileTint: PaperTokens.dictionaryTeal
            ) {
                PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                    SecureField("sk-ant-...", text: $settings.anthropicApiKey)
                        .textFieldStyle(.plain)
                        .font(fonts.ui)
                }
                .frame(width: 240)
            }
        }
    }

    private var permissionsGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Разрешения")
                .font(fonts.captionMedium)
                .foregroundStyle(paperTheme.secondaryInkColor)
                .padding(.horizontal, 4)

            PermissionsChecklistView(includeScreenCapture: true, showAllWhenGranted: true)
        }
    }

    // MARK: - Collapsible Advanced Group

    private var advancedGroup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(paperTheme.secondaryInkColor)
                        .frame(width: 14)

                    Text("Дополнительно")
                        .font(fonts.uiMedium)
                        .foregroundStyle(paperTheme.inkColor)

                    Text("Домашний сервер, параметры встреч и диалект")
                        .font(fonts.caption)
                        .foregroundStyle(paperTheme.secondaryInkColor)
                        .lineLimit(1)

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    paperTheme.surfaceColor.opacity(0.45),
                    in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                        .strokeBorder(paperTheme.borderColor, lineWidth: PaperTokens.hairline)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Дополнительные настройки")

            if showAdvanced {
                VStack(alignment: .leading, spacing: 18) {
                    homeServerSettingsCard

                    PaperSettingGroup("Язык и встречи") {
                        PaperSettingRow(
                            "Узбекский диалект",
                            caption: "«Ташкентский» сохраняет живую разговорную речь (qivommiz, kevotti, qatta).",
                            systemImage: "character.bubble",
                            tileTint: PaperTokens.meetingsIndigo
                        ) {
                            Picker("", selection: $settings.uzbekStyle) {
                                ForEach(UzbekStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        hairlineDivider

                        PaperSettingRow(
                            "Сервер распознавания встреч",
                            caption: "URL внешнего сервера Whisper; если пусто — используется облако gapi.uz.",
                            systemImage: "server.rack",
                            tileTint: PaperTokens.meetingsIndigo
                        ) {
                            PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                                TextField("https://... или http://...", text: $settings.whisperServerURL)
                                    .textFieldStyle(.plain)
                                    .font(fonts.ui)
                            }
                            .frame(width: 240)
                        }

                        hairlineDivider

                        PaperSettingRow(
                            "Источник звука встреч",
                            caption: "«Микрофон + Системный звук» разделяет каналы («Вы» и «Собеседники»).",
                            systemImage: "person.2.wave.2",
                            tileTint: PaperTokens.meetingsIndigo
                        ) {
                            Picker("", selection: $settings.meetingAudioSource) {
                                ForEach(MeetingAudioSource.allCases) { source in
                                    Text(source.rawValue).tag(source)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }

                        hairlineDivider

                        exportDestinationRow

                        hairlineDivider

                        PaperSettingRow(
                            "Резюме на стороне gapi (×1.3)",
                            caption: "Применимо при отправке встреч в gapi.uz.",
                            systemImage: "doc.plaintext",
                            tileTint: PaperTokens.meetingsIndigo
                        ) {
                            Toggle("", isOn: $settings.enableGapiSummary)
                                .labelsHidden()
                                .toggleStyle(PaperToggleStyle())
                        }

                        hairlineDivider

                        audioRetentionRow
                    }
                }
            }
        }
    }

    private var homeServerSettingsCard: some View {
        PaperSettingGroup("Домашний сервер (шлюз диктовки)") {
            PaperSettingRow(
                "Использовать домашний сервер",
                caption: "Отправляет сжатое аудио (Opus 24 кбит/с) на шлюз в Tailscale. При недоступности за 3 с переключается на gapi.uz.",
                systemImage: "network",
                tileTint: PaperTokens.dictationBlue
            ) {
                Toggle("", isOn: $settings.useHomeServer)
                    .labelsHidden()
                    .toggleStyle(PaperToggleStyle())
            }

            hairlineDivider

            PaperSettingRow(
                "Адрес шлюза",
                caption: "Например: http://100.79.78.37:8790",
                systemImage: "link",
                tileTint: PaperTokens.dictationBlue
            ) {
                PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                    TextField(HomeServerConfig.defaultURLString, text: $settings.homeServerURL)
                        .textFieldStyle(.plain)
                        .font(fonts.ui)
                        .onChange(of: settings.homeServerURL) { _, _ in
                            homeServerCheckState = .idle
                        }
                }
                .frame(width: 240)
            }

            hairlineDivider

            PaperSettingRow(
                "Токен авторизации",
                caption: "Хранится только в Keychain.",
                systemImage: "key.horizontal",
                tileTint: PaperTokens.dictationBlue
            ) {
                PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                    SecureField("Bearer-токен шлюза", text: $settings.homeServerToken)
                        .textFieldStyle(.plain)
                        .font(fonts.ui)
                        .onChange(of: settings.homeServerToken) { _, _ in
                            homeServerCheckState = .idle
                        }
                }
                .frame(width: 240)
            }

            hairlineDivider

            PaperSettingRow(
                "Режим распознавания",
                caption: "«Авто» выбирает Gapi для узбекского и Parakeet → Whisper → Gapi для русского и английского.",
                systemImage: "cpu",
                tileTint: PaperTokens.dictationBlue
            ) {
                Picker("", selection: $settings.homeServerEngine) {
                    ForEach(HomeServerEngine.allCases) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            hairlineDivider

            PaperSettingRow(
                "Подсказка языка",
                caption: "Передаётся в параметр lang шлюза (auto, ru, uz, en).",
                systemImage: "globe",
                tileTint: PaperTokens.dictationBlue
            ) {
                Picker("", selection: $settings.homeServerLanguage) {
                    ForEach(HomeServerLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            hairlineDivider

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Проверка соединения")
                            .font(fonts.uiMedium)
                            .foregroundStyle(paperTheme.inkColor)
                        Text("Запрос GET /v1/health с проверкой токена и доступных движков.")
                            .font(fonts.caption)
                            .foregroundStyle(paperTheme.secondaryInkColor)
                    }
                    Spacer(minLength: 8)
                    Button {
                        checkHomeServerConnection()
                    } label: {
                        HStack(spacing: 6) {
                            if case .checking = homeServerCheckState {
                                ProgressView().controlSize(.small)
                            }
                            Text("Проверить соединение")
                        }
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
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
            HStack(spacing: 6) {
                Image(systemName: "network")
                    .font(.system(size: 11))
                Text("Подключаюсь к шлюзу…")
                    .font(fonts.caption)
            }
            .foregroundStyle(paperTheme.secondaryInkColor)
        case .success(let summary):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 11.5))
                Text(summary)
                    .font(fonts.caption)
            }
            .foregroundStyle(paperTheme.successColor)
        case .failure(let message):
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(paperTheme.errorColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(message)
                        .font(fonts.captionMedium)
                        .foregroundStyle(paperTheme.inkColor)
                    Text("Текущие настройки сохранены; диктовка продолжит работать через gapi.uz.")
                        .font(fonts.micro)
                        .foregroundStyle(paperTheme.secondaryInkColor)
                }
                Spacer()
                Button("Повторить") {
                    checkHomeServerConnection()
                }
                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
            }
            .padding(10)
            .paperSurface(level: .l1Inset, cornerRadius: PaperTokens.controlRadius)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Хранение аудиозаписей")
                        .font(fonts.uiMedium)
                        .foregroundStyle(paperTheme.inkColor)
                    Text("Оригиналы аудио встреч удаляются по сроку; рекап и транскрипт сохраняются.")
                        .font(fonts.caption)
                        .foregroundStyle(paperTheme.secondaryInkColor)
                }
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
                Text(
                    audioStats.totalBytes > 0
                        ? "На диске: \(formattedBytes(audioStats.totalBytes)) (\(meetingsCountLabel(audioStats.meetingsWithAudioCount)))"
                        : "Сохранённых аудиофайлов нет."
                )
                .font(fonts.micro)
                .foregroundStyle(paperTheme.secondaryInkColor)

                Spacer()

                if audioStats.expiredMeetingsCount > 0 {
                    Button("Очистить устаревшие (\(formattedBytes(audioStats.expiredBytes)))") {
                        appState.cleanupExpiredMeetingAudio()
                        refreshAudioStats()
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var exportDestinationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Автоэкспорт рекапов")
                    .font(fonts.uiMedium)
                    .foregroundStyle(paperTheme.inkColor)
                Text("Необязательно. Путь к папке (*_vt.md) или URL Webhook JSON.")
                    .font(fonts.caption)
                    .foregroundStyle(paperTheme.secondaryInkColor)
            }

            HStack(spacing: 8) {
                PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 5.5) {
                    HStack(spacing: 6) {
                        TextField("Путь к папке или https://...", text: $settings.exportDestination)
                            .textFieldStyle(.plain)
                            .font(fonts.ui)
                            .foregroundStyle(paperTheme.inkColor)

                        if !settings.exportDestination.isEmpty {
                            Button {
                                settings.exportDestination = ""
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(paperTheme.secondaryInkColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button("Выбрать папку…") {
                    chooseExportFolder()
                }
                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
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
            Text("Экспорт по Webhook URL (\(url.host ?? url.absoluteString))")
                .font(fonts.micro)
                .foregroundStyle(paperTheme.successColor)
        case .folder(let folderURL):
            let exists = FileManager.default.fileExists(atPath: folderURL.path)
            Text(exists ? "Папка найдена: \(folderURL.lastPathComponent)" : "Папка будет создана при экспорте.")
                .font(fonts.micro)
                .foregroundStyle(exists ? paperTheme.successColor : paperTheme.secondaryInkColor)
        }
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(paperTheme.borderColor)
            .frame(height: PaperTokens.hairline)
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
        if mod100 >= 11 && mod100 <= 14 { return "\(count) встреч" }
        switch mod10 {
        case 1: return "\(count) встреча"
        case 2, 3, 4: return "\(count) встречи"
        default: return "\(count) встреч"
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
}
