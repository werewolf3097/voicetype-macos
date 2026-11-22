import Foundation
import CoreGraphics

enum STTDictationSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case localGateway = "localGateway"
    case gapi = "gapi"
    case gemini = "gemini"
    case openai = "openai"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localGateway: return "Домашний шлюз (ПК / Tailscale)"
        case .gapi: return "gapi.uz"
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI (Whisper)"
        }
    }

    var subtitle: String {
        switch self {
        case .localGateway: return "Сжатый Opus-поток на ваш локальный сервер Parakeet / Whisper."
        case .gapi: return "Облачный STT-сервис — особенно хорош для узбекской и смешанной речи."
        case .gemini: return "Мультимодальное распознавание аудио через Gemini API."
        case .openai: return "OpenAI /v1/audio/transcriptions (whisper-1)."
        }
    }

    static var defaultOrder: [STTRouteStep<STTDictationSource>] {
        [
            .init(source: .localGateway, isEnabled: false),
            .init(source: .gapi, isEnabled: true),
            .init(source: .gemini, isEnabled: true),
            .init(source: .openai, isEnabled: true)
        ]
    }
}

enum STTMeetingSource: String, CaseIterable, Identifiable, Codable, Sendable {
    case localWhisper = "localWhisper"
    case gapi = "gapi"
    case gemini = "gemini"
    case openai = "openai"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .localWhisper: return "Локальный сервер встреч (Whisper)"
        case .gapi: return "gapi.uz"
        case .gemini: return "Google Gemini (раздельно каналы)"
        case .openai: return "OpenAI (нарезка чанками <25 МБ)"
        }
    }

    var shortTitle: String {
        switch self {
        case .localWhisper: return "Локальный Whisper"
        case .gapi: return "gapi.uz"
        case .gemini: return "Gemini"
        case .openai: return "OpenAI"
        }
    }

    var subtitle: String {
        switch self {
        case .localWhisper: return "Ваш сервер Whisper (локальный GPU, без лимитов и платы за минуты)."
        case .gapi: return "Облачный STT — особенно хорош для узбекской речи (+ опция резюме)."
        case .gemini: return "Слушает «Вы» и «Собеседников» раздельно (до 9.5 ч, без потери каналов)."
        case .openai: return "Режет встречу на чанки <25 МБ (whisper-1) с привязкой спикеров."
        }
    }

    static var defaultOrder: [STTRouteStep<STTMeetingSource>] {
        [
            .init(source: .localWhisper, isEnabled: true),
            .init(source: .gapi, isEnabled: true),
            .init(source: .gemini, isEnabled: true),
            .init(source: .openai, isEnabled: true)
        ]
    }
}

struct STTRouteStep<Source: RawRepresentable & Hashable & Codable & Sendable>: Identifiable, Codable, Equatable, Sendable where Source.RawValue == String {
    let source: Source
    var isEnabled: Bool

    var id: String { source.rawValue }

    static func normalized(_ stored: [STTRouteStep<Source>], defaults: [STTRouteStep<Source>]) -> [STTRouteStep<Source>] {
        var seen = Set<Source>()
        var result: [STTRouteStep<Source>] = []
        for item in stored {
            if seen.insert(item.source).inserted {
                result.append(item)
            }
        }
        for item in defaults where seen.insert(item.source).inserted {
            result.append(item)
        }
        return result
    }
}

