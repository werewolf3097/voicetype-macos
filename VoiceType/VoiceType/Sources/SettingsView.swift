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

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detail
        }
        .frame(minWidth: 920, minHeight: 620)
        .background(Self.canvas)
        .preferredColorScheme(.dark)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("VoiceType")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.62))
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

            ForEach(DashboardSection.allCases) { section in
                sidebarRow(section)
            }
            Spacer()
        }
        .padding(.top, 36)
        .padding(.horizontal, 12)
        .frame(width: 116)
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.145, green: 0.145, blue: 0.155))
    }

    private func sidebarRow(_ section: DashboardSection) -> some View {
        let selected = (appState.selectedSection ?? .home) == section
        return Button {
            appState.selectedSection = section
        } label: {
            VStack(spacing: 6) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 16, weight: .medium))
                Text(section.rawValue)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? Color.white : Color(white: 0.62))
            .frame(width: 92, height: 92)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.08) : Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.white.opacity(0.14) : Color.white.opacity(0.08))
            )
            .overlay(alignment: .topTrailing) {
                if section == .meetings, appState.activeMeetingID != nil {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private static let canvas = Color(red: 0.11, green: 0.11, blue: 0.118)
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
            newWindow.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1)
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
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
