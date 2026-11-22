import Foundation

enum ShortcutMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case holdOrDoubleTap = "Удержание или двойное нажатие"
    case toggle = "По нажатию (старт / стоп)"
    case hold = "Только удержание (push-to-talk)"

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .holdOrDoubleTap: return "Удержание / ×2"
        case .toggle: return "Нажатие"
        case .hold: return "Удержание"
        }
    }

    var descriptionText: String {
        switch self {
        case .holdOrDoubleTap:
            return "Удерживайте, чтобы продиктовать, или нажмите дважды для записи без рук."
        case .toggle:
            return "Нажмите один раз для старта и ещё раз для вставки. Escape отменяет запись."
        case .hold:
            return "Запись идёт, пока удерживается клавиша. Отпустите для распознавания."
        }
    }
}

enum ShortcutKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case option = "Option"
    case command = "Command"
    case control = "Control"
    case shift = "Shift"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .option: return "⌥"
        case .command: return "⌘"
        case .control: return "⌃"
        case .shift: return "⇧"
        }
    }

    var displayName: String {
        "\(rawValue) \(symbol)"
    }

    var leftKeyCode: UInt16 {
        switch self {
        case .option: return 58
        case .command: return 55
        case .control: return 59
        case .shift: return 56
        }
    }

    var rightKeyCode: UInt16 {
        switch self {
        case .option: return 61
        case .command: return 54
        case .control: return 62
        case .shift: return 60
        }
    }

    func matches(keyCode: UInt16, side: ShortcutSide) -> Bool {
        switch side {
        case .left: return keyCode == leftKeyCode
        case .right: return keyCode == rightKeyCode
        case .either: return keyCode == leftKeyCode || keyCode == rightKeyCode
        }
    }

    static func matchesAnySide(keyCode: UInt16) -> ShortcutKey? {
        for key in allCases {
            if keyCode == key.leftKeyCode || keyCode == key.rightKeyCode {
                return key
            }
        }
        return nil
    }
}

enum ShortcutSide: String, CaseIterable, Identifiable, Codable, Sendable {
    case either = "Любая"
    case left = "Левая"
    case right = "Правая"

    var id: String { rawValue }
}

enum HotkeyAction: Equatable, Sendable {
    case startRecording
    case stopRecording
    case cancelRecording
}

