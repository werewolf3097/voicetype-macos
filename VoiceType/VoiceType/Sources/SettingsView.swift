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
        case .meetings: return "person.2"
        case .history: return "clock"
        case .dictionary: return "book.closed"
        case .settings: return "gearshape"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    @State private var sidebarVisible = true
    @State private var userToggledSidebar = false

    private static let sidebarWidth: CGFloat = 222
    private static let collapsedTopBarHeight: CGFloat = 44

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }
    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    private var currentSection: DashboardSection {
        appState.selectedSection ?? .home
    }

    var body: some View {
        HStack(spacing: 0) {
            ClaudeSidebarView(
                isVisible: sidebarVisible,
                onCollapse: {
                    userToggledSidebar = true
                    setSidebarVisible(false)
                }
            )
            .frame(width: Self.sidebarWidth)
            .frame(width: sidebarVisible ? Self.sidebarWidth : 0, alignment: .trailing)
            .clipped()
            .allowsHitTesting(sidebarVisible)
            .accessibilityHidden(!sidebarVisible)

            VStack(spacing: 0) {
                CollapsedTopBarView(
                    currentSection: currentSection,
                    onExpand: {
                        userToggledSidebar = false
                        setSidebarVisible(true)
                    }
                )
                .frame(height: Self.collapsedTopBarHeight)
                .frame(height: sidebarVisible ? 0 : Self.collapsedTopBarHeight, alignment: .bottom)
                .opacity(sidebarVisible ? 0 : 1)
                .clipped()
                .allowsHitTesting(!sidebarVisible)
                .accessibilityHidden(sidebarVisible)

                DashboardDetailHostView(section: currentSection)
                    .equatable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background { PaperBackground() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width) { _, newWidth in
                        let threshold: CGFloat = currentSection == .meetings ? 940 : 780
                        if newWidth < threshold && sidebarVisible && !userToggledSidebar {
                            setSidebarVisible(false)
                        } else if newWidth >= threshold + 60 && !sidebarVisible && !userToggledSidebar {
                            setSidebarVisible(true)
                        }
                    }
            }
        )
        .frame(minWidth: 740, minHeight: 540)
        .background { PaperBackground() }
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

    private func setSidebarVisible(_ visible: Bool) {
        guard sidebarVisible != visible else { return }
        withAnimation(.snappy(duration: 0.22, extraBounce: 0)) {
            sidebarVisible = visible
        }
    }
}

// MARK: - Isolated Detail Host

private struct DashboardDetailHostView: View, Equatable {
    let section: DashboardSection

    static func == (lhs: DashboardDetailHostView, rhs: DashboardDetailHostView) -> Bool {
        lhs.section == rhs.section
    }

