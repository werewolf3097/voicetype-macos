import SwiftUI

@main
struct VoiceTypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var history: HistoryStore
    @StateObject private var appState: AppState
    @StateObject private var entitlement = LocalProEntitlement()

    init() {
        ClaudeFonts.registerBundledFonts()
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
                .environment(\.proEntitlement, entitlement)
                .applyPaperEnvironment(settings)
        } label: {
            MenuBarIcon(status: appState.status)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(settings)
                .environmentObject(history)
                .environmentObject(appState.dictionary)
                .environmentObject(appState.meetings)
                .environment(\.proEntitlement, entitlement)
                .applyPaperEnvironment(settings)
        }
    }
}

private struct MenuBarIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: RecordingStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                Image(systemName: "mic")
                    .accessibilityLabel("VoiceType готов")
            case .recording:
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                    .accessibilityLabel("Идёт запись")
            case .transcribing, .cleaning:
                Image(systemName: "waveform")
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                    .accessibilityLabel("Обработка речи")
            case .error:
                Image(systemName: "exclamationmark.triangle")
                    .accessibilityLabel("Ошибка VoiceType")
            }
        }
    }
}
