import Foundation
import CoreGraphics

enum PushToTalkKey: String, CaseIterable, Identifiable {
    case rightOption = "Right Option"
    case rightCommand = "Right Command"
    case rightControl = "Right Control"
    case rightShift = "Right Shift"

    var id: String { rawValue }

    var keyCode: CGKeyCode {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }
}

enum CleanupStyle: String, CaseIterable, Identifiable {
    case off = "Без LLM-обработки"
    case grammar = "Умная коррекция (Typeless)"
    case notes = "Заметка"
    case message = "Сообщение/письмо"

    var id: String { rawValue }

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

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "Как в системе"
    case light = "Светлая"
    case dark = "Тёмная"

    var id: String { rawValue }
}

enum RecordingMode: String, CaseIterable, Identifiable {
    case toggle = "По нажатию (старт / стоп)"
    case hold = "По удержанию (push-to-talk)"

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
    @Published var hotkey: PushToTalkKey {
        didSet { UserDefaults.standard.set(hotkey.rawValue, forKey: "hotkey") }
    }
    @Published var recordingMode: RecordingMode {
        didSet { UserDefaults.standard.set(recordingMode.rawValue, forKey: "recordingMode") }
    }
    @Published var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }
    @Published var cleanupStyle: CleanupStyle {
        didSet { UserDefaults.standard.set(cleanupStyle.rawValue, forKey: "cleanupStyle") }
    }
    @Published var uzbekStyle: UzbekStyle {
        didSet { UserDefaults.standard.set(uzbekStyle.rawValue, forKey: "uzbekStyle") }
    }
    @Published var appearance: AppearanceMode {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance") }
    }
    @Published var showDockIcon: Bool {
        didSet {
            UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
            DockIconController.apply(visible: showDockIcon)
        }
    }
    @Published var meetingAudioSource: MeetingAudioSource {
        didSet { UserDefaults.standard.set(meetingAudioSource.rawValue, forKey: "meetingAudioSource") }
    }
    @Published var enableGapiSummary: Bool {
        didSet { UserDefaults.standard.set(enableGapiSummary, forKey: "enableGapiSummary") }
    }
    @Published var meetingAudioRetention: MeetingAudioRetention {
        didSet {
            UserDefaults.standard.set(meetingAudioRetention.rawValue, forKey: "meetingAudioRetention")
            UserDefaults.standard.set(meetingAudioRetention != .deleteAfterTranscription, forKey: "keepMeetingAudio")
        }
    }
    @Published var whisperServerURL: String {
        didSet { UserDefaults.standard.set(whisperServerURL, forKey: "whisperServerURL") }
    }
    @Published var exportDestination: String {
        didSet { UserDefaults.standard.set(exportDestination, forKey: "exportDestination") }
    }
    @Published var useHomeServer: Bool {
        didSet { UserDefaults.standard.set(useHomeServer, forKey: "useHomeServer") }
    }
    @Published var homeServerURL: String {
        didSet { UserDefaults.standard.set(homeServerURL, forKey: "homeServerURL") }
    }
    @Published var homeServerEngine: HomeServerEngine {
        didSet { UserDefaults.standard.set(homeServerEngine.rawValue, forKey: "homeServerEngine") }
    }
    @Published var homeServerLanguage: HomeServerLanguage {
        didSet { UserDefaults.standard.set(homeServerLanguage.rawValue, forKey: "homeServerLanguage") }
    }

    @Published var gapiToken: String {
        didSet { KeychainStore.set(gapiToken, forKey: "gapiToken") }
    }
    @Published var anthropicApiKey: String {
        didSet { KeychainStore.set(anthropicApiKey, forKey: "anthropicApiKey") }
    }
    @Published var homeServerToken: String {
        didSet {
            if homeServerToken.isEmpty {
                KeychainStore.delete("homeServerToken")
            } else {
                KeychainStore.set(homeServerToken, forKey: "homeServerToken")
            }
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

    init() {
        let defaults = UserDefaults.standard
        self.hotkey = PushToTalkKey(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .rightOption
        self.recordingMode = RecordingMode(rawValue: defaults.string(forKey: "recordingMode") ?? "") ?? .toggle
        self.autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        self.cleanupStyle = CleanupStyle(rawValue: defaults.string(forKey: "cleanupStyle") ?? "") ?? .grammar
        self.uzbekStyle = UzbekStyle(rawValue: defaults.string(forKey: "uzbekStyle") ?? "") ?? .tashkent
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        self.showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? true
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
        self.gapiToken = KeychainStore.get("gapiToken") ?? ""
        self.anthropicApiKey = KeychainStore.get("anthropicApiKey") ?? ""
        self.homeServerToken = KeychainStore.get("homeServerToken") ?? ""
        DockIconController.apply(visible: self.showDockIcon)
    }
}
