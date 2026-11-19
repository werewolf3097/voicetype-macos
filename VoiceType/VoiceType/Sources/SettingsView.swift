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
    @EnvironmentObject var meetingsStore: MeetingsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var sidebarVisible = true
    @State private var userToggledSidebar = false
    @State private var hoveredSection: DashboardSection?
    @State private var hoveredMeetingID: UUID?

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }

    private var currentSection: DashboardSection {
        appState.selectedSection ?? .home
    }

    private var activeProcessingCount: Int {
        meetingsStore.meetings.filter { meeting in
            switch meeting.status {
            case .queued, .transcribing, .summarizing:
                return true
            case .recording, .ready, .error:
                return false
            }
        }.count
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                if sidebarVisible {
                    claudeSidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                mainCanvas
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: geo.size.width) { _, newWidth in
                let threshold: CGFloat = currentSection == .meetings ? 940 : 780
                if newWidth < threshold && sidebarVisible && !userToggledSidebar {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarVisible = false
                    }
                } else if newWidth >= threshold + 60 && !sidebarVisible && !userToggledSidebar {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarVisible = true
                    }
                }
            }
        }
        .frame(minWidth: 740, minHeight: 540)
        .background(theme.canvas)
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

    // MARK: - Claude-Style Sidebar

    private var claudeSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Primary Claude-style "+ New" CTA + sidebar collapse button
            HStack(spacing: 8) {
                if let activeID = appState.activeMeetingID {
                    Button {
                        appState.selectedMeetingID = activeID
                        appState.selectedSection = .meetings
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, isActive: true)
                            Text("Запись")
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                                .font(.caption.monospacedDigit().weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(theme.danger, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        if let id = appState.startMeeting(
                            template: .general,
                            audioSource: settings.meetingAudioSource
                        ) {
                            appState.selectedMeetingID = id
                            appState.selectedSection = .meetings
                        }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.ink)
                            Text("Новая встреча")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    userToggledSidebar = true
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarVisible = false
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryInk)
                        .frame(width: 28, height: 28)
                        .background(theme.hoverFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Скрыть боковую панель")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 12)

            // Navigation items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(DashboardSection.allCases) { section in
                    sidebarNavRow(section)
                }
            }
            .padding(.horizontal, 10)

            if !meetingsStore.meetings.isEmpty {
                Text("Недавние")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.tertiaryInk)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 6)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(meetingsStore.meetings.prefix(8)) { meeting in
                            recentMeetingRow(meeting)
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .scrollIndicators(.hidden)
            } else {
                Spacer()
            }

            Spacer(minLength: 8)

            // Bottom status pill
            Divider()
                .overlay(theme.border)

            Button {
                appState.selectedSection = .settings
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(sidebarStatusColor)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sidebarStatusTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        Text(settings.hotkey.rawValue)
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryInk)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .frame(width: 222)
        .frame(maxHeight: .infinity)
        .background(theme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.border)
                .frame(width: 1)
        }
    }

    private func sidebarNavRow(_ section: DashboardSection) -> some View {
        let isSelected = currentSection == section
        let isHovered = hoveredSection == section

        return Button {
            appState.selectedSection = section
        } label: {
            HStack(spacing: 9) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 13.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? theme.ink : theme.secondaryInk)
                    .frame(width: 18)

                Text(section.rawValue)
                    .font(.callout.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if section == .meetings, appState.activeMeetingID == nil, activeProcessingCount > 0 {
                    Text("\(activeProcessingCount)")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.accentInk)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(theme.accentSoft, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.selectedFill : (isHovered ? theme.hoverFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredSection = hovering ? section : (hoveredSection == section ? nil : hoveredSection)
        }
    }

    private func recentMeetingRow(_ meeting: MeetingRecord) -> some View {
        let isActiveMeeting = currentSection == .meetings && appState.selectedMeetingID == meeting.id
        let isHovered = hoveredMeetingID == meeting.id

        return Button {
            appState.selectedMeetingID = meeting.id
            appState.selectedSection = .meetings
        } label: {
            HStack(spacing: 7) {
                if case .transcribing = meeting.status {
                    ProgressView().controlSize(.mini)
                } else if case .summarizing = meeting.status {
                    ProgressView().controlSize(.mini)
                } else if meeting.status == .recording {
                    Circle().fill(theme.danger).frame(width: 6, height: 6)
                }
                Text(meeting.title)
                    .font(.caption.weight(isActiveMeeting ? .semibold : .regular))
                    .foregroundStyle(isActiveMeeting ? theme.ink : theme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActiveMeeting ? theme.selectedFill : (isHovered ? theme.hoverFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredMeetingID = hovering ? meeting.id : (hoveredMeetingID == meeting.id ? nil : hoveredMeetingID)
        }
    }

    private var sidebarStatusColor: Color {
        switch appState.status {
        case .idle: return appState.hotkeyActive ? theme.success : theme.warning
        case .recording: return theme.danger
        case .transcribing, .cleaning: return theme.accent
        case .error: return theme.warning
        }
    }

    private var sidebarStatusTitle: String {
        switch appState.status {
        case .idle: return appState.hotkeyActive ? "Готов слушать" : "Нужны права"
        case .recording: return "Запись голоса…"
        case .transcribing: return "Распознаю…"
        case .cleaning: return "Обрабатываю…"
        case .error: return "Ошибка"
        }
    }

    // MARK: - Main Canvas

    private var mainCanvas: some View {
        VStack(spacing: 0) {
            if !sidebarVisible {
                HStack(spacing: 10) {
                    Button {
                        userToggledSidebar = false
                        withAnimation(.easeInOut(duration: 0.18)) {
                            sidebarVisible = true
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryInk)
                            .frame(width: 28, height: 28)
                            .background(theme.hoverFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Показать боковую панель")

                    Menu {
                        ForEach(DashboardSection.allCases) { section in
                            Button {
                                appState.selectedSection = section
                            } label: {
                                Label(section.rawValue, systemImage: section.systemImage)
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: currentSection.systemImage)
                                .foregroundStyle(theme.secondaryInk)
                            Text(currentSection.rawValue)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(theme.ink)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(theme.secondaryInk)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()

                    Spacer()

                    if appState.activeMeetingID == nil {
                        Button {
                            if let id = appState.startMeeting(
                                template: .general,
                                audioSource: settings.meetingAudioSource
                            ) {
                                appState.selectedMeetingID = id
                                appState.selectedSection = .meetings
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                Text("Новая встреча")
                            }
                        }
                        .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
                    } else {
                        Button {
                            appState.selectedMeetingID = appState.activeMeetingID
                            appState.selectedSection = .meetings
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(Color.white).frame(width: 6, height: 6)
                                Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(ClaudePrimaryButtonStyle(compact: true, tintColor: theme.danger))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(theme.sidebar.opacity(0.6))

                Divider().overlay(theme.border)
            }

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(theme.canvas)
    }

    @ViewBuilder
    private var detailView: some View {
        switch currentSection {
        case .home:
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
            newWindow.titleVisibility = .visible
            newWindow.titlebarAppearsTransparent = true
            newWindow.backgroundColor = ClaudeTheme.windowBackgroundNSColor
            newWindow.isMovableByWindowBackground = false
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 1120, height: 700))
            newWindow.minSize = NSSize(width: 740, height: 540)
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
        window?.backgroundColor = ClaudeTheme.windowBackgroundNSColor
    }
}
