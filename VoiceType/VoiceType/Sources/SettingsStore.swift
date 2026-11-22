import Foundation
import CoreGraphics

enum CleanupStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "Без LLM-обработки"
    case grammar = "Умная коррекция (Typeless)"
    case notes = "Заметка"
    case message = "Сообщение/письмо"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .off: return "Без обработки"
        case .grammar: return "Аккуратно"
        case .notes: return "Заметка"
        case .message: return "Сообщение"
        }
    }

    var oneLineDescription: String {
        switch self {
        case .off:
            return "Без обработки: вставит текст так, как он распознан."
        case .grammar:
            return "Аккуратно: расставит знаки и уберёт «э-э», смысл не меняет."
        case .notes:
            return "Заметка: очистит оговорки и оформит тезисы или абзацы."
        case .message:
            return "Сообщение: приведёт речь к связному тексту для чата или письма."
        }
    }

    var systemPrompt: String? {
        switch self {
        case .off:
            return nil
        case .grammar:
            return """
            Ты — интеллектуальный редактор голосовой диктовки в стиле Typeless.
            Тебе дают расшифровку живой речи. Твоя задача — выдать идеально отпунктурованный текст, полностью сохранив авторский тон, лексику и смысл:
            1. Расставь все недостающие запятые, тире, двоеточия, точки и вопросительные знаки по правилам языка.
            2. Убери слова-паразиты («э-э», «эм», «ну», «как бы», «типа», случайные повторы слов подряд).
            3. Обработай устные самоисправления: если говорящий поправил сам себя («давай завтра нет в четверг созвонимся» → «давай в четверг созвонимся»), оставь только итоговый вариант.
            4. Исправь мелкие падежные/фонетические сбои распознавания, но НЕ переписывай фразы в искусственный канцелярит и ничего не придумывай от себя.
            Верни только готовый текст, без кавычек и пояснений.
            """
        case .notes:
            return "Ты редактор. Тебе дают сырую расшифровку голосовой заметки. Приведи её в читаемый вид: убери слова-паразиты и оговорки, разбей на абзацы или пункты, если это уместно. Сохрани язык и смысл оригинала. Верни только готовый текст, без пояснений и кавычек."
        case .message:
            return "Ты редактор. Тебе дают сырую расшифровку голосового сообщения, которое человек хочет отправить как текстовое письмо или чат-сообщение. Приведи его к связному, вежливому тексту сообщения на том же языке, убери слова-паразиты. Не добавляй приветствия и подпись, если их не было. Верни только готовый текст, без пояснений и кавычек."
        }
    }
}

enum PasteMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case autoPaste = "Автовставка (⌘V)"
    case clipboardOnly = "Только в буфер"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .autoPaste: return "Автовставка"
        case .clipboardOnly: return "Только в буфер"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "Как в системе"
    case light = "Светлая"
    case dark = "Тёмная"

    var id: String { rawValue }
}

enum IndicatorPosition: String, CaseIterable, Identifiable, Codable, Sendable {
    case top = "Сверху"
    case bottom = "Снизу"
    case off = "Выключен"

    var id: String { rawValue }
}

enum IndicatorPlacement: String, CaseIterable, Identifiable, Codable, Sendable {
    case fromNotch = "Из выреза"
    case inMenuBar = "В строке меню"
    case belowMenuBar = "Под строкой меню"

    var id: String { rawValue }
}

enum ProcessingLook: String, CaseIterable, Identifiable, Codable, Sendable {
    case flow = "Бегущая волна"
    case pulse = "Пульс"
    case sweep = "Луч"

    var id: String { rawValue }
}

enum MeetingAudioSource: String, CaseIterable, Identifiable, Codable {
    case micAndSystem = "Микрофон + Системный звук"
    case micOnly = "Только микрофон"

    var id: String { rawValue }
}

enum MeetingAudioRetention: String, CaseIterable, Identifiable, Codable {
    case deleteAfterTranscription = "Удалять после расшифровки"
    case oneWeek = "1 неделя"
    case twoWeeks = "2 недели"
    case oneMonth = "1 месяц"
    case threeMonths = "3 месяца"
    case forever = "Хранить всегда"

    var id: String { rawValue }

