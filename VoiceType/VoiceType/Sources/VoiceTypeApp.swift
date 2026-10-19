import SwiftUI

@main
struct VoiceTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var history: HistoryStore
    @StateObject private var appState: AppState

    init() {
        let settingsStore = SettingsStore()
        let historyStore = HistoryStore()
        let state = AppState(settings: settingsStore, history: historyStore)
        _settings = StateObject(wrappedValue: settingsStore)
        _history = StateObject(wrappedValue: historyStore)
        _appState = StateObject(wrappedValue: state)
        DashboardWindowController.shared.configure(
            appState: state,
            settings: settingsStore,
            history: historyStore
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(settings)
                .environmentObject(appState.meetings)
        } label: {
            MenuBarIcon(status: appState.status)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(appState.meetings)
        }
    }
}

private struct MenuBarIcon: View {
    let status: RecordingStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                Image(systemName: "mic")
            case .recording:
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: true)
            case .transcribing, .cleaning:
                Image(systemName: "waveform")
                    .symbolEffect(.pulse, isActive: true)
            case .error:
                Image(systemName: "exclamationmark.triangle")
            }
        }
    }
}
