import AVFoundation
import AppKit
import ApplicationServices
import IOKit.hid

enum PermissionsHelper {
    static func microphoneStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    static func microphoneAuthorized() -> Bool {
        microphoneStatus() == .authorized
    }

    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// The event tap in HotkeyManager only tells us "it failed to start" — this is what
    /// actually distinguishes "permission never granted" from "granted, but macOS only
    /// applies Input Monitoring to a process after it's relaunched".
    static func inputMonitoringAuthorized() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    @discardableResult
    static func requestInputMonitoring() -> Bool {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    static func accessibilityAuthorized() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibility(prompt: Bool = true) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func openInputMonitoringSettings() {
        _ = requestInputMonitoring()
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    static func openAccessibilitySettings() {
        _ = requestAccessibility(prompt: true)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openMicrophoneSettings() {
        if microphoneStatus() == .notDetermined {
            requestMicrophone { granted in
                if !granted {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                }
            }
        } else {
            open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        }
    }

    static func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }

    private static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
