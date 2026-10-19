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
    @Published var keepMeetingAudio: Bool {
        didSet { UserDefaults.standard.set(keepMeetingAudio, forKey: "keepMeetingAudio") }
    }

    @Published var gapiToken: String {
        didSet { KeychainStore.set(gapiToken, forKey: "gapiToken") }
    }
    @Published var anthropicApiKey: String {
        didSet { KeychainStore.set(anthropicApiKey, forKey: "anthropicApiKey") }
    }

    init() {
        let defaults = UserDefaults.standard
        self.hotkey = PushToTalkKey(rawValue: defaults.string(forKey: "hotkey") ?? "") ?? .rightOption
        self.recordingMode = RecordingMode(rawValue: defaults.string(forKey: "recordingMode") ?? "") ?? .toggle
        self.autoPaste = defaults.object(forKey: "autoPaste") as? Bool ?? true
        self.cleanupStyle = CleanupStyle(rawValue: defaults.string(forKey: "cleanupStyle") ?? "") ?? .grammar
        self.uzbekStyle = UzbekStyle(rawValue: defaults.string(forKey: "uzbekStyle") ?? "") ?? .tashkent
        self.showDockIcon = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        self.meetingAudioSource = MeetingAudioSource(rawValue: defaults.string(forKey: "meetingAudioSource") ?? "") ?? .micAndSystem
        self.enableGapiSummary = defaults.object(forKey: "enableGapiSummary") as? Bool ?? false
        self.keepMeetingAudio = defaults.object(forKey: "keepMeetingAudio") as? Bool ?? false
        self.gapiToken = KeychainStore.get("gapiToken") ?? ""
        self.anthropicApiKey = KeychainStore.get("anthropicApiKey") ?? ""
        DockIconController.apply(visible: self.showDockIcon)
    }
}
