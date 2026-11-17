import AppKit
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case home = "Главная"
    case meetings = "Встречи"
    case history = "История"
    case dictionary = "Словарь"
    case settings = "Настройки"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .meetings: return "person.2.wave.2"
        case .history: return "clock"
        case .dictionary: return "text.book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    private var chrome: VoiceChrome { VoiceChrome(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(chrome.canvas)
        .preferredColorScheme(settings.appearance.colorScheme)
        .onChange(of: settings.appearance) { _, mode in
            DashboardWindowController.shared.applyAppearance(mode)
        }
        .onAppear {
            if PermissionsHelper.microphoneStatus() == .notDetermined {
                PermissionsHelper.requestMicrophone { _ in
                    appState.refreshPermissionsAndHotkey()
                }
            } else {
                appState.refreshPermissionsAndHotkey()
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VoiceType")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(chrome.ink)
                .padding(.horizontal, 6)
                .padding(.bottom, 8)

            ForEach(DashboardSection.allCases) { section in
                sidebarRow(section)
            }
            Spacer()
        }
        .padding(.top, 36)
        .padding(.horizontal, 16)
        .frame(width: 128)
        .frame(maxHeight: .infinity)
        .background(chrome.canvas)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(chrome.hairline)
                .frame(width: 1)
        }
    }

    private func sidebarRow(_ section: DashboardSection) -> some View {
        let selected = (appState.selectedSection ?? .home) == section
        return Button {
            appState.selectedSection = section
        } label: {
            VStack(spacing: 7) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 18, weight: .medium))
                Text(section.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.white : chrome.ink)
            .frame(width: 96, height: 96)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(selected ? chrome.accent : chrome.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.14) : chrome.hairline)
            )
            .shadow(
                color: selected ? chrome.accent.opacity(0.32) : chrome.shadow,
                radius: selected ? 12 : 8,
                y: selected ? 6 : 3
            )
            .overlay(alignment: .topTrailing) {
                if section == .meetings, appState.activeMeetingID != nil {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .padding(10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch appState.selectedSection {
            case .home, .none:
                DashboardHomeView()
            case .meetings:
                DashboardMeetingsView()
            case .history:
                DashboardHistoryView()
            case .dictionary:
                DashboardDictionaryView()
            case .settings:
                DashboardSettingsView()
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(chrome.canvas)
    }
}

struct VoiceChrome {
    var scheme: ColorScheme

    var canvas: Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.078, blue: 0.090)
            : Color(red: 0.925, green: 0.933, blue: 0.953)
    }

    var card: Color {
        scheme == .dark
            ? Color(red: 0.133, green: 0.141, blue: 0.165)
            : Color.white
    }

    var ink: Color {
        scheme == .dark
            ? Color.white.opacity(0.92)
            : Color(red: 0.11, green: 0.12, blue: 0.15)
    }

    var quiet: Color {
        scheme == .dark
            ? Color.white.opacity(0.58)
            : Color(red: 0.38, green: 0.41, blue: 0.48)
    }

    var accent: Color { Color(red: 0.231, green: 0.447, blue: 0.980) }

    var hairline: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }

    var shadow: Color {
        scheme == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.06)
    }

    static let windowBackground: NSColor = NSColor(name: "VoiceTypeCanvas") { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return NSColor(srgbRed: 0.075, green: 0.078, blue: 0.090, alpha: 1)
        }
        return NSColor(srgbRed: 0.925, green: 0.933, blue: 0.953, alpha: 1)
    }
}

extension AppearanceMode {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@MainActor
final class DashboardWindowController {
    static let shared = DashboardWindowController()

    private var window: NSWindow?
    private var appState: AppState?
    private var settings: SettingsStore?
    private var history: HistoryStore?

    func configure(appState: AppState, settings: SettingsStore, history: HistoryStore) {
        self.appState = appState
        self.settings = settings
        self.history = history
    }

    func show(section: DashboardSection? = nil) {
        guard let appState, let settings, let history else { return }

        if let section {
            appState.selectedSection = section
        }

        let window: NSWindow
        if let existing = self.window {
            window = existing
        } else {
            let rootView = SettingsView()
                .environmentObject(appState)
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(appState.meetings)
            let hostingController = NSHostingController(rootView: rootView)
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "VoiceType"
            newWindow.titleVisibility = .hidden
            newWindow.titlebarAppearsTransparent = true
            newWindow.backgroundColor = VoiceChrome.windowBackground
            newWindow.isMovableByWindowBackground = false
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            newWindow.setContentSize(NSSize(width: 980, height: 660))
            newWindow.center()
            newWindow.isReleasedWhenClosed = false
            self.window = newWindow
            window = newWindow
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        applyAppearance(settings.appearance)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
        window?.backgroundColor = VoiceChrome.windowBackground
    }
}
