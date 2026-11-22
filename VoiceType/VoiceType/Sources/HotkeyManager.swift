import CoreGraphics
import Foundation

final class HotkeyManager {
    var shortcutKey: ShortcutKey = .option
    var shortcutSide: ShortcutSide = .either
    var mode: ShortcutMode = .holdOrDoubleTap {
        didSet {
            if stateMachine.mode != mode {
                stateMachine.mode = mode
                stateMachine.reset()
                cancelDeadlineWorkItem()
            }
        }
    }

    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?
    var isRecording: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTimer: Timer?
    private var deadlineWorkItem: DispatchWorkItem?
    private var stateMachine = HotkeyStateMachine()

    private(set) var canSwallowEvents = false

    var isActive: Bool { eventTap != nil }

    func start() -> Bool {
        stop()

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            let swallow = manager.handle(type: type, event: event)
            return (swallow && manager.canSwallowEvents) ? nil : Unmanaged.passUnretained(event)
        }

        // .cghidEventTap перехватывает события клавиатуры на аппаратном уровне до маршрутизации в приложение.
        // .defaultTap позволяет глотать Escape во время записи, но требует Accessibility;
        // при его отсутствии откатываемся на .listenOnly (достаточно Input Monitoring).
        var createdTap: CFMachPort?
        if PermissionsHelper.accessibilityAuthorized() {
            createdTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: refcon
            )
            if createdTap != nil {
                canSwallowEvents = true
            }
        }

        if createdTap == nil {
            createdTap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: callback,
                userInfo: refcon
            )
            canSwallowEvents = false
        }

        guard let tap = createdTap else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.checkTapHealth()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthCheckTimer = timer

        return true
    }

    func stop() {
        cancelDeadlineWorkItem()
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        eventTap = nil
        runLoopSource = nil
        stateMachine.reset()
    }

    func notifyRecordingEndedExternally() {
        stateMachine.syncRecordingEnded()
        scheduleDeadlineIfNeeded()
    }

    private func checkTapHealth() {
        guard let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime

        if type == .keyDown {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            let isEscape = keyCode == 53
            let systemRecording = isRecording?() ?? false
            let actions = stateMachine.handleOtherKeyDown(isEscape: isEscape)
            scheduleDeadlineIfNeeded()
            dispatch(actions)

            if isEscape && (systemRecording || actions.contains(.cancelRecording)) {
                if !actions.contains(.cancelRecording) {
                    DispatchQueue.main.async { [weak self] in self?.onCancel?() }
                }
                return true
            }
            return false
        }

        guard type == .flagsChanged else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if !shortcutKey.matches(keyCode: keyCode, side: shortcutSide) {
            // Другой модификатор (например, ⌘ или ⇧ вместе с ⌥) тоже отменяет одиночное нажатие.
            let isPressed = ShortcutKey.matchesAnySide(keyCode: keyCode).map {
                event.flags.rawValue & modifierFlagBit(for: $0) != 0
            } ?? false
            if isPressed {
                let actions = stateMachine.handleOtherKeyDown(isEscape: false)
                scheduleDeadlineIfNeeded()
                dispatch(actions)
            }
            return false
        }

        let pressed = event.flags.rawValue & modifierFlagBit(for: shortcutKey) != 0
        let actions: [HotkeyAction]
        if pressed {
            actions = stateMachine.handleModifierDown(at: now, isSystemRecording: isRecording?() ?? false)
        } else {
            actions = stateMachine.handleModifierUp(at: now)
        }
        scheduleDeadlineIfNeeded()
        dispatch(actions)
        return false
    }

    private func scheduleDeadlineIfNeeded() {
        cancelDeadlineWorkItem()
        guard let deadline = stateMachine.nextDeadline else { return }
        let delay = max(0.005, deadline - ProcessInfo.processInfo.systemUptime)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            let actions = self.stateMachine.tick(at: now)
            self.scheduleDeadlineIfNeeded()
            self.dispatch(actions)
        }
        deadlineWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelDeadlineWorkItem() {
        deadlineWorkItem?.cancel()
        deadlineWorkItem = nil
    }

    private func dispatch(_ actions: [HotkeyAction]) {
        guard !actions.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for action in actions {
                switch action {
                case .startRecording:
                    self.onStart?()
                case .stopRecording:
                    self.onStop?()
                case .cancelRecording:
                    self.onCancel?()
                }
            }
        }
    }

    private func modifierFlagBit(for key: ShortcutKey) -> UInt64 {
        switch key {
        case .option: return CGEventFlags.maskAlternate.rawValue
        case .command: return CGEventFlags.maskCommand.rawValue
        case .control: return CGEventFlags.maskControl.rawValue
        case .shift: return CGEventFlags.maskShift.rawValue
        }
    }
}
