import AppKit
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case home = "Диктовка"
    case meetings = "Встречи"
    case history = "История"
    case dictionary = "Словарь"
    case settings = "Настройки"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "waveform"
        case .meetings: return "person.2"
        case .history: return "clock"
        case .dictionary: return "book.closed"
        case .settings: return "gearshape"
        }
    }

    var tileTint: Color {
        switch self {
        case .home: return PaperTokens.dictationBlue
        case .meetings: return PaperTokens.meetingsIndigo
        case .history: return PaperTokens.historyGreen
        case .dictionary: return PaperTokens.dictionaryTeal
        case .settings: return PaperTokens.settingsSlate
        }
    }

    static var mainSections: [DashboardSection] {
        [.home, .meetings, .history, .dictionary]
    }
}

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    @State private var sidebarVisible = true
    @State private var userToggledSidebar = false

    private static let sidebarWidth: CGFloat = 224
    private static let collapsedTopBarHeight: CGFloat = 44

    private var currentSection: DashboardSection {
        appState.selectedSection ?? .home
    }

    var body: some View {
        HStack(spacing: 0) {
            PaperSidebarView(
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
                        let threshold: CGFloat = currentSection == .meetings ? 940 : 760
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
        .onChange(of: settings.appearance) { _, mode in
            DashboardWindowController.shared.applyAppearance(mode)
        }
        .onChange(of: settings.paperThemeID) { _, _ in
            DashboardWindowController.shared.applyAppearance(settings.appearance)
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

// MARK: - Paper Sidebar

private struct PaperSidebarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    let isVisible: Bool
    let onCollapse: () -> Void

    @State private var hoveredSection: DashboardSection?
    @State private var hoveredMeetingID: UUID?

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

    private var hasPermissionProblem: Bool {
        !appState.hotkeyActive || !appState.microphoneAuthorized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top bar: "+ Новая встреча" + collapse sidebar button
            HStack(spacing: 8) {
                if let activeID = appState.activeMeetingID {
                    Button {
                        appState.selectedMeetingID = activeID
                        appState.selectedSection = .meetings
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .font(.system(size: 11.5, weight: .medium))
                            Text("Запись")
                                .font(fonts.uiMedium)
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                                .font(fonts.captionMedium.monospacedDigit())
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PaperTokens.recordingRed, in: RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous))
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
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(paperTheme.secondaryInkColor)
                            Text("Новая встреча")
                                .font(fonts.uiMedium)
                                .foregroundStyle(paperTheme.inkColor)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .paperSurface(level: .l2OnPaper, cornerRadius: PaperTokens.controlRadius)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: onCollapse) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(paperTheme.secondaryInkColor)
                        .frame(width: 26, height: 26)
                        .background(paperTheme.hoverColor.opacity(0.6), in: RoundedRectangle(cornerRadius: PaperTokens.chipRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Скрыть боковую панель")
                .accessibilityLabel("Скрыть боковую панель")
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Main navigation items
            VStack(alignment: .leading, spacing: 2) {
                ForEach(DashboardSection.mainSections) { section in
                    sidebarNavRow(section)
                }
            }
            .padding(.horizontal, 10)

            if !meetingsStore.meetings.isEmpty {
                Text("Недавние встречи")
                    .font(fonts.micro)
                    .foregroundStyle(paperTheme.tertiaryInkColor)
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
                Spacer(minLength: 8)
            }

            Spacer(minLength: 8)

            // Settings pinned to bottom of sidebar
            VStack(alignment: .leading, spacing: 6) {
                sidebarNavRow(.settings)
                    .padding(.horizontal, 10)

                Rectangle()
                    .fill(paperTheme.borderColor)
                    .frame(height: PaperTokens.hairline)

                Button {
                    if hasPermissionProblem {
                        appState.focusPermissionsInSettings = true
                        appState.selectedSection = .settings
                    } else {
                        appState.selectedSection = .home
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(sidebarStatusColor)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(sidebarStatusTitle)
                                .font(fonts.captionMedium)
                                .foregroundStyle(paperTheme.inkColor)
                                .lineLimit(1)
                            Text(hasPermissionProblem ? "Открыть разрешения" : settings.shortcutDisplayLabel)
                                .font(fonts.micro)
                                .foregroundStyle(paperTheme.secondaryInkColor)
                                .lineLimit(1)
                        }
                        Spacer()
                        if hasPermissionProblem {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(paperTheme.secondaryInkColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .paperSurface(level: .l1Inset, cornerRadius: PaperTokens.controlRadius)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .accessibilityLabel("Статус диктовки: \(sidebarStatusTitle)")
            }
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
            HStack(spacing: 9) {
                PaperSectionTile(
                    systemImage: section.systemImage,
                    tint: section.tileTint,
                    size: 22,
                    iconSize: 11
                )

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
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
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
                    Circle().fill(PaperTokens.recordingRed).frame(width: 6, height: 6)
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: 10.5, weight: .light))
                        .foregroundStyle(paperTheme.tertiaryInkColor)
                }
                Text(meeting.title)
                    .font(isActiveMeeting ? fonts.captionMedium : fonts.caption)
                    .foregroundStyle(isActiveMeeting ? paperTheme.inkColor : paperTheme.secondaryInkColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: PaperTokens.chipRadius, style: .continuous)
                    .fill(isActiveMeeting ? paperTheme.selectedSidebarColor : (isHovered ? paperTheme.hoverColor : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredMeetingID = hovering ? meeting.id : (hoveredMeetingID == meeting.id ? nil : hoveredMeetingID)
        }
    }

    private var sidebarStatusColor: Color {
        if hasPermissionProblem {
            return paperTheme.errorColor
        }
        switch appState.status {
        case .idle: return paperTheme.successColor
        case .recording: return PaperTokens.recordingRed
        case .transcribing, .cleaning: return paperTheme.clipboardWarningColor
        case .error: return paperTheme.errorColor
        }
    }

    private var sidebarStatusTitle: String {
        if !appState.microphoneAuthorized {
            return "Нет доступа к микрофону"
        }
        if !appState.hotkeyActive {
            return "Хоткей не работает"
        }
        switch appState.status {
        case .idle: return "Готов"
        case .recording: return "Идёт запись"
        case .transcribing: return "Распознаю…"
        case .cleaning: return "Привожу в порядок…"
        case .error: return "Ошибка"
        }
    }
}

// MARK: - Collapsed Top Bar

private struct CollapsedTopBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    let currentSection: DashboardSection
    let onExpand: () -> Void

    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onExpand) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(paperTheme.secondaryInkColor)
                    .frame(width: 26, height: 26)
                    .background(paperTheme.hoverColor, in: RoundedRectangle(cornerRadius: PaperTokens.chipRadius, style: .continuous))
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
                    PaperSectionTile(
                        systemImage: currentSection.systemImage,
                        tint: currentSection.tileTint,
                        size: 18,
                        iconSize: 9.5
                    )
                    Text(currentSection.rawValue)
                        .font(fonts.uiMedium)
                        .foregroundStyle(paperTheme.inkColor)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(paperTheme.secondaryInkColor)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .paperSurface(level: .l2OnPaper, cornerRadius: PaperTokens.controlRadius)
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
                            .font(.system(size: 11, weight: .medium))
                        Text("Новая встреча")
                    }
                }
                .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
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
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(PaperTokens.recordingRed, in: RoundedRectangle(cornerRadius: PaperTokens.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(paperTheme.sidebarColor)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(paperTheme.borderColor)
                .frame(height: PaperTokens.hairline)
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
    private var entitlement: LocalProEntitlement?

    func configure(
        appState: AppState,
        settings: SettingsStore,
        history: HistoryStore,
        entitlement: LocalProEntitlement
    ) {
        self.appState = appState
        self.settings = settings
        self.history = history
        self.entitlement = entitlement
    }

    func show(section: DashboardSection? = nil) {
        guard let appState, let settings, let history, let entitlement else { return }

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
                .environmentObject(appState.dictionary)
                .environmentObject(appState.meetings)
                .environmentObject(entitlement)
                .environment(\.proEntitlement, entitlement)
                .applyPaperEnvironment(settings)
            let hostingController = NSHostingController(rootView: rootView)
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "VoiceType"
            newWindow.titleVisibility = .visible
            newWindow.titlebarAppearsTransparent = true
            newWindow.backgroundColor = PaperTheme.cleanSheet.base.nsColor
            newWindow.isMovableByWindowBackground = false
            newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            newWindow.setContentSize(NSSize(width: 1080, height: 680))
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
        SystemAppearanceObserver.shared.refresh()
        switch mode {
        case .system:
            window?.appearance = nil
        case .light:
            window?.appearance = NSAppearance(named: .aqua)
        case .dark:
            window?.appearance = NSAppearance(named: .darkAqua)
        }
        let isDark = mode == .dark || (mode == .system && SystemAppearanceObserver.currentSystemIsDark())
        if let settings {
            let resolved = PaperTheme.resolved(themeID: settings.paperThemeID, prefersDark: isDark)
            window?.backgroundColor = resolved.base.nsColor
        }
    }
}