/// Чистый конечный автомат обработки клавиши-модификатора без зависимости от AppKit / CGEvent.
/// Легко тестируется с подставными временными метками (`now: TimeInterval`).
struct HotkeyStateMachine: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case pendingFirstPress(downAt: TimeInterval)
        case holdRecording
        case waitingSecondTap(releasedAt: TimeInterval)
        case handsFreePressing
        case handsFreeRecording
        case waitingTogglePress(otherKeyPressed: Bool)
        case toggleRecording
        case toggleStopPress
        case pendingHoldPress(downAt: TimeInterval)
        case cancelledUntilRelease
    }

    var mode: ShortcutMode
    var holdThreshold: TimeInterval
    var doubleTapWindow: TimeInterval
    var holdChordGrace: TimeInterval

    private(set) var phase: Phase = .idle
    private(set) var isModifierDown: Bool = false

    init(
        mode: ShortcutMode = .holdOrDoubleTap,
        holdThreshold: TimeInterval = 0.25,
        doubleTapWindow: TimeInterval = 0.30,
        holdChordGrace: TimeInterval = 0.08
    ) {
        self.mode = mode
        self.holdThreshold = holdThreshold
        self.doubleTapWindow = doubleTapWindow
        self.holdChordGrace = holdChordGrace
    }

    mutating func reset() {
        phase = .idle
        isModifierDown = false
    }

    /// Ближайшее время, когда нужно вызвать `tick(at:)`, если ожидание активно.
    var nextDeadline: TimeInterval? {
        switch phase {
        case .pendingFirstPress(let downAt):
            return downAt + holdThreshold
        case .waitingSecondTap(let releasedAt):
            return releasedAt + doubleTapWindow
        case .pendingHoldPress(let downAt):
            return downAt + holdChordGrace
        default:
            return nil
        }
    }

    mutating func handleModifierDown(at now: TimeInterval, isSystemRecording: Bool) -> [HotkeyAction] {
        guard !isModifierDown else { return [] }
        isModifierDown = true

        switch mode {
        case .holdOrDoubleTap:
            switch phase {
            case .idle:
                if isSystemRecording {
                    phase = .handsFreeRecording
                    // Повторное нажатие останавливает активную запись
                    phase = .cancelledUntilRelease
                    return [.stopRecording]
                }
                phase = .pendingFirstPress(downAt: now)
                return []

            case .waitingSecondTap(let releasedAt):
                if now - releasedAt <= doubleTapWindow {
                    phase = .handsFreePressing
                    return [.startRecording]
                } else {
                    phase = .pendingFirstPress(downAt: now)
                    return []
                }

            case .handsFreeRecording:
                phase = .cancelledUntilRelease
                return [.stopRecording]

            case .pendingFirstPress, .holdRecording, .handsFreePressing,
                 .waitingTogglePress, .toggleRecording, .toggleStopPress,
                 .pendingHoldPress, .cancelledUntilRelease:
                return []
            }

        case .toggle:
            switch phase {
            case .idle:
                if isSystemRecording {
                    phase = .toggleStopPress
                    return [.stopRecording]
                }
                phase = .waitingTogglePress(otherKeyPressed: false)
                return []
            case .toggleRecording:
                phase = .toggleStopPress
                return [.stopRecording]
            default:
                return []
            }

        case .hold:
            if isSystemRecording {
                return []
            }
            if holdChordGrace <= 0 {
                phase = .holdRecording
                return [.startRecording]
            }
            phase = .pendingHoldPress(downAt: now)
            return []
        }
    }

    mutating func handleModifierUp(at now: TimeInterval) -> [HotkeyAction] {
        guard isModifierDown else { return [] }
        isModifierDown = false

        switch phase {
        case .pendingFirstPress(let downAt):
            if now - downAt >= holdThreshold {
                // Порог удержания уже был достигнут, даже если таймер не успел сработать.
                phase = .idle
                return [.startRecording, .stopRecording]
            }
            phase = .waitingSecondTap(releasedAt: now)
            return []

        case .holdRecording:
            phase = .idle
            return [.stopRecording]

        case .handsFreePressing:
            phase = .handsFreeRecording
            return []

        case .waitingTogglePress(let otherKeyPressed):
            if otherKeyPressed {
                phase = .idle
                return []
            }
            phase = .toggleRecording
            return [.startRecording]

        case .toggleStopPress:
            phase = .idle
            return []

        case .pendingHoldPress(let downAt):
            if now - downAt >= holdChordGrace {
                phase = .idle
                return [.startRecording, .stopRecording]
            }
            // Слишком короткий случайный тап в режиме «только удержание» не запускает запись.
            phase = .idle
            return []

        case .cancelledUntilRelease:
            phase = .idle
            return []

        case .idle, .waitingSecondTap, .handsFreeRecording, .toggleRecording:
            return []
        }
    }

    mutating func handleOtherKeyDown(isEscape: Bool) -> [HotkeyAction] {
        if isEscape {
            switch phase {
            case .holdRecording, .handsFreePressing, .handsFreeRecording,
                 .toggleRecording, .toggleStopPress:
                phase = isModifierDown ? .cancelledUntilRelease : .idle
                return [.cancelRecording]
            case .pendingFirstPress, .pendingHoldPress:
                phase = isModifierDown ? .cancelledUntilRelease : .idle
                return []
            case .waitingTogglePress:
                phase = isModifierDown ? .waitingTogglePress(otherKeyPressed: true) : .idle
                return []
            case .waitingSecondTap:
                phase = .idle
                return []
            case .idle, .cancelledUntilRelease:
                return []
            }
        }

        // Любая другая клавиша отменяет модификатор до старта записи (например, ⌥ + буква).
        switch phase {
        case .pendingFirstPress, .pendingHoldPress:
            phase = .cancelledUntilRelease
            return []
        case .waitingTogglePress:
            phase = .waitingTogglePress(otherKeyPressed: true)
            return []
        case .waitingSecondTap:
            phase = .idle
            return []
        default:
            return []
        }
    }

    mutating func tick(at now: TimeInterval) -> [HotkeyAction] {
        switch phase {
        case .pendingFirstPress(let downAt):
            if now - downAt >= holdThreshold {
                phase = .holdRecording
                return [.startRecording]
            }
            return []

        case .waitingSecondTap(let releasedAt):
            if now - releasedAt > doubleTapWindow {
                phase = .idle
            }
            return []

        case .pendingHoldPress(let downAt):
            if now - downAt >= holdChordGrace {
                phase = .holdRecording
                return [.startRecording]
            }
            return []

        default:
            return []
        }
    }

    /// Синхронизирует состояние автомата, если внешняя запись завершилась или была отменена из UI.
    mutating func syncRecordingEnded() {
        switch phase {
        case .holdRecording, .handsFreePressing, .handsFreeRecording, .toggleRecording:
            phase = isModifierDown ? .cancelledUntilRelease : .idle
        default:
            break
        }
    }
}
