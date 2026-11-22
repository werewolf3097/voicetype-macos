import AppKit
import SwiftUI

struct DashboardSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore
    @EnvironmentObject var entitlement: LocalProEntitlement
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    private enum ConnectionCheckState: Equatable {
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
    @State private var homeServerCheckState: ConnectionCheckState = .idle
    @State private var llmCheckState: ConnectionCheckState = .idle
    @State private var fetchedModels: [LLMProviderKind: [String]] = [:]
    @State private var isLoadingModels = false
    @State private var modelsFetchError: String? = nil
    @State private var showGapiKeyHelp = false
    @State private var showLLMKeyHelp = false
    @State private var showLLMModelHelp = false
    @State private var showAdvanced = false
    @State private var inputDevices: [AudioInputDevice] = []

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
                    audioAndMicGroup
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
            refreshInputDevices()
        }
        .onChange(of: settings.meetingAudioRetention) { _, _ in
            refreshAudioStats()
            refreshInputDevices()
        }
        .onChange(of: meetingsStore.meetings) { _, _ in
            refreshAudioStats()
            refreshInputDevices()
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
                caption: "\(settings.cleanupStyle.oneLineDescription) \(settings.activeLLMConfig.privacyCaption)",
                systemImage: "sparkles",
                tileTint: PaperTokens.dictationBlue
            ) {
                HStack(spacing: 6) {
                    Picker("", selection: $settings.cleanupStyle) {
                        ForEach(CleanupStyle.allCases) { style in
                            Text("\(style.shortTitle) (\(style.loadLabel))").tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)

                    CleanupStyleGuideButton()
                }
            }

            if settings.cleanupStyle != .off {
                hairlineDivider

                PaperSettingRow(
                    "Сжимать (без воды)",
                    caption: "Превращает длинную речь в ёмкую мысль без повторов и вводных слов.",
                    systemImage: "arrow.down.right.and.arrow.up.left",
                    tileTint: PaperTokens.dictationBlue
                ) {
                    Toggle("", isOn: $settings.cleanupCompactMode)
                        .labelsHidden()
                        .toggleStyle(PaperToggleStyle())
                }

                hairlineDivider

                PaperSettingRow(
                    "Списки и абзацы",
                    caption: "Оформляет перечисления, шаги и задачи в аккуратный список или абзацы.",
                    systemImage: "list.bullet",
                    tileTint: PaperTokens.dictationBlue
                ) {
                    Toggle("", isOn: $settings.cleanupStructuredLists)
                        .labelsHidden()
                        .toggleStyle(PaperToggleStyle())
                }

                hairlineDivider

                PaperSettingRow(
                    "Сохранять код и термины",
                    caption: "Не переводит и не искажает пути, URL, команды и camelCase/snake_case.",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    tileTint: PaperTokens.dictationBlue
                ) {
                    Toggle("", isOn: $settings.cleanupPreserveTechTerms)
                        .labelsHidden()
                        .toggleStyle(PaperToggleStyle())
                }

                hairlineDivider

                PaperSettingRow(
                    "Автотон по приложению",
                    caption: "Telegram/WhatsApp/Slack → Дружественный; Mail/Notes/IDE → Деловой.",
                    systemImage: "app.badge.checkmark",
                    tileTint: PaperTokens.dictationBlue
                ) {
                    Toggle("", isOn: $settings.cleanupAutoToneByApp)
                        .labelsHidden()
                        .toggleStyle(PaperToggleStyle())
                }

                hairlineDivider

                PaperSettingRow(
                    "Свой акцент (доп. правило)",
                    caption: "Необязательно. Например: «Переводи на английский» или «Пиши без эмодзи».",
                    systemImage: "text.bubble",
                    tileTint: PaperTokens.dictationBlue
                ) {
                    PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                        TextField("Дополнительная инструкция для ИИ", text: $settings.cleanupCustomInstruction)
                            .textFieldStyle(.plain)
                            .font(fonts.ui)
                    }
                    .frame(width: 240)
                }
            }
        }
    }

    private var audioAndMicGroup: some View {
        PaperSettingGroup("Микрофон и звуки") {
            PaperSettingRow(
                "Микрофон",
                caption: "Микрофон включается только во время диктовки.",
                systemImage: "mic",
                tileTint: PaperTokens.dictationBlue
            ) {
                HStack(spacing: 8) {
                    Picker("", selection: $settings.selectedMicrophoneUID) {
                        Text("Системный по умолчанию").tag("")
                        ForEach(inputDevices) { dev in
                            Text(dev.isDefault ? "\(dev.name) (по умолчанию)" : dev.name)
                                .tag(dev.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 210)

                    Button {
                        refreshInputDevices()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                    .help("Обновить список микрофонов")
                    .accessibilityLabel("Обновить список микрофонов")
                }
            }

            hairlineDivider

            PaperSettingRow(
                "Использовать микрофон Mac вместо Bluetooth",
                caption: "Bluetooth-наушники звучат хуже, пока включён их микрофон.",
                systemImage: "headphones",
                tileTint: PaperTokens.dictationBlue
            ) {
                Toggle("", isOn: $settings.preferBuiltInMicOverBluetooth)
                    .labelsHidden()
                    .toggleStyle(PaperToggleStyle())
            }

            hairlineDivider

            PaperSettingRow(
                "Звуковые сигналы",
                caption: "Короткие тихие сигналы при старте, завершении записи и вставке.",
                systemImage: "speaker.wave.2",
                tileTint: PaperTokens.dictationBlue
            ) {
                Toggle("", isOn: $settings.soundsEnabled)
                    .labelsHidden()
                    .toggleStyle(PaperToggleStyle())
            }

            if settings.soundsEnabled {
                hairlineDivider

                PaperSettingRow(
                    "Громкость сигналов",
                    caption: "Нажмите «Проверить», чтобы услышать сигнал.",
                    systemImage: "speaker.wave.1",
                    tileTint: PaperTokens.dictationBlue
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $settings.soundVolume, in: 0.05...1.0, step: 0.05)
                            .frame(width: 140)
                        Button("Проверить") {
                            SoundCuePlayer.shared.play(
                                .startRecording,
                                enabled: settings.soundsEnabled,
                                volume: settings.soundVolume
                            )
                        }
                        .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                    }
                }
            }
        }
    }

    private func refreshInputDevices() {
        inputDevices = AudioInputDeviceManager.availableInputDevices()
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
                "Тема оформления",
                caption: "Светлая, тёмная или автоматическое переключение вместе с macOS.",
                systemImage: "circle.lefthalf.filled",
                tileTint: PaperTokens.settingsSlate
            ) {
                PaperSegmentedControl(
                    options: [
                        .init(id: .system, title: "Системная"),
                        .init(id: .light, title: "Светлая"),
                        .init(id: .dark, title: "Тёмная")
                    ],
                    selection: $settings.appearance,
                    compact: true
                )
            }

            hairlineDivider

            PaperSettingRow(
                "Шрифт интерфейса",
                caption: "Заголовки и текст во всех разделах, включая «Встречи».",
                systemImage: "textformat",
                tileTint: PaperTokens.settingsSlate
            ) {
                Picker("", selection: $settings.fontPreset) {
                    ForEach(FontPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
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
        VStack(alignment: .leading, spacing: 20) {
            PaperSettingGroup("Распознавание речи (STT)") {
                PaperSettingRow(
                    "Токен gapi.uz",
                    caption: "Отправляет голос на console.gapi.uz (особенно хорошо для узбекской речи). Хранится в Keychain.",
                    systemImage: "key",
                    tileTint: PaperTokens.dictionaryTeal
                ) {
                    HStack(spacing: 6) {
                        PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                            SecureField("Вставьте API-токен", text: $settings.gapiToken)
                                .textFieldStyle(.plain)
                                .font(fonts.ui)
                        }
                        .frame(width: 210)

                        helpPopoverButton(
                            isPresented: $showGapiKeyHelp,
                            title: "Где взять токен gapi.uz",
                            message: "Войдите в личный кабинет console.gapi.uz, откройте вкладку «API-токены» и создайте новый токен.",
                            primaryLinkTitle: "Открыть console.gapi.uz",
                            primaryURL: URL(string: "https://console.gapi.uz")!
                        )
                    }
                }
            }

            PaperSettingGroup("Обработка текста (LLM)") {
                PaperSettingRow(
                    "Сервис обработки",
                    caption: settings.activeLLMConfig.privacyCaption,
                    systemImage: "sparkles",
                    tileTint: PaperTokens.dictionaryTeal
                ) {
                    PaperSegmentedControl(
                        options: LLMProviderKind.allCases.map { .init(id: $0, title: $0.shortTitle) },
                        selection: $settings.llmProvider,
                        compact: true
                    )
                    .onChange(of: settings.llmProvider) { _, _ in
                        llmCheckState = .idle
                        modelsFetchError = nil
                    }
                }

                hairlineDivider

                if settings.llmProvider == .openaiCompatible {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Быстрый выбор совместимого сервиса")
                            .font(fonts.captionMedium)
                            .foregroundStyle(paperTheme.secondaryInkColor)
                        ClaudeFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(OpenAICompatiblePreset.allCases) { preset in
                                Button(preset.rawValue) {
                                    settings.customLLMBaseURL = preset.baseURL
                                    settings.customLLMModel = preset.suggestedModel
                                    llmCheckState = .idle
                                }
                                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true, isCapsule: true))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    hairlineDivider

                    PaperSettingRow(
                        "Адрес API (Base URL)",
                        caption: "Например: https://openrouter.ai/api/v1 или http://localhost:11434/v1",
                        systemImage: "link",
                        tileTint: PaperTokens.dictionaryTeal
                    ) {
                        PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                            TextField("https://...", text: $settings.customLLMBaseURL)
                                .textFieldStyle(.plain)
                                .font(fonts.ui)
                                .onChange(of: settings.customLLMBaseURL) { _, _ in
                                    llmCheckState = .idle
                                }
                        }
                        .frame(width: 240)
                    }

                    hairlineDivider
                }

                PaperSettingRow(
                    "API-ключ (\(settings.llmProvider.shortTitle))",
                    caption: settings.llmProvider.requiresAPIKey
                        ? "Хранится только в macOS Keychain."
                        : "Хранится в Keychain. Для локальных Ollama / LM Studio можно оставить пустым.",
                    systemImage: "lock.shield",
                    tileTint: PaperTokens.dictionaryTeal
                ) {
                    HStack(spacing: 6) {
                        PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                            SecureField(settings.llmProvider.apiKeyPlaceholder, text: currentLLMAPIKeyBinding)
                                .textFieldStyle(.plain)
                                .font(fonts.ui)
                                .onChange(of: currentLLMAPIKeyBinding.wrappedValue) { _, _ in
                                    llmCheckState = .idle
                                }
                        }
                        .frame(width: 210)

                        helpPopoverButton(
                            isPresented: $showLLMKeyHelp,
                            title: "Где получить ключ \(settings.llmProvider.shortTitle)",
                            message: settings.llmProvider.keyHelpText,
                            primaryLinkTitle: "Открыть кабинет ключей",
                            primaryURL: settings.llmProvider.keyPortalURL,
                            secondaryLinkTitle: "Документация моделей",
                            secondaryURL: settings.llmProvider.modelsDocsURL
                        )
                    }
                }

                hairlineDivider

                PaperSettingRow(
                    "Модель",
                    caption: modelsFetchError ?? "По умолчанию (драфт): \(settings.llmProvider.defaultModel). Нажмите на поле, чтобы указать свою.",
                    systemImage: "cpu",
                    tileTint: PaperTokens.dictionaryTeal
                ) {
                    HStack(spacing: 6) {
                        PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 9, verticalPadding: 6) {
                            HStack(spacing: 4) {
                                TextField(settings.llmProvider.defaultModel, text: currentLLMModelBinding)
                                    .textFieldStyle(.plain)
                                    .font(fonts.ui)
                                    .onChange(of: currentLLMModelBinding.wrappedValue) { _, _ in
                                        llmCheckState = .idle
                                    }

                                if !currentLLMModelBinding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Button {
                                        currentLLMModelBinding.wrappedValue = ""
                                        llmCheckState = .idle
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(paperTheme.tertiaryInkColor)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Сбросить к модели по умолчанию")
                                    .accessibilityLabel("Сбросить к модели по умолчанию")
                                }
                            }
                        }
                        .frame(width: 182)

                        Menu {
                            Button("По умолчанию (\(settings.llmProvider.defaultModel))") {
                                currentLLMModelBinding.wrappedValue = ""
                                llmCheckState = .idle
                            }

                            Section("Рекомендуемые") {
                                ForEach(settings.llmProvider.recommendedModels, id: \.id) { item in
                                    Button {
                                        currentLLMModelBinding.wrappedValue = item.id
                                        llmCheckState = .idle
                                    } label: {
                                        Text("\(item.id) — \(item.note)")
                                    }
                                }
                            }

                            if let live = fetchedModels[settings.llmProvider], !live.isEmpty {
                                Section("Доступные по вашему ключу (\(live.count))") {
                                    ForEach(live.prefix(80), id: \.self) { modelID in
                                        Button(modelID) {
                                            currentLLMModelBinding.wrappedValue = modelID
                                            llmCheckState = .idle
                                        }
                                    }
                                }
                            }

                            Divider()

                            Button(fetchedModels[settings.llmProvider] == nil ? "Загрузить список с сервера" : "Обновить список с сервера") {
                                refreshAvailableModels()
                            }
                            .disabled(isLoadingModels || !settings.isLLMConfigured)
                        } label: {
                            Group {
                                if isLoadingModels {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundStyle(paperTheme.inkColor)
                                }
                            }
                            .frame(width: 24, height: 24)
                            .paperSurface(level: .l2OnPaper, cornerRadius: PaperTokens.chipRadius)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Выбрать или загрузить модель с сервера")
                        .accessibilityLabel("Выбрать модель из списка")

                        helpPopoverButton(
                            isPresented: $showLLMModelHelp,
                            title: "Какую модель указать",
                            message: settings.llmProvider.modelsHelpText,
                            primaryLinkTitle: "Список моделей в документации",
                            primaryURL: settings.llmProvider.modelsDocsURL
                        )
                    }
                }

                hairlineDivider

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Проверка подключения")
                                .font(fonts.uiMedium)
                                .foregroundStyle(paperTheme.inkColor)
                            Text("Отправит короткий тестовый запрос к \(settings.llmProvider.rawValue).")
                                .font(fonts.caption)
                                .foregroundStyle(paperTheme.secondaryInkColor)
                        }
                        Spacer(minLength: 8)
                        Button {
                            checkLLMConnection()
                        } label: {
                            HStack(spacing: 6) {
                                if case .checking = llmCheckState {
                                    ProgressView().controlSize(.small)
                                }
                                Text("Проверить")
                            }
                        }
                        .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                        .disabled(llmCheckState == .checking || !settings.isLLMConfigured)
                    }

                    llmCheckStatusView
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var currentLLMAPIKeyBinding: Binding<String> {
        switch settings.llmProvider {
        case .anthropic: return $settings.anthropicApiKey
        case .openai: return $settings.openaiApiKey
        case .gemini: return $settings.geminiApiKey
        case .openaiCompatible: return $settings.customLLMApiKey
        }
    }

    private var currentLLMModelBinding: Binding<String> {
        switch settings.llmProvider {
        case .anthropic: return $settings.anthropicModel
        case .openai: return $settings.openaiModel
        case .gemini: return $settings.geminiModel
        case .openaiCompatible: return $settings.customLLMModel
        }
    }

    @ViewBuilder
    private var llmCheckStatusView: some View {
        switch llmCheckState {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                Image(systemName: "network").font(.system(size: 11))
                Text("Проверяю \(settings.llmProvider.shortTitle)…")
                    .font(fonts.caption)
            }
            .foregroundStyle(paperTheme.secondaryInkColor)
        case .success(let summary):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle").font(.system(size: 11.5))
                Text(summary).font(fonts.caption)
            }
            .foregroundStyle(paperTheme.successColor)
        case .failure(let message):
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(paperTheme.errorColor)
                Text(message)
                    .font(fonts.captionMedium)
                    .foregroundStyle(paperTheme.inkColor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Повторить") {
                    checkLLMConnection()
                }
                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
            }
            .padding(10)
            .paperSurface(level: .l1Inset, cornerRadius: PaperTokens.controlRadius)
        }
    }

    private func checkLLMConnection() {
        llmCheckState = .checking
        let config = settings.activeLLMConfig
        Task {
            do {
                let latencyMs = try await LLMPostProcessor(config: config).testConnection()
                llmCheckState = .success("Подключено · \(config.resolvedModel) (\(latencyMs) мс)")
                refreshAvailableModels()
            } catch {
                llmCheckState = .failure(error.localizedDescription)
            }
        }
    }

    private func refreshAvailableModels() {
        let config = settings.activeLLMConfig
        guard config.isConfigured else { return }
        isLoadingModels = true
        modelsFetchError = nil
        Task {
            defer { isLoadingModels = false }
            do {
                let list = try await LLMPostProcessor(config: config).fetchAvailableModels()
                fetchedModels[config.provider] = list
            } catch {
                modelsFetchError = "Не удалось загрузить список моделей: \(error.localizedDescription)"
            }
        }
    }

    private func helpPopoverButton(
        isPresented: Binding<Bool>,
        title: String,
        message: String,
        primaryLinkTitle: String,
        primaryURL: URL,
        secondaryLinkTitle: String? = nil,
        secondaryURL: URL? = nil
    ) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(paperTheme.secondaryInkColor)
                .frame(width: 22, height: 22)
                .paperSurface(level: .l2OnPaper, cornerRadius: 999)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(fonts.uiMedium)
                    .foregroundStyle(paperTheme.inkColor)

                Text(message)
                    .font(fonts.caption)
                    .foregroundStyle(paperTheme.secondaryInkColor)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button(primaryLinkTitle) {
                        isPresented.wrappedValue = false
                        NSWorkspace.shared.open(primaryURL)
                    }
                    .buttonStyle(PaperButtonStyle(role: .primary, compact: true))

                    if let secondaryLinkTitle, let secondaryURL {
                        Button(secondaryLinkTitle) {
                            isPresented.wrappedValue = false
                            NSWorkspace.shared.open(secondaryURL)
                        }
                        .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                    }
                }
            }
            .padding(14)
            .frame(width: 310)
            .background(paperTheme.baseColor)
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
