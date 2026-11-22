import AppKit
import SwiftUI

struct DashboardMeetingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    @State private var searchQuery: String = ""
    @State private var detailTab: DetailTab = .recap
    @State private var transcriptSearch: String = ""
    @State private var copiedFeedback: Bool = false
    @State private var isEditingRecapMarkdown: Bool = false
    @State private var newActionItemText: String = ""
    @State private var showSpeakersPopover: Bool = false
    @State private var meetingPendingDelete: MeetingRecord?
    @State private var hoveredMeetingID: UUID?
    @State private var showMeetingsList: Bool = true
    @State private var meetingsListWidth: CGFloat = 248
    @State private var dragStartListWidth: CGFloat? = nil
    @State private var isHoveringDivider: Bool = false

    private var theme: MeetingsPaperTheme { MeetingsPaperTheme(paper: paperTheme) }
    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    private enum DetailTab: String, CaseIterable, Identifiable {
        case recap = "Рекап и задачи"
        case notes = "Мои заметки"
        case transcript = "Транскрипт"

        var id: String { rawValue }
    }

    private var filteredMeetings: [MeetingRecord] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return meetingsStore.meetings }
        return meetingsStore.meetings.filter { m in
            m.title.lowercased().contains(q)
                || m.rawNotes.lowercased().contains(q)
                || m.recapMarkdown.lowercased().contains(q)
                || m.segments.contains(where: { $0.text.lowercased().contains(q) })
        }
    }

    private var selectedMeeting: MeetingRecord? {
        if let id = appState.selectedMeetingID, let found = meetingsStore.meeting(withID: id) {
            return found
        }
        if let activeID = appState.activeMeetingID, let found = meetingsStore.meeting(withID: activeID) {
            return found
        }
        return filteredMeetings.first
    }

    var body: some View {
        HStack(spacing: 0) {
            meetingsListColumn
                .frame(width: meetingsListWidth)
                .frame(width: showMeetingsList ? meetingsListWidth : 0, alignment: .trailing)
                .clipped()
                .allowsHitTesting(showMeetingsList)

            meetingsListDivider
                .frame(width: showMeetingsList ? 1 : 0)
                .opacity(showMeetingsList ? 1 : 0)
                .allowsHitTesting(showMeetingsList)

            detailPane
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                .background { PaperBackground() }
        }
        .onAppear {
            if appState.selectedMeetingID == nil {
                appState.selectedMeetingID = appState.activeMeetingID ?? meetingsStore.meetings.first?.id
            }
        }
        .onChange(of: appState.activeMeetingID) { _, newValue in
            if let newValue {
                appState.selectedMeetingID = newValue
            }
        }
        .confirmationDialog(
            "Удалить встречу «\(meetingPendingDelete?.title ?? "")»?",
            isPresented: Binding(
                get: { meetingPendingDelete != nil },
                set: { if !$0 { meetingPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                if let target = meetingPendingDelete {
                    appState.deleteMeeting(target.id)
                    if appState.selectedMeetingID == target.id {
                        appState.selectedMeetingID = meetingsStore.meetings.first?.id
                    }
                    meetingPendingDelete = nil
                }
            }
            Button("Отмена", role: .cancel) {
                meetingPendingDelete = nil
            }
        } message: {
            Text("Заметки, транскрипт, рекап и сохранённые аудиофайлы этой встречи будут удалены.")
        }
    }

    // MARK: - Meetings List Column

    private var meetingsListDivider: some View {
        Rectangle()
            .fill(theme.border)
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 7)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering && !isHoveringDivider {
                            isHoveringDivider = true
                            NSCursor.resizeLeftRight.push()
                        } else if !hovering && isHoveringDivider {
                            isHoveringDivider = false
                            NSCursor.pop()
                        }
                    }
                    .onDisappear {
                        if isHoveringDivider {
                            isHoveringDivider = false
                            NSCursor.pop()
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let base = dragStartListWidth ?? meetingsListWidth
                                if dragStartListWidth == nil {
                                    dragStartListWidth = base
                                }
                                meetingsListWidth = min(320, max(215, base + value.translation.width))
                            }
                            .onEnded { _ in
                                dragStartListWidth = nil
                            }
                    )
            )
    }

    private var meetingsListColumn: some View {
        VStack(spacing: 0) {
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Text("Встречи")
                        .font(fonts.panelTitle)
                        .tracking(-0.25)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Spacer()
                    if appState.activeMeetingID == nil {
                        Button {
                            if let id = appState.startMeeting(
                                template: .general,
                                audioSource: settings.meetingAudioSource
                            ) {
                                appState.selectedMeetingID = id
                            }
                        } label: {
                            HStack(spacing: 4) {
                                ClaudeIcon(name: "plus", size: 10.5, weight: .regular)
                                Text("Новая")
                            }
                        }
                        .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                        .help("Начать запись новой встречи")
                    } else {
                        Button {
                            appState.selectedMeetingID = appState.activeMeetingID
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(Color.white).frame(width: 6, height: 6)
                                Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(PaperButtonStyle(role: .destructive, compact: true))
                    }
                }

                HStack(spacing: 6) {
                    ClaudeIcon(name: "magnifyingglass", size: 11, weight: .light)
                        .foregroundStyle(theme.secondaryInk)
                    TextField("Поиск по встречам…", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(fonts.ui)
                        .foregroundStyle(theme.ink)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            ClaudeIcon(name: "xmark", size: 9.5, weight: .regular)
                                .foregroundStyle(theme.secondaryInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5.5)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7.5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().overlay(theme.border)

            if filteredMeetings.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    ClaudeIcon(name: searchQuery.isEmpty ? "person.2" : "magnifyingglass", size: 22, weight: .ultraLight)
                        .foregroundStyle(theme.tertiaryInk)
                    Text(searchQuery.isEmpty ? "Пока нет встреч" : "Ничего не найдено")
                        .font(fonts.uiMedium)
                        .foregroundStyle(theme.secondaryInk)
                    if searchQuery.isEmpty {
                        Text("Нажмите «Новая» для старта записи")
                            .font(fonts.caption)
                            .foregroundStyle(theme.tertiaryInk)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filteredMeetings) { meeting in
                            meetingRow(meeting)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background { PaperBackground() }
    }

    private func meetingRow(_ meeting: MeetingRecord) -> some View {
        let isSelected = selectedMeeting?.id == meeting.id
        let isHovered = hoveredMeetingID == meeting.id

        return Button {
            appState.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .center, spacing: 9) {
                // Granola-style soft rounded-square icon tile
                ZStack {
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .fill(isSelected ? theme.surface.opacity(0.85) : theme.surfaceSubtle)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                .strokeBorder(theme.border.opacity(0.65), lineWidth: 0.75)
                        )
                    statusIcon(for: meeting.status)
                }
                .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(isSelected ? fonts.uiMedium : fonts.ui)
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(Self.shortDateFormatter.string(from: meeting.date))
                        Text("·")
                        Text(meeting.template.rawValue)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if meeting.durationSeconds > 0 {
                            Text(MeetingRecord.formatTimestamp(meeting.durationSeconds))
                                .monospacedDigit()
                                .foregroundStyle(theme.tertiaryInk)
                        }
                    }
                    .font(fonts.micro)
                    .foregroundStyle(theme.secondaryInk)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.selectedFill : (isHovered ? theme.hoverFill : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredMeetingID = hovering ? meeting.id : (hoveredMeetingID == meeting.id ? nil : hoveredMeetingID)
        }
        .contextMenu {
            Button("Скопировать Markdown") {
                TextInjector.copyToClipboard(meetingsStore.fullExportMarkdown(for: meeting))
            }
            Button("Показать recap.md в Finder") {
                meetingsStore.revealMarkdownInFinder(meeting)
            }
            if meeting.audioFileName != nil {
                Button("Показать аудио в Finder") {
                    meetingsStore.revealAudioInFinder(meeting)
                }
            }
            Divider()
            Button("Удалить встречу…", role: .destructive) {
                meetingPendingDelete = meeting
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for status: MeetingStatus) -> some View {
        switch status {
        case .recording:
            Circle()
                .fill(theme.danger)
                .frame(width: 7, height: 7)
        case .queued:
            ClaudeIcon(name: "clock", size: 11.5, weight: .light)
                .foregroundStyle(theme.warning)
        case .transcribing, .summarizing:
            ProgressView()
                .controlSize(.mini)
        case .ready:
            ClaudeIcon(name: "doc", size: 11.5, weight: .light)
                .foregroundStyle(theme.secondaryInk)
        case .error:
            ClaudeIcon(name: "exclamationmark.triangle", size: 11.5, weight: .light)
                .foregroundStyle(theme.warning)
        }
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        if let meeting = selectedMeeting {
            if meeting.status == .recording {
                liveRecordingView(meeting)
            } else {
                completedMeetingView(meeting)
            }
        } else {
            emptyStateView
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 10) {
                ClaudeIcon(name: "person.2", size: 22, weight: .light)
                    .foregroundStyle(theme.accent)
                    .frame(width: 48, height: 48)
                    .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                Text("Заметки и рекапы встреч")
                    .font(fonts.pageTitle)
                    .tracking(-0.35)
                    .foregroundStyle(theme.ink)

                Text("Записывайте созвоны без ботов в Zoom, Meet или Telegram. Пишите короткие тезисы, а VoiceType разложит речь по спикерам и соберёт структурированный рекап.")
                    .font(fonts.ui)
                    .lineSpacing(3)
                    .foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            ClaudeFlowLayout(horizontalSpacing: 7, verticalSpacing: 7) {
                ForEach([MeetingTemplate.general, .oneOnOne, .standup, .sales]) { tpl in
                    Button {
                        if let id = appState.startMeeting(
                            template: tpl,
                            audioSource: settings.meetingAudioSource
                        ) {
                            appState.selectedMeetingID = id
                        }
                    } label: {
                        HStack(spacing: 5) {
                            ClaudeIcon(name: tpl.systemImage, size: 11.5, weight: .light)
                                .foregroundStyle(theme.accent)
                            Text(tpl.rawValue)
                        }
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                }
            }
            .frame(maxWidth: 520)

            Button {
                if let id = appState.startMeeting(
                    template: .general,
                    audioSource: settings.meetingAudioSource
                ) {
                    appState.selectedMeetingID = id
                }
            } label: {
                HStack(spacing: 6) {
                    ClaudeIcon(name: "record.circle", size: 12.5, weight: .regular)
                    Text("Начать запись встречи")
                }
            }
            .buttonStyle(PaperButtonStyle(role: .primary))

            if settings.meetingAudioSource == .micAndSystem && !appState.screenCaptureAuthorized {
                systemAudioPermissionWarning
                    .frame(maxWidth: 560)
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var systemAudioPermissionWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.warning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        appState.activeMeetingSystemAudioError != nil
                            ? "Системный звук не записывается — идёт только канал микрофона."
                            : "Доступ к записи системного звука не активен (будет записан только микрофон)."
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.ink)

                    if let sysError = appState.activeMeetingSystemAudioError, !sysError.isEmpty {
                        Text("Причина: \(sysError)")
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryInk)
                    }

                    Text("Откройте «Запись экрана и системного аудио». Если тумблер VoiceType уже включён от прошлой сборки — выключите и включите его заново (или «–» / «+»), затем нажмите «Перезапустить».")
                        .font(.caption2)
                        .foregroundStyle(theme.secondaryInk)
                }
                Spacer(minLength: 0)
            }

            ClaudeFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                Button("Открыть настройки") {
                    PermissionsHelper.openScreenCaptureSettings()
                }
                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))

                Button("Перезапустить") {
                    PermissionsHelper.relaunchApp()
                }
                .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
            }
        }
        .padding(12)
        .background(theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.warning.opacity(0.25))
        )
    }

    // MARK: - Live Meeting Notepad

    private func liveRecordingView(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    liveRecordingBadge
                    liveChannelStatusBadge(for: meeting)
                    Spacer()
                    liveRecordingButtons
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        liveRecordingBadge
                        liveChannelStatusBadge(for: meeting)
                        Spacer()
                    }
                    liveRecordingButtons
                }
            }

            if meeting.audioSource == .micAndSystem && (!appState.screenCaptureAuthorized || (appState.meetingElapsedSeconds >= 2 && !appState.activeMeetingSystemAudioCapturing)) {
                systemAudioPermissionWarning
            }

            ClaudeFlowLayout(horizontalSpacing: 12, verticalSpacing: 8) {
                TextField(
                    "Название встречи…",
                    text: Binding(
                        get: { meeting.title },
                        set: { newTitle in
                            meetingsStore.update(meeting.id) { $0.title = newTitle }
                        }
                    )
                )
                .font(fonts.meetingTitle)
                .tracking(-0.3)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.ink)
                .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

                templateMenuPill(for: meeting, regenerateOnChange: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Живой блокнот встречи — короткие тезисы станут каркасом рекапа")
                    .font(fonts.caption)
                    .foregroundStyle(theme.secondaryInk)

                TextEditor(
                    text: Binding(
                        get: { meeting.rawNotes },
                        set: { newNotes in
                            meetingsStore.update(meeting.id) { $0.rawNotes = newNotes }
                        }
                    )
                )
                .font(fonts.body)
                .foregroundStyle(theme.ink)
                .scrollContentBackground(.hidden)
                .padding(14)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func liveChannelStatusBadge(for meeting: MeetingRecord) -> some View {
        if meeting.audioSource == .micAndSystem {
            if appState.activeMeetingSystemAudioCapturing {
                HStack(spacing: 5) {
                    ClaudeIcon(name: "speaker.wave.2", size: 11, weight: .light)
                    Text("2 канала: Вы + Собеседники")
                        .font(fonts.captionMedium)
                }
                .foregroundStyle(theme.accentInk)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.accentSoft, in: Capsule())
                .lineLimit(1)
            } else {
                HStack(spacing: 5) {
                    ClaudeIcon(name: "mic", size: 11, weight: .light)
                    Text("Только микрофон (нет системного звука)")
                        .font(fonts.captionMedium)
                }
                .foregroundStyle(theme.warning)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(theme.warning.opacity(0.12), in: Capsule())
                .lineLimit(1)
            }
        } else {
            HStack(spacing: 5) {
                ClaudeIcon(name: "mic", size: 11, weight: .light)
                Text(meeting.audioSource.rawValue)
                    .font(fonts.caption)
            }
            .foregroundStyle(theme.secondaryInk)
            .lineLimit(1)
        }
    }

    private var liveRecordingBadge: some View {
        HStack(spacing: 6) {
            ClaudeIcon(name: "waveform", size: 12, weight: .regular)
                .symbolEffect(.variableColor.iterative, isActive: true)
                .foregroundStyle(theme.danger)
            Text("Запись")
                .font(fonts.captionMedium)
                .foregroundStyle(theme.danger)
            Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                .font(fonts.captionMedium.monospacedDigit())
                .foregroundStyle(theme.ink)
        }
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(theme.danger.opacity(0.10), in: Capsule())
    }

    private var liveRecordingButtons: some View {
        HStack(spacing: 8) {
            Button("Отменить") {
                appState.cancelMeeting()
                appState.selectedMeetingID = meetingsStore.meetings.first?.id
            }
            .buttonStyle(PaperButtonStyle(role: .destructive, compact: true))

            Button {
                appState.finishMeeting()
                detailTab = .recap
            } label: {
                HStack(spacing: 5) {
                    ClaudeIcon(name: "sparkles", size: 11, weight: .regular)
                    Text("Завершить и создать рекап")
                }
            }
            .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
        }
    }

    // MARK: - Completed / Processing Meeting View

    private func completedMeetingView(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            // Header: Title + fixed-size action buttons (never crush or stretch vertically)
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    if !showMeetingsList {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                showMeetingsList = true
                            }
                        } label: {
                            ClaudeIcon(name: "list.bullet", size: 12, weight: .light)
                                .foregroundStyle(theme.secondaryInk)
                                .frame(width: 26, height: 26)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(theme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Показать список встреч")
                    }

                    TextField(
                        "Название встречи",
                        text: Binding(
                            get: { meeting.title },
                            set: { newTitle in
                                meetingsStore.update(meeting.id) { $0.title = newTitle }
                            }
                        ),
                        axis: .vertical
                    )
                    .font(fonts.meetingTitle)
                    .tracking(-0.3)
                    .textFieldStyle(.plain)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1...2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                showMeetingsList.toggle()
                            }
                        } label: {
                            ClaudeIcon(
                                name: showMeetingsList ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left",
                                size: 11.5,
                                weight: .light
                            )
                            .foregroundStyle(theme.secondaryInk)
                            .frame(width: 26, height: 26)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(theme.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(showMeetingsList ? "Развернуть конспект на всю ширину" : "Вернуть список встреч")

                        ViewThatFits(in: .horizontal) {
                            Button {
                                copyMeetingMarkdown(meeting)
                            } label: {
                                HStack(spacing: 5) {
                                    ClaudeIcon(name: copiedFeedback ? "checkmark" : "doc.on.doc", size: 11, weight: .light)
                                    Text(copiedFeedback ? "Скопировано" : "Копировать")
                                }
                            }
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))

                            Button {
                                copyMeetingMarkdown(meeting)
                            } label: {
                                ClaudeIcon(name: copiedFeedback ? "checkmark" : "doc.on.doc", size: 11, weight: .light)
                            }
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                        }
                        .help("Скопировать Markdown в буфер обмена")

                        Menu {
                            if meeting.status == .ready {
                                Button {
                                    Task {
                                        await appState.regenerateRecap(for: meeting.id)
                                    }
                                } label: {
                                    Label("Пересобрать рекап", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }

                            if meeting.status == .ready, meetingsStore.exportedFileURL(for: meeting) != nil {
                                Button {
                                    meetingsStore.revealInExportFolder(meeting)
                                } label: {
                                    Label("Показать в папке экспорта", systemImage: "arrow.up.right.square")
                                }
                            } else if meeting.status == .ready,
                                      case .webhook = MeetingsStore.resolvedExportDestination() {
                                Button {
                                    Task {
                                        await meetingsStore.sendExportWebhookIfNeeded(for: meeting)
                                    }
                                } label: {
                                    Label("Отправить по URL экспорта", systemImage: "paperplane")
                                }
                            }

                            Button {
                                meetingsStore.revealMarkdownInFinder(meeting)
                            } label: {
                                Label("Показать recap.md в Finder", systemImage: "folder")
                            }

                            if meetingsStore.audioFileURL(for: meeting) != nil {
                                Button {
                                    meetingsStore.revealAudioInFinder(meeting)
                                } label: {
                                    Label("Показать аудиозапись в Finder", systemImage: "waveform.circle")
                                }
                            }

                            Divider()

                            Button(role: .destructive) {
                                meetingPendingDelete = meeting
                            } label: {
                                Label("Удалить встречу…", systemImage: "trash")
                            }
                        } label: {
                            ClaudeIcon(name: "ellipsis", size: 12, weight: .regular)
                                .foregroundStyle(theme.ink)
                                .frame(width: 26, height: 26)
                                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(theme.border, lineWidth: 1)
                                )
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Дополнительные действия")
                    }
                    .fixedSize()
                }

                // Wrapping metadata + template selector (never truncates with "...")
                ClaudeFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                    templateMenuPill(for: meeting, regenerateOnChange: true)

                    metadataChip(Self.fullDateFormatter.string(from: meeting.date), systemImage: "calendar")

                    metadataChip("\(max(1, Int((meeting.durationSeconds / 60).rounded()))) мин", systemImage: "clock")

                    metadataChip(
                        meeting.stereoParties
                            ? "Стерео: Вы + Собеседники"
                            : (meeting.sysAudioFileName == nil ? "Только микрофон" : "Диаризация спикеров"),
                        systemImage: meeting.stereoParties ? "person.2" : "mic"
                    )

                    if let engine = meeting.transcriptionEngine, !engine.isEmpty {
                        Text(engine)
                            .font(fonts.caption)
                            .foregroundStyle(theme.secondaryInk)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(theme.surfaceSubtle, in: Capsule())
                    }

                    if let lang = meeting.languageSummary {
                        Text(lang)
                            .font(fonts.captionMedium)
                            .foregroundStyle(theme.accentInk)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(theme.accentSoft, in: Capsule())
                    }
                }
            }

            statusBanner(for: meeting)

            // Responsive tab switcher (pills never wrap internally)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(DetailTab.allCases) { tab in
                        let isSelected = detailTab == tab
                        let label = (tab == .transcript && !meeting.segments.isEmpty)
                            ? "Транскрипт (\(meeting.segments.count))"
                            : tab.rawValue

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                detailTab = tab
                            }
                        } label: {
                            Text(label)
                                .font(isSelected ? fonts.captionMedium : fonts.caption)
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(isSelected ? theme.ink : theme.secondaryInk)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(isSelected ? theme.surface : Color.clear)
                                        .shadow(color: isSelected ? theme.cardShadow : .clear, radius: 3, y: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            }

            switch detailTab {
            case .recap:
                recapTabView(meeting)
            case .notes:
                notesTabView(meeting)
            case .transcript:
                transcriptTabView(meeting)
            }
        }
        .padding(20)
    }

    private func templateMenuPill(for meeting: MeetingRecord, regenerateOnChange: Bool) -> some View {
        Menu {
            ForEach(MeetingTemplate.allCases) { tpl in
                Button {
                    meetingsStore.update(meeting.id) { $0.template = tpl }
                    if regenerateOnChange {
                        Task {
                            await appState.regenerateRecap(for: meeting.id)
                        }
                    }
                } label: {
                    Label(tpl.rawValue, systemImage: tpl.systemImage)
                }
            }
        } label: {
            HStack(spacing: 5) {
                ClaudeIcon(name: meeting.template.systemImage, size: 11, weight: .light)
                    .foregroundStyle(theme.secondaryInk)
                Text(meeting.template.rawValue)
                    .font(fonts.captionMedium)
                    .lineLimit(1)
                ClaudeIcon(name: "chevron.down", size: 8, weight: .regular)
                    .foregroundStyle(theme.secondaryInk)
            }
            .foregroundStyle(theme.ink)
            .padding(.horizontal, 8.5)
            .padding(.vertical, 3.5)
            .background(theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(regenerateOnChange ? "Сменить шаблон и пересобрать рекап" : "Выбрать шаблон")
    }

    private func metadataChip(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 4) {
            ClaudeIcon(name: systemImage, size: 11, weight: .light)
            Text(text)
                .font(fonts.caption)
                .lineLimit(1)
        }
        .foregroundStyle(theme.secondaryInk)
        .padding(.vertical, 2.5)
        .fixedSize()
    }

    private func copyMeetingMarkdown(_ meeting: MeetingRecord) {
        TextInjector.copyToClipboard(meetingsStore.fullExportMarkdown(for: meeting))
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            copiedFeedback = false
        }
    }

    // MARK: - Status Banners & Unified Progress Bar

    @ViewBuilder
    private func statusBanner(for meeting: MeetingRecord) -> some View {
        switch meeting.status {
        case .queued(let msg):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(theme.warning)
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(theme.ink)
                    Spacer()
                    queuedActionButtons(meeting)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(theme.warning)
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(theme.ink)
                    }
                    queuedActionButtons(meeting)
                }
            }
            .padding(12)
            .background(theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.warning.opacity(0.25))
            )

        case .transcribing:
            transcribingStatusBanner(for: meeting)

        case .summarizing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Формирование структурированного рекапа и списка задач…")
                    .font(.callout)
                    .foregroundStyle(theme.ink)
                Spacer()
            }
            .padding(12)
            .background(theme.accentSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.25))
            )

        case .error(let msg):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.warning)
                    Text(msg)
                        .font(.callout)
                        .foregroundStyle(theme.ink)
                    Spacer(minLength: 0)
                }

                ClaudeFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
                    if meetingsStore.audioFileURL(for: meeting) != nil {
                        if settings.hasExternalWhisperServer {
                            Button("На внешний сервер") {
                                appState.retryMeetingOnWindows(meeting.id)
                            }
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                        }

                        Button("Повторить (\(appState.nextCloudMeetingProviderTitle))") {
                            appState.transcribeMeetingUrgentGapi(meeting.id)
                        }
                        .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
                    }
                    Button("Собрать из заметок") {
                        Task {
                            await appState.regenerateRecap(for: meeting.id)
                        }
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                }
            }
            .padding(12)
            .background(theme.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.warning.opacity(0.25))
            )

        case .ready, .recording:
            EmptyView()
        }
    }

    private func queuedActionButtons(_ meeting: MeetingRecord) -> some View {
        ClaudeFlowLayout(horizontalSpacing: 8, verticalSpacing: 6) {
            if settings.hasExternalWhisperServer {
                Button("Проверить сервер") {
                    appState.retryMeetingOnWindows(meeting.id)
                }
                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
            }

            Button("Отправить через \(appState.nextCloudMeetingProviderTitle)") {
                appState.transcribeMeetingUrgentGapi(meeting.id)
            }
            .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
        }
    }

    private func transcribingStatusBanner(for meeting: MeetingRecord) -> some View {
        let engineName = meeting.transcriptionEngine ?? "Сервер распознавания"
        let isGapi = engineName == "gapi.uz"
        let isLocal = engineName.contains("Whisper (") || engineName == "Внешний сервер"
        let progress = resolvedTranscriptionProgress(for: meeting, isGapi: isGapi)
        let percent = Int((progress.overallFraction * 100).rounded())

        return VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Распознавание · \(engineName)")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.ink)
                        .lineLimit(1)
                    Spacer()
                    Text("\(percent)%")
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .foregroundStyle(theme.secondaryInk)
                        .fixedSize()
                    if isLocal, meetingsStore.audioFileURL(for: meeting) != nil {
                        Button("Переключить на \(appState.nextCloudMeetingProviderTitle)") {
                            appState.transcribeMeetingUrgentGapi(meeting.id)
                        }
                        .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Распознавание · \(engineName)")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(theme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text("\(percent)%")
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(theme.secondaryInk)
                    }
                    if isLocal, meetingsStore.audioFileURL(for: meeting) != nil {
                        Button("Переключить на \(appState.nextCloudMeetingProviderTitle)") {
                            appState.transcribeMeetingUrgentGapi(meeting.id)
                        }
                        .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                    }
                }
            }

            unifiedProgressBar(for: progress, isGapi: isGapi)

            HStack(spacing: 8) {
                transcriptionStageLabel(for: progress, isGapi: isGapi)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let total = progress.totalSeconds, total > 0 {
                    Text("\(MeetingRecord.formatTimestamp(progress.processedSeconds)) / \(MeetingRecord.formatTimestamp(total))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryInk)
                        .fixedSize()
                } else if progress.processedSeconds > 0 {
                    Text("обработано \(MeetingRecord.formatTimestamp(progress.processedSeconds))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryInk)
                        .fixedSize()
                }
            }
        }
        .meetingsPaperCard(paperTheme, cornerRadius: 12, padding: 12)
    }

    private func resolvedTranscriptionProgress(
        for meeting: MeetingRecord,
        isGapi: Bool
    ) -> MeetingTranscriptionProgress {
        if let live = appState.meetingTranscriptionProgress[meeting.id] {
            return live
        }
        let fallbackTotal = meeting.durationSeconds > 0 ? meeting.durationSeconds : nil
        let fallbackProcessed = max(0, meeting.progressSeconds ?? 0)
        let uploadShare = isGapi ? 0.25 : 0.05
        if fallbackProcessed > 0 {
            let ratio = (fallbackTotal ?? 0) > 0 ? min(1.0, fallbackProcessed / fallbackTotal!) : 0
            let overall = uploadShare + (1.0 - uploadShare) * ratio
            return MeetingTranscriptionProgress(
                stage: .transcribing(processedSeconds: fallbackProcessed, totalSeconds: fallbackTotal),
                overallFraction: overall,
                uploadPhaseEndFraction: uploadShare,
                uploadCompleted: true,
                processedSeconds: fallbackProcessed,
                totalSeconds: fallbackTotal
            )
        }
        return MeetingTranscriptionProgress(
            stage: .preparingAudio,
            overallFraction: 0.01,
            uploadPhaseEndFraction: uploadShare,
            uploadCompleted: false,
            processedSeconds: 0,
            totalSeconds: fallbackTotal
        )
    }

    private func unifiedProgressBar(for progress: MeetingTranscriptionProgress, isGapi: Bool) -> some View {
        let fraction = MeetingTranscriptionProgress.clamp(progress.overallFraction)
        let milestone = progress.uploadPhaseEndFraction

        return GeometryReader { geo in
            let width = max(0, geo.size.width)
            let fillWidth = width * fraction

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.surfaceSubtle)

                if let milestone, milestone > 0,
                   (isGapi ? progress.uploadCompleted : (progress.stage != .preparingAudio && fraction >= milestone)) {
                    let stageOneWidth = min(fillWidth, width * milestone)
                    let stageTwoWidth = max(0, fillWidth - stageOneWidth)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(theme.accentLight)
                            .frame(width: stageOneWidth)
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: stageTwoWidth)
                    }
                    .clipShape(Capsule())
                } else {
                    Capsule()
                        .fill(theme.accent)
                        .frame(width: fillWidth)
                }

                if isGapi, let milestone, milestone > 0, milestone < 1 {
                    Rectangle()
                        .fill(theme.surface)
                        .frame(width: 1.5, height: 6)
                        .offset(x: width * milestone - 0.75)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: fraction)
        }
        .frame(height: 6)
    }

    @ViewBuilder
    private func transcriptionStageLabel(for progress: MeetingTranscriptionProgress, isGapi: Bool) -> some View {
        switch progress.stage {
        case .preparingAudio:
            Text(isGapi ? "Подготовка аудио к отправке…" : "Анализ аудио (поиск фрагментов речи)…")

        case .uploading(let sent, let total, let chunk, let totalChunks):
            if isGapi {
                HStack(spacing: 5) {
                    if total > 0 {
                        Text("Отправка файла на сервер: \(Self.formatBytes(sent)) / \(Self.formatBytes(total))")
                            .monospacedDigit()
                    } else {
                        Text("Отправка файла на сервер…")
                    }
                    Text("→")
                        .foregroundStyle(theme.tertiaryInk)
                    Text("Транскрибация на сервере")
                        .foregroundStyle(theme.tertiaryInk)
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                    Text("Подготовка")
                    Text("·")
                        .foregroundStyle(theme.tertiaryInk)
                    if let chunk, let totalChunks {
                        if total > 0, sent > 0 {
                            Text("Отправка фрагмента \(chunk)/\(totalChunks) (\(Self.formatBytes(sent)) / \(Self.formatBytes(total)))…")
                                .monospacedDigit()
                        } else {
                            Text("Отправка фрагмента \(chunk)/\(totalChunks) на сервер…")
                        }
                    } else {
                        Text("Отправка на сервер…")
                    }
                }
            }

        case .waitingInServerQueue:
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.success)
                Text("Файл отправлен")
                    .foregroundStyle(theme.ink)
                Text("→")
                    .foregroundStyle(theme.tertiaryInk)
                Text("В очереди на сервере…")
            }

        case .transcribing(_, _, let chunk, let totalChunks):
            if isGapi {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                    Text("Файл отправлен")
                        .foregroundStyle(theme.ink)
                    Text("→")
                        .foregroundStyle(theme.tertiaryInk)
                    Text("Транскрибация на сервере…")
                }
            } else if let chunk, let totalChunks {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                    Text("Фрагмент \(chunk)/\(totalChunks) отправлен")
                        .foregroundStyle(theme.ink)
                    Text("·")
                        .foregroundStyle(theme.tertiaryInk)
                    Text("Транскрибация на сервере…")
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.success)
                    Text("Аудио отправлено")
                        .foregroundStyle(theme.ink)
                    Text("·")
                        .foregroundStyle(theme.tertiaryInk)
                    Text("Транскрибация на сервере…")
                }
            }
        }
    }

    // MARK: - Tab 1: Recap & Action Items

    private func recapTabView(_ meeting: MeetingRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Action items card
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        HStack(spacing: 6) {
                            ClaudeIcon(name: "checklist", size: 12.5, weight: .light)
                                .foregroundStyle(theme.secondaryInk)
                            Text("Задачи и следующие шаги")
                                .font(fonts.uiMedium)
                                .foregroundStyle(theme.ink)
                        }
                        Spacer()
                        Text("\(meeting.actionItems.filter(\.completed).count)/\(meeting.actionItems.count)")
                            .font(fonts.caption.monospacedDigit())
                            .foregroundStyle(theme.secondaryInk)
                    }

                    if meeting.actionItems.isEmpty {
                        Text("Задачи не обнаружены автоматически. Можно добавить вручную ниже.")
                            .font(fonts.caption)
                            .foregroundStyle(theme.secondaryInk)
                    } else {
                        ForEach(meeting.actionItems) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    meetingsStore.update(meeting.id) { rec in
                                        if let idx = rec.actionItems.firstIndex(where: { $0.id == item.id }) {
                                            rec.actionItems[idx].completed.toggle()
                                        }
                                    }
                                } label: {
                                    ClaudeIcon(
                                        name: item.completed ? "checkmark.square" : "square",
                                        size: 13.5,
                                        weight: .light
                                    )
                                    .foregroundStyle(item.completed ? theme.accent : theme.secondaryInk)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text)
                                        .font(fonts.body)
                                        .strikethrough(item.completed)
                                        .foregroundStyle(item.completed ? theme.secondaryInk : theme.ink)
                                    if item.assignee != nil || item.timestamp != nil {
                                        HStack(spacing: 6) {
                                            if let assignee = item.assignee {
                                                Text(assignee)
                                                    .font(fonts.micro)
                                                    .foregroundStyle(theme.secondaryInk)
                                            }
                                            if let ts = item.timestamp {
                                                Text("[\(MeetingRecord.formatTimestamp(ts))]")
                                                    .font(fonts.micro.monospacedDigit())
                                                    .foregroundStyle(theme.secondaryInk)
                                            }
                                        }
                                    }
                                }

                                Spacer()

                                Button {
                                    meetingsStore.update(meeting.id) { rec in
                                        rec.actionItems.removeAll { $0.id == item.id }
                                    }
                                } label: {
                                    ClaudeIcon(name: "xmark", size: 9.5, weight: .light)
                                        .foregroundStyle(theme.tertiaryInk)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Embedded input + submit pill
                    HStack(spacing: 8) {
                        TextField("Добавить задачу…", text: $newActionItemText)
                            .textFieldStyle(.plain)
                            .font(fonts.ui)
                            .foregroundStyle(theme.ink)
                            .onSubmit {
                                addActionItem(to: meeting.id)
                            }
                        Button {
                            addActionItem(to: meeting.id)
                        } label: {
                            ClaudeIcon(name: "plus", size: 10.5, weight: .medium)
                        }
                        .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
                        .disabled(newActionItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5.5)
                    .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 8.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8.5, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                }
                .meetingsPaperCard(paperTheme, cornerRadius: 12, padding: 14)

                // Structured recap card
                VStack(alignment: .leading, spacing: 11) {
                    HStack {
                        HStack(spacing: 6) {
                            ClaudeIcon(name: "doc.text", size: 12.5, weight: .light)
                                .foregroundStyle(theme.secondaryInk)
                            Text("Структурированный рекап")
                                .font(fonts.uiMedium)
                                .foregroundStyle(theme.ink)
                        }
                        Spacer()
                        if !meeting.recapMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isEditingRecapMarkdown {
                            Button(isEditingRecapMarkdown ? "Готово" : "Редактировать") {
                                isEditingRecapMarkdown.toggle()
                            }
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                        }
                    }

                    if isEditingRecapMarkdown {
                        TextEditor(
                            text: Binding(
                                get: { meeting.recapMarkdown },
                                set: { newMD in
                                    meetingsStore.update(meeting.id) { $0.recapMarkdown = newMD }
                                }
                            )
                        )
                        .font(fonts.mono)
                        .foregroundStyle(theme.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 280)
                        .padding(10)
                        .background(theme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )
                    } else if meeting.recapMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(spacing: 8) {
                            ClaudeIcon(name: "doc.text", size: 22, weight: .ultraLight)
                                .foregroundStyle(theme.tertiaryInk)
                            Text(meeting.status == .ready ? "Рекап пока пуст" : "Рекап появится после расшифровки")
                                .font(fonts.uiMedium)
                                .foregroundStyle(theme.secondaryInk)
                            Text(
                                meeting.status == .ready
                                    ? "Выберите «Пересобрать рекап» в меню действий или заполните вручную."
                                    : "Как только аудио будет расшифровано, VoiceType автоматически соберёт структурированный конспект."
                            )
                            .font(fonts.caption)
                            .foregroundStyle(theme.tertiaryInk)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)

                            if meeting.status == .ready {
                                Button("Редактировать вручную") {
                                    isEditingRecapMarkdown = true
                                }
                                .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                                .padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        renderedMarkdownView(meeting.recapMarkdown)
                            .textSelection(.enabled)
                    }
                }
                .meetingsPaperCard(paperTheme, cornerRadius: 12, padding: 15)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func addActionItem(to meetingID: UUID) {
        let trimmed = newActionItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        newActionItemText = ""
        meetingsStore.update(meetingID) { rec in
            rec.actionItems.append(MeetingActionItem(text: trimmed))
        }
    }

    private func renderedMarkdownView(_ markdown: String) -> some View {
        let lines = markdown.components(separatedBy: .newlines)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("## ") {
                    Text(String(trimmed.dropFirst(3)))
                        .font(fonts.recapH2)
                        .tracking(-0.2)
                        .foregroundStyle(theme.ink)
                        .padding(.top, 8)
                } else if trimmed.hasPrefix("# ") {
                    Text(String(trimmed.dropFirst(2)))
                        .font(fonts.recapH1)
                        .tracking(-0.25)
                        .foregroundStyle(theme.ink)
                        .padding(.top, 10)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(fonts.body)
                            .foregroundStyle(theme.accent)
                        Text((try? AttributedString(markdown: String(trimmed.dropFirst(2)))) ?? AttributedString(String(trimmed.dropFirst(2))))
                            .font(fonts.body)
                            .lineSpacing(3.5)
                            .foregroundStyle(theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !trimmed.isEmpty {
                    Text((try? AttributedString(markdown: trimmed)) ?? AttributedString(trimmed))
                        .font(fonts.body)
                        .lineSpacing(3.5)
                        .foregroundStyle(theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tab 2: User Notes

    private func notesTabView(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Ваши заметки со встречи (используются как скелет важности при генерации рекапа)")
                        .font(fonts.caption)
                        .foregroundStyle(theme.secondaryInk)
                    Spacer()
                    regenerateFromNotesButton(meeting)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ваши заметки со встречи (используются как скелет важности при генерации рекапа)")
                        .font(fonts.caption)
                        .foregroundStyle(theme.secondaryInk)
                    regenerateFromNotesButton(meeting)
                }
            }

            TextEditor(
                text: Binding(
                    get: { meeting.rawNotes },
                    set: { newNotes in
                        meetingsStore.update(meeting.id) { $0.rawNotes = newNotes }
                    }
                )
            )
            .font(fonts.body)
            .foregroundStyle(theme.ink)
            .scrollContentBackground(.hidden)
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.border, lineWidth: 1)
            )
        }
    }

    private func regenerateFromNotesButton(_ meeting: MeetingRecord) -> some View {
        Button {
            Task {
                await appState.regenerateRecap(for: meeting.id)
                detailTab = .recap
            }
        } label: {
            HStack(spacing: 5) {
                ClaudeIcon(name: "sparkles", size: 11, weight: .regular)
                Text("Обновить рекап по заметкам")
            }
        }
        .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
    }

    // MARK: - Tab 3: Diarized Transcript

    private func transcriptTabView(_ meeting: MeetingRecord) -> some View {
        let speakerIDs = Array(Set(meeting.segments.compactMap(\.speaker))).sorted()
        let filteredSegments = meeting.segments.filter { seg in
            let text = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return false }
            let q = transcriptSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return true }
            return text.lowercased().contains(q)
                || meeting.displayName(for: seg.speaker).lowercased().contains(q)
        }

        return VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                if !speakerIDs.isEmpty {
                    Button {
                        showSpeakersPopover.toggle()
                    } label: {
                        HStack(spacing: 5) {
                            ClaudeIcon(name: "person.2", size: 11.5, weight: .light)
                            Text("Спикеры (\(speakerIDs.count))")
                        }
                    }
                    .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                    .popover(isPresented: $showSpeakersPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Имена спикеров")
                                .font(fonts.uiSemibold)
                            ForEach(speakerIDs, id: \.self) { spk in
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(speakerColor(for: spk))
                                        .frame(width: 7, height: 7)
                                    TextField(
                                        meeting.stereoParties ? (spk == 0 ? "Вы" : "Собеседники") : "Спикер \(spk + 1)",
                                        text: Binding(
                                            get: { meeting.displayName(for: spk) },
                                            set: { newName in
                                                meetingsStore.update(meeting.id) { rec in
                                                    rec.speakerNames[spk] = newName
                                                }
                                            }
                                        )
                                    )
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 170)
                                }
                            }
                        }
                        .padding(14)
                    }
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    ClaudeIcon(name: "magnifyingglass", size: 11, weight: .light)
                        .foregroundStyle(theme.secondaryInk)
                    TextField("Поиск по репликам…", text: $transcriptSearch)
                        .textFieldStyle(.plain)
                        .font(fonts.ui)
                        .foregroundStyle(theme.ink)
                    if !transcriptSearch.isEmpty {
                        Button {
                            transcriptSearch = ""
                        } label: {
                            ClaudeIcon(name: "xmark", size: 9.5, weight: .regular)
                                .foregroundStyle(theme.secondaryInk)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(minWidth: 140, maxWidth: 230)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7.5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7.5, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            }

            if filteredSegments.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    ClaudeIcon(name: meeting.segments.isEmpty ? "text.alignleft" : "magnifyingglass", size: 22, weight: .ultraLight)
                        .foregroundStyle(theme.tertiaryInk)
                    Text(meeting.segments.isEmpty ? "Транскрипт пока пуст" : "Реплики не найдены")
                        .font(fonts.uiMedium)
                        .foregroundStyle(theme.secondaryInk)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(filteredSegments.enumerated()), id: \.offset) { _, seg in
                            HStack(alignment: .top, spacing: 10) {
                                Text(MeetingRecord.formatTimestamp(seg.start))
                                    .font(fonts.micro.monospacedDigit())
                                    .foregroundStyle(theme.secondaryInk)
                                    .frame(width: 40, alignment: .leading)
                                    .padding(.top, 2)

                                Text(meeting.displayName(for: seg.speaker))
                                    .font(fonts.microMedium)
                                    .foregroundStyle(speakerColor(for: seg.speaker ?? 0))
                                    .lineLimit(1)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(speakerColor(for: seg.speaker ?? 0).opacity(0.12), in: Capsule())
                                    .frame(minWidth: 64, maxWidth: 112, alignment: .leading)

                                Text(seg.text)
                                    .font(fonts.body)
                                    .lineSpacing(3)
                                    .foregroundStyle(theme.ink)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 3.5)
                            Divider().overlay(theme.border)
                        }
                    }
                    .padding(14)
                }
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                )
            }
        }
    }

    private func speakerColor(for speaker: Int) -> Color {
        switch speaker % 4 {
        case 0: return theme.accent
        case 1: return .indigo
        case 2: return theme.success
        default: return theme.warning
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    private static func formatBytes(_ bytes: Int64) -> String {
        byteFormatter.string(fromByteCount: max(0, bytes))
    }
}


private struct MeetingsPaperTheme {
    let paper: PaperTheme

    var surface: Color {
        paper.surfaceColor.opacity(paper.isDark ? 0.92 : 0.86)
    }

    var surfaceSubtle: Color {
        paper.insetColor
    }

    var hoverFill: Color {
        paper.hoverColor
    }

    var selectedFill: Color {
        paper.selectedSidebarColor
    }

    var ink: Color {
        paper.inkColor
    }

    var secondaryInk: Color {
        paper.secondaryInkColor
    }

    var tertiaryInk: Color {
        paper.tertiaryInkColor
    }

    var border: Color {
        paper.borderColor
    }

    var accent: Color {
        paper.isDark ? Color(red: 0.45, green: 0.67, blue: 1.0) : PaperTokens.dictationBlue
    }

    var accentLight: Color {
        accent.opacity(0.65)
    }

    var accentSoft: Color {
        accent.opacity(paper.isDark ? 0.18 : 0.12)
    }

    var accentInk: Color {
        paper.isDark ? Color(red: 0.72, green: 0.85, blue: 1.0) : Color(red: 0.14, green: 0.35, blue: 0.76)
    }

    var success: Color {
        paper.successColor
    }

    var warning: Color {
        paper.clipboardWarningColor
    }

    var danger: Color {
        PaperTokens.recordingRed
    }

    var cardShadow: Color {
        paper.shadowRGB.color.opacity(paper.isDark ? 0.30 : 0.05)
    }
}

private extension View {
    func meetingsPaperCard(_ theme: PaperTheme, cornerRadius: CGFloat = 12, padding: CGFloat = 14) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .padding(padding)
            .background(theme.surfaceColor.opacity(theme.isDark ? 0.92 : 0.86), in: shape)
            .overlay(
                shape.strokeBorder(theme.borderColor, lineWidth: 0.75)
            )
            .shadow(color: theme.shadowRGB.color.opacity(theme.isDark ? 0.30 : 0.05), radius: 6, y: 2)
    }
}
