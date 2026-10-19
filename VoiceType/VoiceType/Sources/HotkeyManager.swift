import CoreGraphics
import Foundation

final class HotkeyManager {
    var targetKeyCode: CGKeyCode = 61
    var mode: RecordingMode = .toggle
    var onStart: (() -> Void)?
    var onStop: (() -> Void)?
    var onToggle: (() -> Void)?
    var onCancel: (() -> Void)?
    var isRecording: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthCheckTimer: Timer?
    private var isDown = false

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

        // .cghidEventTap taps the keyboard at the hardware level, before the window
        // server routes the event to a session/frontmost app.
        // .defaultTap allows swallowing Escape during recording, but requires Accessibility.
        // Fall back to .listenOnly (which only requires Input Monitoring) if .defaultTap fails.
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
        isDown = false
    }

    /// Defense in depth beyond the tapDisabledBy* callback below: catches any other
    /// silent disablement the OS doesn't explicitly notify the callback about.
    private func checkTapHealth() {
        guard let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // macOS can silently disable a tap (timeout, or user-input pressure) — without
        // this it just stops receiving events forever and the hotkey looks "dead".
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return false
        }

        if type == .keyDown {
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if keyCode == 53 { // 53 is Escape
                if isDown || (isRecording?() == true) {
                    isDown = false
                    DispatchQueue.main.async { [weak self] in self?.onCancel?() }
                    return true // Swallow the Escape key
                }
            }
            return false
        }

        guard type == .flagsChanged else { return false }
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == targetKeyCode else { return false }

        let pressed = event.flags.rawValue & modifierFlagBit(for: keyCode) != 0
        switch mode {
        case .toggle:
            if pressed && !isDown {
                isDown = true
                DispatchQueue.main.async { [weak self] in self?.onToggle?() }
            } else if !pressed && isDown {
                isDown = false
            }
        case .hold:
            if pressed && !isDown {
                isDown = true
                DispatchQueue.main.async { [weak self] in self?.onStart?() }
            } else if !pressed && isDown {
                isDown = false
                DispatchQueue.main.async { [weak self] in self?.onStop?() }
            }
        }

        return false
    }

    private func modifierFlagBit(for keyCode: CGKeyCode) -> UInt64 {
        switch keyCode {
        case 61, 58: return CGEventFlags.maskAlternate.rawValue
        case 54, 55: return CGEventFlags.maskCommand.rawValue
        case 62, 59: return CGEventFlags.maskControl.rawValue
        case 60, 56: return CGEventFlags.maskShift.rawValue
        default: return 0
        }
    }
}
