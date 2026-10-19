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
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $appState.selectedSection) { section in
                HStack {
                    Label(section.rawValue, systemImage: section.systemImage)
                    if section == .meetings, appState.activeMeetingID != nil {
                        Spacer()
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                }
                .tag(section)
            }
            .navigationTitle("VoiceType")
            .listStyle(.sidebar)
        } detail: {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 920, minHeight: 620)
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
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            newWindow.setContentSize(NSSize(width: 920, height: 620))
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