    var body: some View {
        switch section {
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

// MARK: - Claude-Style Sidebar

private struct ClaudeSidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    let isVisible: Bool
    let onCollapse: () -> Void

    @State private var hoveredSection: DashboardSection?
    @State private var hoveredMeetingID: UUID?

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }
    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

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
        VStack(alignment: .leading, spacing: 0) {
            // Primary Granola-style "+ New" CTA + sidebar collapse button
            HStack(spacing: 8) {
                if let activeID = appState.activeMeetingID {
                    Button {
                        appState.selectedMeetingID = activeID
                        appState.selectedSection = .meetings
                    } label: {
                        HStack(spacing: 6) {
                            ClaudeIcon(name: "waveform", size: 12, weight: .regular)
                                .symbolEffect(.variableColor.iterative, isActive: isVisible)
                            Text("Запись")
                                .font(ClaudeFonts.uiMedium)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                                .font(ClaudeFonts.smallMedium.monospacedDigit())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(theme.danger, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                        HStack(spacing: 6) {
                            ClaudeIcon(name: "plus", size: 11.5, weight: .regular)
                                .foregroundStyle(theme.secondaryInk)
                            Text("Новая встреча")
                                .font(ClaudeFonts.uiMedium)
                                .foregroundStyle(theme.ink)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onCollapse) {
                    ClaudeIcon(name: "sidebar.left", size: 13.5, weight: .light)
                        .foregroundStyle(theme.secondaryInk)
                        .frame(width: 26, height: 26)
                        .background(theme.hoverFill.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Скрыть боковую панель")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Navigation items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(DashboardSection.allCases) { section in
                    sidebarNavRow(section)
                }
            }
            .padding(.horizontal, 10)

            if !meetingsStore.meetings.isEmpty {
                Text("Недавние")
                    .font(ClaudeFonts.microMedium)
                    .foregroundStyle(theme.tertiaryInk)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 5)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1.5) {
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
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(sidebarStatusTitle)
                            .font(ClaudeFonts.smallMedium)
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        Text(settings.hotkey.rawValue)
                            .font(ClaudeFonts.micro)
                            .foregroundStyle(theme.secondaryInk)
                            .lineLimit(1)
                    }
                    Spacer()
                    ClaudeIcon(name: "slider.horizontal.3", size: 12, weight: .light)
                        .foregroundStyle(theme.secondaryInk)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6.5)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .background(paperTheme.sidebarColor)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(paperTheme.borderColor)
                .frame(width: PaperTokens.hairline)
        }
    }

    private func sidebarNavRow(_ section: DashboardSection) -> some View {
        let isSelected = currentSection == section
        let isHovered = hoveredSection == section

        return Button {
            appState.selectedSection = section
        } label: {
            HStack(spacing: 8.5) {
                ClaudeIcon(name: section.systemImage, size: 13.5, weight: isSelected ? .regular : .light)
                    .foregroundStyle(isSelected ? paperTheme.inkColor : paperTheme.secondaryInkColor)
                    .frame(width: 17)

                Text(section.rawValue)
                    .font(isSelected ? fonts.uiMedium : fonts.ui)
                    .foregroundStyle(isSelected ? paperTheme.inkColor : paperTheme.inkColor.opacity(0.86))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if section == .meetings, appState.activeMeetingID == nil, activeProcessingCount > 0 {
                    Text("\(activeProcessingCount)")
                        .font(fonts.micro.monospacedDigit())
                        .foregroundStyle(paperTheme.inkColor)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(paperTheme.insetColor, in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous)
                        .fill(paperTheme.selectedSidebarColor)
                        .paperSurface(level: .l1Inset, cornerRadius: PaperTokens.controlRadius)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous)
                        .fill(paperTheme.hoverColor)
                }
            }
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
                } else {
                    ClaudeIcon(name: "doc", size: 10.5, weight: .light)
                        .foregroundStyle(theme.tertiaryInk)
                }
                Text(meeting.title)
                    .font(isActiveMeeting ? ClaudeFonts.smallMedium : ClaudeFonts.small)
                    .foregroundStyle(isActiveMeeting ? theme.ink : theme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
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
}

// MARK: - Collapsed Top Bar

private struct CollapsedTopBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    let currentSection: DashboardSection
    let onExpand: () -> Void

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onExpand) {
                ClaudeIcon(name: "sidebar.left", size: 13.5, weight: .light)
                    .foregroundStyle(theme.secondaryInk)
                    .frame(width: 26, height: 26)
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
                HStack(spacing: 6) {
                    ClaudeIcon(name: currentSection.systemImage, size: 12.5, weight: .light)
                        .foregroundStyle(theme.secondaryInk)
                    Text(currentSection.rawValue)
                        .font(ClaudeFonts.uiMedium)
                        .foregroundStyle(theme.ink)
                    ClaudeIcon(name: "chevron.down", size: 8.5, weight: .regular)
                        .foregroundStyle(theme.secondaryInk)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
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
                        ClaudeIcon(name: "plus", size: 11, weight: .medium)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.sidebar.opacity(0.6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
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
                .applyPaperEnvironment(settings)
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