enum CleanupStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "Без обработки"
    case friendly = "Дружественный"
    case business = "Деловой"
    case formal = "Формальный"

    var id: String { rawValue }

    var shortTitle: String { rawValue }

    var loadLabel: String {
        switch self {
        case .off: return "0% правок"
        case .friendly: return "Лёгкая правка"
        case .business: return "Средняя правка"
        case .formal: return "Полная редактура"
        }
    }

    var tooltipText: String {
        switch self {
        case .off:
            return "Без ИИ: вставляет сырую расшифровку как есть, без задержки на обработку."
        case .friendly:
            return "Лёгкая правка (для Telegram, Slack, личных чатов): расставит знаки, уберёт «э-э» и опечатки, но оставит живую интонацию, «ты» и лёгкий тон без официоза."
        case .business:
            return "Средняя правка (для коллег, писем, заметок): вычистит разговорные шероховатости, сделает мысль собранной, нейтральной и понятной, при длинной речи поделит на абзацы."
        case .formal:
            return "Полная редактура (для документов, руководства, официальных обращений): переведёт устную речь в грамотный официально-вежливый стиль на «Вы»."
        }
    }

    var oneLineDescription: String {
        switch self {
        case .off:
            return "Без обработки: вставит текст ровно так, как он распознан."
        case .friendly:
            return "Дружественный (лёгкая правка): пунктуация и орфография с живым тоном для чатов и Telegram."
        case .business:
            return "Деловой (средняя правка): чёткая рабочая речь для коллег, писем, задач и заметок."
        case .formal:
            return "Формальный (полная редактура): строгий официально-вежливый стиль на «Вы»."
        }
    }

    var exampleOutput: String {
        switch self {
        case .off:
            return "ну короче я завтра не смогу на созвон давай в четверг ок"
        case .friendly:
            return "Я завтра не смогу на созвон, давай в четверг, ок?"
        case .business:
            return "Завтра не смогу присоединиться к созвону. Давайте перенесём встречу на четверг."
        case .formal:
            return "К сожалению, завтра я не смогу принять участие в созвоне. Предлагаю перенести встречу на четверг."
        }
    }

    var systemPrompt: String? {
        let sharedFoundation = """
        Обязательная база (выполняй всегда):
        1. Расставь все недостающие знаки препинания (запятые, тире, двоеточия, точки, вопросительные знаки).
        2. Исправь орфографические, падежные и очевидные фонетические сбои распознавания речи.
        3. Убери слова-паразиты («э-э», «эм», «ну», «как бы», «типа», случайные повторы слов) и обработай устные самоисправления («давай завтра нет в четверг» → «давай в четверг»).
        4. Сохрани язык оригинала (или смешанную речь) и все факты, имена, даты и числа — ничего не выдумывай от себя.
        Верни только готовый текст, без кавычек и пояснений.
        """

        switch self {
        case .off:
            return nil
        case .friendly:
            return """
            Ты — редактор голосовой диктовки в стиле Typeless с мягким дружественным тоном (как живая переписка в Telegram, Slack или личном чате).
            Твоя задача — вычистить речь от ошибок, но сохранить естественный, человеческий голос автора:
            - Не превращай фразы в сухой канцелярит; сохраняй обращение «ты/вы» и разговорную лёгкость.
            - В короткой однострочной реплике для чата не утяжеляй тон лишним официозом.

            \(sharedFoundation)
            """
        case .business:
            return """
            Ты — редактор голосовой диктовки в нейтрально-деловом рабочем стиле (переписка с коллегами и клиентами, рабочие письма, заметки и задачи).
            Твоя задача — сделать мысль чёткой, собранной и уважительной:
            - Сгладь слишком резкие или сумбурные разговорные обороты, не скатываясь в тяжёлый бюрократический язык.
            - Если текст длинный, логично разбей его на аккуратные абзацы.

            \(sharedFoundation)
            """
        case .formal:
            return """
            Ты — редактор голосовой диктовки в строгом формальном стиле (официальные письма, обращения к руководству/партнёрам, документы).
            Твоя задача — перевести устную речь в безупречный официально-вежливый письменный регистр:
            - Используй грамотные завершённые формулировки и вежливое обращение на «Вы» (если уместно по контексту).
            - Полностью убери просторечия и сленг, сохранив весь смысл, имена и цифры.

            \(sharedFoundation)
            """
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = Self.fromStored(raw) ?? .friendly
    }

    static func fromStored(_ raw: String?) -> CleanupStyle? {
        guard let raw else { return nil }
        if let direct = CleanupStyle(rawValue: raw) {
            return direct
        }
        switch raw {
        case "Без LLM-обработки":
            return .off
        case "Умная коррекция (Typeless)":
            return .friendly
        case "Заметка", "Сообщение/письмо":
            return .business
        default:
            return nil
        }
    }
}

struct CleanupModifiers: Equatable, Sendable {
    var compactMode: Bool = false
    var structuredLists: Bool = false
    var preserveTechnicalTerms: Bool = true
    var autoToneByApp: Bool = false
    var customInstruction: String = ""

    static let `default` = CleanupModifiers()

