import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Держим токен живым весь срок работы приложения: без этого macOS применяет App Nap,
    // как только VoiceType уходит в фон, и глобальный хоткей перестаёт реагировать вовремя
    // (или вообще) — именно это выглядело как «хоткей работает, только пока открыто меню».
    private var activityToken: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Глобальный хоткей должен реагировать даже когда приложение в фоне"
        )
        NotificationHelper.requestAuthorizationIfNeeded()

        DispatchQueue.main.async {
            DashboardWindowController.shared.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            DashboardWindowController.shared.show()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let homeItem = NSMenuItem(title: "Открыть VoiceType", action: #selector(openHome), keyEquivalent: "")
        homeItem.target = self
        menu.addItem(homeItem)

        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    @objc private func openHome() {
        Task { @MainActor in
            DashboardWindowController.shared.show(section: .home)
        }
    }

    @objc private func openSettings() {
        Task { @MainActor in
            DashboardWindowController.shared.show(section: .settings)
        }
    }
}