    /// Количество дней хранения оригинала аудио после даты встречи.
    /// `0` — удалять сразу после успешной расшифровки; `nil` — хранить бессрочно.
    var retentionDays: Int? {
        switch self {
        case .deleteAfterTranscription: return 0
        case .oneWeek: return 7
        case .twoWeeks: return 14
        case .oneMonth: return 30
        case .threeMonths: return 90
        case .forever: return nil
        }
    }
}

final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private let persistSecrets: Bool
    private let syncDockIcon: Bool

    @Published var shortcutKey: ShortcutKey {
        didSet { defaults.set(shortcutKey.rawValue, forKey: "shortcutKey") }
    }
    @Published var shortcutSide: ShortcutSide {
        didSet { defaults.set(shortcutSide.rawValue, forKey: "shortcutSide") }
    }
    @Published var shortcutMode: ShortcutMode {
        didSet { defaults.set(shortcutMode.rawValue, forKey: "shortcutMode") }
    }
    @Published var pasteMode: PasteMode {
        didSet { defaults.set(pasteMode.rawValue, forKey: "pasteMode") }
    }
    @Published var restoreClipboard: Bool {
        didSet { defaults.set(restoreClipboard, forKey: "restoreClipboard") }
    }
    @Published var cleanupStyle: CleanupStyle {
        didSet { defaults.set(cleanupStyle.rawValue, forKey: "cleanupStyle") }
    }
    @Published var uzbekStyle: UzbekStyle {
        didSet { defaults.set(uzbekStyle.rawValue, forKey: "uzbekStyle") }
    }
    @Published var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var paperThemeID: String {
        didSet { defaults.set(paperThemeID, forKey: "paperThemeID") }
    }
    @Published var paperDepth: Double {
        didSet { defaults.set(paperDepth, forKey: "paperDepth") }
    }
    @Published var paperGrainIntensity: Double {
        didSet { defaults.set(paperGrainIntensity, forKey: "paperGrainIntensity") }
    }
    @Published var fontPreset: FontPreset {
        didSet { defaults.set(fontPreset.rawValue, forKey: "fontPreset") }
    }
    @Published var indicatorPosition: IndicatorPosition {
        didSet { defaults.set(indicatorPosition.rawValue, forKey: "indicatorPosition") }
    }
    @Published var indicatorPlacement: IndicatorPlacement {
        didSet { defaults.set(indicatorPlacement.rawValue, forKey: "indicatorPlacement") }
    }
    @Published var processingLook: ProcessingLook {
        didSet { defaults.set(processingLook.rawValue, forKey: "processingLook") }
    }
    @Published var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: "soundsEnabled") }
    }
    @Published var soundVolume: Double {
        didSet { defaults.set(soundVolume, forKey: "soundVolume") }
    }
    @Published var selectedMicrophoneUID: String {
        didSet { defaults.set(selectedMicrophoneUID, forKey: "selectedMicrophoneUID") }
    }
    @Published var preferBuiltInMicOverBluetooth: Bool {
        didSet { defaults.set(preferBuiltInMicOverBluetooth, forKey: "preferBuiltInMicOverBluetooth") }
    }
    @Published var showDockIcon: Bool {
        didSet {
            defaults.set(showDockIcon, forKey: "showDockIcon")
            if syncDockIcon {
                DockIconController.apply(visible: showDockIcon)
            }
        }
    }
    @Published var meetingAudioSource: MeetingAudioSource {
        didSet { defaults.set(meetingAudioSource.rawValue, forKey: "meetingAudioSource") }
    }
    @Published var enableGapiSummary: Bool {
        didSet { defaults.set(enableGapiSummary, forKey: "enableGapiSummary") }
    }
    @Published var meetingAudioRetention: MeetingAudioRetention {
        didSet {
            defaults.set(meetingAudioRetention.rawValue, forKey: "meetingAudioRetention")
            defaults.set(meetingAudioRetention != .deleteAfterTranscription, forKey: "keepMeetingAudio")
        }
    }
    @Published var whisperServerURL: String {
        didSet { defaults.set(whisperServerURL, forKey: "whisperServerURL") }
    }
    @Published var exportDestination: String {
        didSet { defaults.set(exportDestination, forKey: "exportDestination") }
    }
    @Published var useHomeServer: Bool {
        didSet { defaults.set(useHomeServer, forKey: "useHomeServer") }
    }
    @Published var homeServerURL: String {
        didSet { defaults.set(homeServerURL, forKey: "homeServerURL") }
    }
    @Published var homeServerEngine: HomeServerEngine {
        didSet { defaults.set(homeServerEngine.rawValue, forKey: "homeServerEngine") }
    }
    @Published var homeServerLanguage: HomeServerLanguage {
        didSet { defaults.set(homeServerLanguage.rawValue, forKey: "homeServerLanguage") }
    }

    @Published var gapiToken: String {
        didSet {
            guard persistSecrets else { return }
            KeychainStore.set(gapiToken, forKey: "gapiToken")
        }
    }
    @Published var anthropicApiKey: String {
        didSet {
            guard persistSecrets else { return }
            KeychainStore.set(anthropicApiKey, forKey: "anthropicApiKey")
        }
    }
    @Published var homeServerToken: String {
        didSet {
            guard persistSecrets else { return }
            if homeServerToken.isEmpty {
                KeychainStore.delete("homeServerToken")
            } else {
                KeychainStore.set(homeServerToken, forKey: "homeServerToken")
            }
        }
    }

    var autoPaste: Bool {
        pasteMode == .autoPaste
    }

    var shortcutDisplayLabel: String {
        switch shortcutSide {
        case .either:
            return shortcutKey.displayName
        case .left:
            return "Левый \(shortcutKey.displayName)"
        case .right:
            return "Правый \(shortcutKey.displayName)"
        }
    }

    var keepMeetingAudio: Bool {
        meetingAudioRetention != .deleteAfterTranscription
    }

    var hasExternalWhisperServer: Bool {
        !whisperServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasExportDestination: Bool {
        !exportDestination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var homeServerConfig: HomeServerConfig {
        HomeServerConfig(
            baseURLString: homeServerURL,
            token: homeServerToken,
            engine: homeServerEngine,
            language: homeServerLanguage
        )
    }

    init(
        defaults: UserDefaults = .standard,
        persistSecrets: Bool = true,
        syncDockIcon: Bool = true
    ) {
        self.defaults = defaults
        self.persistSecrets = persistSecrets
        self.syncDockIcon = syncDockIcon

        // Миграция прежнего ключа `hotkey` ("Right Option" и т.д.) -> (ShortcutKey, ShortcutSide)
        if let rawKey = defaults.string(forKey: "shortcutKey"),
           let parsedKey = ShortcutKey(rawValue: rawKey) {
            self.shortcutKey = parsedKey
            self.shortcutSide = ShortcutSide(rawValue: defaults.string(forKey: "shortcutSide") ?? "") ?? .either
        } else if let legacyHotkey = defaults.string(forKey: "hotkey"),
                  let migrated = Self.migrateLegacyHotkey(legacyHotkey) {
            self.shortcutKey = migrated.0
            self.shortcutSide = migrated.1
            defaults.set(migrated.0.rawValue, forKey: "shortcutKey")
            defaults.set(migrated.1.rawValue, forKey: "shortcutSide")
        } else {
            self.shortcutKey = .option
            self.shortcutSide = .either
        }

        // Миграция `recordingMode` -> `shortcutMode`
        if let rawMode = defaults.string(forKey: "shortcutMode"),
           let parsedMode = ShortcutMode(rawValue: rawMode) {
            self.shortcutMode = parsedMode
        } else if let legacyMode = defaults.string(forKey: "recordingMode") {
            let migratedMode = Self.migrateLegacyRecordingMode(legacyMode)
            self.shortcutMode = migratedMode
            defaults.set(migratedMode.rawValue, forKey: "shortcutMode")
        } else {
            self.shortcutMode = .holdOrDoubleTap
        }

        // Миграция `autoPaste` -> `pasteMode`
        if let rawPaste = defaults.string(forKey: "pasteMode"),
           let parsedPaste = PasteMode(rawValue: rawPaste) {
            self.pasteMode = parsedPaste
        } else if let legacyAutoPaste = defaults.object(forKey: "autoPaste") as? Bool {
            let migratedPaste: PasteMode = legacyAutoPaste ? .autoPaste : .clipboardOnly
            self.pasteMode = migratedPaste
            defaults.set(migratedPaste.rawValue, forKey: "pasteMode")
        } else {
            self.pasteMode = .autoPaste
        }

        self.restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        self.cleanupStyle = CleanupStyle(rawValue: defaults.string(forKey: "cleanupStyle") ?? "") ?? .grammar
        self.uzbekStyle = UzbekStyle(rawValue: defaults.string(forKey: "uzbekStyle") ?? "") ?? .tashkent
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        self.paperThemeID = defaults.string(forKey: "paperThemeID") ?? PaperTheme.cleanSheet.id
        self.paperDepth = defaults.object(forKey: "paperDepth") as? Double ?? 0.6
        self.paperGrainIntensity = defaults.object(forKey: "paperGrainIntensity") as? Double ?? 0.8
        self.fontPreset = FontPreset(rawValue: defaults.string(forKey: "fontPreset") ?? "") ?? .paperNewYork
        self.indicatorPosition = IndicatorPosition(rawValue: defaults.string(forKey: "indicatorPosition") ?? "") ?? .top
        self.indicatorPlacement = IndicatorPlacement(rawValue: defaults.string(forKey: "indicatorPlacement") ?? "") ?? .fromNotch
        self.processingLook = ProcessingLook(rawValue: defaults.string(forKey: "processingLook") ?? "") ?? .flow
        self.soundsEnabled = defaults.object(forKey: "soundsEnabled") as? Bool ?? true
        self.soundVolume = defaults.object(forKey: "soundVolume") as? Double ?? 0.35
        self.selectedMicrophoneUID = defaults.string(forKey: "selectedMicrophoneUID") ?? ""
        self.preferBuiltInMicOverBluetooth = defaults.object(forKey: "preferBuiltInMicOverBluetooth") as? Bool ?? false
        let dockVisible = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        self.showDockIcon = dockVisible
        self.meetingAudioSource = MeetingAudioSource(rawValue: defaults.string(forKey: "meetingAudioSource") ?? "") ?? .micAndSystem
        self.enableGapiSummary = defaults.object(forKey: "enableGapiSummary") as? Bool ?? false
        if let rawRetention = defaults.string(forKey: "meetingAudioRetention"),
           let parsed = MeetingAudioRetention(rawValue: rawRetention) {
            self.meetingAudioRetention = parsed
        } else if let legacyKeep = defaults.object(forKey: "keepMeetingAudio") as? Bool {
            self.meetingAudioRetention = legacyKeep ? .forever : .deleteAfterTranscription
        } else {
            self.meetingAudioRetention = .deleteAfterTranscription
        }
        self.whisperServerURL = defaults.string(forKey: "whisperServerURL") ?? ""
        self.exportDestination = defaults.string(forKey: "exportDestination")
            ?? defaults.string(forKey: "obsidianRecapsFolder")
            ?? ""
        self.useHomeServer = defaults.object(forKey: "useHomeServer") as? Bool ?? false
        self.homeServerURL = defaults.string(forKey: "homeServerURL") ?? HomeServerConfig.defaultURLString
        self.homeServerEngine = HomeServerEngine(rawValue: defaults.string(forKey: "homeServerEngine") ?? "") ?? .auto
        self.homeServerLanguage = HomeServerLanguage(rawValue: defaults.string(forKey: "homeServerLanguage") ?? "") ?? .auto

        if persistSecrets {
            self.gapiToken = KeychainStore.get("gapiToken") ?? ""
            self.anthropicApiKey = KeychainStore.get("anthropicApiKey") ?? ""
            self.homeServerToken = KeychainStore.get("homeServerToken") ?? ""
        } else {
            self.gapiToken = ""
            self.anthropicApiKey = ""
            self.homeServerToken = ""
        }

        if syncDockIcon {
            DockIconController.apply(visible: dockVisible)
        }
    }

    static func migrateLegacyHotkey(_ rawValue: String) -> (ShortcutKey, ShortcutSide)? {
        switch rawValue {
        case "Right Option": return (.option, .right)
        case "Right Command": return (.command, .right)
        case "Right Control": return (.control, .right)
        case "Right Shift": return (.shift, .right)
        case "Left Option": return (.option, .left)
        case "Left Command": return (.command, .left)
        case "Left Control": return (.control, .left)
        case "Left Shift": return (.shift, .left)
        default: return nil
        }
    }

    static func migrateLegacyRecordingMode(_ rawValue: String) -> ShortcutMode {
        switch rawValue {
        case "По нажатию (старт / стоп)": return .toggle
        case "По удержанию (push-to-talk)": return .hold
        default: return .holdOrDoubleTap
        }
    }
}