    func resolvedStyle(base: CleanupStyle, targetAppName: String?) -> CleanupStyle {
        guard base != .off else { return .off }
        guard autoToneByApp, let app = targetAppName?.lowercased(), !app.isEmpty else {
            return base
        }
        let friendlyApps = ["telegram", "whatsapp", "slack", "messages", "сообщения", "discord"]
        if friendlyApps.contains(where: { app.contains($0) }) {
            return .friendly
        }
        let businessApps = [
            "mail", "почта", "outlook", "spark", "mimestream",
            "notion", "obsidian", "notes", "заметки", "linear", "jira",
            "cursor", "visual studio code", "vscode", "xcode", "terminal", "iterm"
        ]
        if businessApps.contains(where: { app.contains($0) }) {
            return .business
        }
        return base
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
    @Published var cleanupCompactMode: Bool {
        didSet { defaults.set(cleanupCompactMode, forKey: "cleanupCompactMode") }
    }
    @Published var cleanupStructuredLists: Bool {
        didSet { defaults.set(cleanupStructuredLists, forKey: "cleanupStructuredLists") }
    }
    @Published var cleanupPreserveTechTerms: Bool {
        didSet { defaults.set(cleanupPreserveTechTerms, forKey: "cleanupPreserveTechTerms") }
    }
    @Published var cleanupAutoToneByApp: Bool {
        didSet { defaults.set(cleanupAutoToneByApp, forKey: "cleanupAutoToneByApp") }
    }
    @Published var cleanupCustomInstruction: String {
        didSet { defaults.set(cleanupCustomInstruction, forKey: "cleanupCustomInstruction") }
    }

    var cleanupModifiers: CleanupModifiers {
        CleanupModifiers(
            compactMode: cleanupCompactMode,
            structuredLists: cleanupStructuredLists,
            preserveTechnicalTerms: cleanupPreserveTechTerms,
            autoToneByApp: cleanupAutoToneByApp,
            customInstruction: cleanupCustomInstruction
        )
    }
    @Published var llmProvider: LLMProviderKind {
        didSet { defaults.set(llmProvider.rawValue, forKey: "llmProvider") }
    }
    @Published var anthropicModel: String {
        didSet { defaults.set(anthropicModel, forKey: "anthropicModel") }
    }
    @Published var openaiModel: String {
        didSet { defaults.set(openaiModel, forKey: "openaiModel") }
    }
    @Published var geminiModel: String {
        didSet { defaults.set(geminiModel, forKey: "geminiModel") }
    }
    @Published var customLLMBaseURL: String {
        didSet { defaults.set(customLLMBaseURL, forKey: "customLLMBaseURL") }
    }
    @Published var customLLMModel: String {
        didSet { defaults.set(customLLMModel, forKey: "customLLMModel") }
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
        didSet {
            defaults.set(useHomeServer, forKey: "useHomeServer")
            guard !isSyncingRouteFlag else { return }
            isSyncingRouteFlag = true
            if let idx = sttDictationRoute.firstIndex(where: { $0.source == .localGateway }),
               sttDictationRoute[idx].isEnabled != useHomeServer {
                sttDictationRoute[idx].isEnabled = useHomeServer
            }
            isSyncingRouteFlag = false
        }
    }
    @Published var sttDictationRoute: [STTRouteStep<STTDictationSource>] {
        didSet {
            if let data = try? JSONEncoder().encode(sttDictationRoute) {
                defaults.set(data, forKey: "sttDictationRoute")
            }
            guard !isSyncingRouteFlag else { return }
            if let localStep = sttDictationRoute.first(where: { $0.source == .localGateway }),
               useHomeServer != localStep.isEnabled {
                isSyncingRouteFlag = true
                useHomeServer = localStep.isEnabled
                isSyncingRouteFlag = false
            }
        }
    }
    @Published var sttMeetingRoute: [STTRouteStep<STTMeetingSource>] {
        didSet {
            if let data = try? JSONEncoder().encode(sttMeetingRoute) {
                defaults.set(data, forKey: "sttMeetingRoute")
            }
        }
    }
    @Published var waitForLocalMeetingServerInQueue: Bool {
        didSet { defaults.set(waitForLocalMeetingServerInQueue, forKey: "waitForLocalMeetingServerInQueue") }
    }
    private var isSyncingRouteFlag = false
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
    @Published var openaiApiKey: String {
        didSet {
            guard persistSecrets else { return }
            if openaiApiKey.isEmpty {
                KeychainStore.delete("openaiApiKey")
            } else {
                KeychainStore.set(openaiApiKey, forKey: "openaiApiKey")
            }
        }
    }
    @Published var geminiApiKey: String {
        didSet {
            guard persistSecrets else { return }
            if geminiApiKey.isEmpty {
                KeychainStore.delete("geminiApiKey")
            } else {
                KeychainStore.set(geminiApiKey, forKey: "geminiApiKey")
            }
        }
    }
    @Published var customLLMApiKey: String {
        didSet {
            guard persistSecrets else { return }
            if customLLMApiKey.isEmpty {
                KeychainStore.delete("customLLMApiKey")
            } else {
                KeychainStore.set(customLLMApiKey, forKey: "customLLMApiKey")
            }
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

    var activeLLMConfig: LLMConfiguration {
        switch llmProvider {
        case .anthropic:
            return LLMConfiguration(
                provider: .anthropic,
                apiKey: anthropicApiKey,
                model: anthropicModel,
                customBaseURL: ""
            )
        case .openai:
            return LLMConfiguration(
                provider: .openai,
                apiKey: openaiApiKey,
                model: openaiModel,
                customBaseURL: ""
            )
        case .gemini:
            return LLMConfiguration(
                provider: .gemini,
                apiKey: geminiApiKey,
                model: geminiModel,
                customBaseURL: ""
            )
        case .openaiCompatible:
            return LLMConfiguration(
                provider: .openaiCompatible,
                apiKey: customLLMApiKey,
                model: customLLMModel,
                customBaseURL: customLLMBaseURL
            )
        }
    }

    var isLLMConfigured: Bool {
        activeLLMConfig.isConfigured
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

    func isDictationSourceConfigured(_ source: STTDictationSource) -> Bool {
        switch source {
        case .localGateway:
            return !homeServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !homeServerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .gapi:
            return !gapiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .gemini:
            return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openai:
            return !openaiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func dictationMissingRequirement(_ source: STTDictationSource) -> String? {
        guard !isDictationSourceConfigured(source) else { return nil }
        switch source {
        case .localGateway: return "Укажите URL и токен домашнего шлюза"
        case .gapi: return "Укажите токен gapi.uz"
        case .gemini: return "Укажите API-ключ Gemini"
        case .openai: return "Укажите API-ключ OpenAI"
        }
    }

    func isMeetingSourceConfigured(_ source: STTMeetingSource) -> Bool {
        switch source {
        case .localWhisper:
            return hasExternalWhisperServer
        case .gapi:
            return !gapiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .gemini:
            return !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .openai:
            return !openaiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    func meetingMissingRequirement(_ source: STTMeetingSource) -> String? {
        guard !isMeetingSourceConfigured(source) else { return nil }
        switch source {
        case .localWhisper: return "Укажите URL сервера Whisper"
        case .gapi: return "Укажите токен gapi.uz"
        case .gemini: return "Укажите API-ключ Gemini"
        case .openai: return "Укажите API-ключ OpenAI"
        }
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
        let rawCleanupStyle = defaults.string(forKey: "cleanupStyle")
        let resolvedStyle = CleanupStyle.fromStored(rawCleanupStyle) ?? .friendly
        self.cleanupStyle = resolvedStyle
        if rawCleanupStyle != resolvedStyle.rawValue {
            defaults.set(resolvedStyle.rawValue, forKey: "cleanupStyle")
        }
        self.cleanupCompactMode = defaults.object(forKey: "cleanupCompactMode") as? Bool ?? false
        self.cleanupStructuredLists = defaults.object(forKey: "cleanupStructuredLists") as? Bool ?? false
        self.cleanupPreserveTechTerms = defaults.object(forKey: "cleanupPreserveTechTerms") as? Bool ?? true
        self.cleanupAutoToneByApp = defaults.object(forKey: "cleanupAutoToneByApp") as? Bool ?? false
        self.cleanupCustomInstruction = defaults.string(forKey: "cleanupCustomInstruction") ?? ""
        self.llmProvider = LLMProviderKind(rawValue: defaults.string(forKey: "llmProvider") ?? "") ?? .anthropic
        let storedAnthropicModel = defaults.string(forKey: "anthropicModel") ?? ""
        self.anthropicModel = (storedAnthropicModel == "claude-haiku-4-5-20251001" || storedAnthropicModel == LLMProviderKind.anthropic.defaultModel)
            ? ""
            : storedAnthropicModel
        let storedOpenAIModel = defaults.string(forKey: "openaiModel") ?? ""
        self.openaiModel = (storedOpenAIModel == "gpt-4o-mini" || storedOpenAIModel == LLMProviderKind.openai.defaultModel)
            ? ""
            : storedOpenAIModel
        let storedGeminiModel = defaults.string(forKey: "geminiModel") ?? ""
        if storedGeminiModel == "gemini-2.5-flash" || storedGeminiModel == LLMProviderKind.gemini.defaultModel {
            self.geminiModel = ""
            defaults.set("", forKey: "geminiModel")
        } else {
            self.geminiModel = storedGeminiModel
        }
        self.customLLMBaseURL = defaults.string(forKey: "customLLMBaseURL") ?? OpenAICompatiblePreset.openrouter.baseURL
        let storedCustomModel = defaults.string(forKey: "customLLMModel") ?? ""
        self.customLLMModel = storedCustomModel == OpenAICompatiblePreset.openrouter.suggestedModel ? "" : storedCustomModel
        self.uzbekStyle = UzbekStyle(rawValue: defaults.string(forKey: "uzbekStyle") ?? "") ?? .tashkent
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        self.paperThemeID = PaperTheme.cleanSheet.id
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
        let legacyUseHome = defaults.object(forKey: "useHomeServer") as? Bool ?? false
        self.useHomeServer = legacyUseHome
        if let rawDictRoute = defaults.data(forKey: "sttDictationRoute"),
           let decoded = try? JSONDecoder().decode([STTRouteStep<STTDictationSource>].self, from: rawDictRoute) {
            var normalized = STTRouteStep.normalized(decoded, defaults: STTDictationSource.defaultOrder)
            if defaults.object(forKey: "useHomeServer") != nil,
               let idx = normalized.firstIndex(where: { $0.source == .localGateway }) {
                normalized[idx].isEnabled = legacyUseHome
            }
            self.sttDictationRoute = normalized
        } else {
            var initial = STTDictationSource.defaultOrder
            if let idx = initial.firstIndex(where: { $0.source == .localGateway }) {
                initial[idx].isEnabled = legacyUseHome
            }
            self.sttDictationRoute = initial
        }

        if let rawMeetRoute = defaults.data(forKey: "sttMeetingRoute"),
           let decoded = try? JSONDecoder().decode([STTRouteStep<STTMeetingSource>].self, from: rawMeetRoute) {
            self.sttMeetingRoute = STTRouteStep.normalized(decoded, defaults: STTMeetingSource.defaultOrder)
        } else {
            self.sttMeetingRoute = STTMeetingSource.defaultOrder
        }
        self.waitForLocalMeetingServerInQueue = defaults.object(forKey: "waitForLocalMeetingServerInQueue") as? Bool ?? true
        self.homeServerURL = defaults.string(forKey: "homeServerURL") ?? HomeServerConfig.defaultURLString
        self.homeServerEngine = HomeServerEngine(rawValue: defaults.string(forKey: "homeServerEngine") ?? "") ?? .auto
        self.homeServerLanguage = HomeServerLanguage(rawValue: defaults.string(forKey: "homeServerLanguage") ?? "") ?? .auto

        if persistSecrets {
            self.gapiToken = KeychainStore.get("gapiToken") ?? ""
            self.anthropicApiKey = KeychainStore.get("anthropicApiKey") ?? ""
            self.openaiApiKey = KeychainStore.get("openaiApiKey") ?? ""
            self.geminiApiKey = KeychainStore.get("geminiApiKey") ?? ""
            self.customLLMApiKey = KeychainStore.get("customLLMApiKey") ?? ""
            self.homeServerToken = KeychainStore.get("homeServerToken") ?? ""
        } else {
            self.gapiToken = ""
            self.anthropicApiKey = ""
            self.openaiApiKey = ""
            self.geminiApiKey = ""
            self.customLLMApiKey = ""
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
