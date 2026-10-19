import AppKit
import SwiftUI

struct DashboardMeetingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var meetingsStore: MeetingsStore

    @State private var selectedMeetingID: UUID?
    @State private var searchQuery: String = ""
    @State private var detailTab: DetailTab = .recap
    @State private var transcriptSearch: String = ""
    @State private var copiedFeedback: Bool = false
    @State private var isEditingRecapMarkdown: Bool = false
    @State private var newActionItemText: String = ""

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
        if let id = selectedMeetingID, let found = meetingsStore.meeting(withID: id) {
            return found
        }
        if let activeID = appState.activeMeetingID, let found = meetingsStore.meeting(withID: activeID) {
            return found
        }
        return filteredMeetings.first
    }

    var body: some View {
        HSplitView {
            sidebarList
                .frame(minWidth: 240, idealWidth: 265, maxWidth: 320)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedMeetingID == nil {
                selectedMeetingID = appState.activeMeetingID ?? meetingsStore.meetings.first?.id
            }
        }
        .onChange(of: appState.activeMeetingID) { _, newValue in
            if let newValue {
                selectedMeetingID = newValue
            }
        }
    }

    // MARK: - Left Sidebar List

    private var sidebarList: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                HStack {
                    Text("Встречи")
                        .font(.headline)
                    Spacer()
                    if appState.activeMeetingID == nil {
                        Button {
                            if let id = appState.startMeeting(
                                template: .general,
                                audioSource: settings.meetingAudioSource
                            ) {
                                selectedMeetingID = id
                            }
                        } label: {
                            Label("Новая встреча", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Button {
                            selectedMeetingID = appState.activeMeetingID
                        } label: {
                            HStack(spacing: 5) {
                                Circle().fill(Color.red).frame(width: 7, height: 7)
                                Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Поиск по встречам…", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(12)

            Divider()

            if filteredMeetings.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text(searchQuery.isEmpty ? "Пока нет встреч" : "Ничего не найдено")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filteredMeetings) { meeting in
                            meetingRow(meeting)
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func meetingRow(_ meeting: MeetingRecord) -> some View {
        let isSelected = selectedMeeting?.id == meeting.id
        return Button {
            selectedMeetingID = meeting.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    statusIcon(for: meeting.status)
                    Text(meeting.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                }

                HStack(spacing: 6) {
                    Text(Self.shortDateFormatter.string(from: meeting.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(meeting.template.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if meeting.durationSeconds > 0 {
                        Text(MeetingRecord.formatTimestamp(meeting.durationSeconds))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func statusIcon(for status: MeetingStatus) -> some View {
        switch status {
        case .recording:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        case .transcribing, .summarizing:
            ProgressView()
                .controlSize(.mini)
        case .ready:
            Image(systemName: "doc.text.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Right Detail Pane

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
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Заметки и рекапы встреч (Granola)")
                    .font(.title2.weight(.semibold))
                Text("Записывайте звонки без ботов в Zoom/Meet/Telegram. Пишите короткие тезисы во время разговора, а VoiceType разложит речь по спикерам («Вы» и «Собеседник») и соберёт локальный Markdown-рекап.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }

            HStack(spacing: 10) {
                ForEach([MeetingTemplate.general, .oneOnOne, .standup, .sales]) { tpl in
                    Button {
                        if let id = appState.startMeeting(
                            template: tpl,
                            audioSource: settings.meetingAudioSource
                        ) {
                            selectedMeetingID = id
                        }
                    } label: {
                        Label(tpl.rawValue, systemImage: tpl.systemImage)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button {
                if let id = appState.startMeeting(
                    template: .general,
                    audioSource: settings.meetingAudioSource
                ) {
                    selectedMeetingID = id
                }
            } label: {
                Label("Начать запись встречи", systemImage: "record.circle.fill")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Live Meeting Notepad (Granola Mode)

    private func liveRecordingView(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top bar with recording status and controls
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                    Text("Идёт запись")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(MeetingRecord.formatTimestamp(appState.meetingElapsedSeconds))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.1))
                .clipShape(Capsule())

                Label(meeting.audioSource.rawValue, systemImage: meeting.audioSource == .micAndSystem ? "speaker.wave.2.fill" : "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Отменить", role: .destructive) {
                    appState.cancelMeeting()
                    selectedMeetingID = meetingsStore.meetings.first?.id
                }
                .buttonStyle(.bordered)

                Button {
                    appState.finishMeeting()
                    detailTab = .recap
                } label: {
                    Label("Завершить и создать рекап", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
            }

            // Title & Template row
            HStack(spacing: 12) {
                TextField(
                    "Название встречи…",
                    text: Binding(
                        get: { meeting.title },
                        set: { newTitle in
                            meetingsStore.update(meeting.id) { $0.title = newTitle }
                        }
                    )
                )
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)

                Picker(
                    "Шаблон",
                    selection: Binding(
                        get: { meeting.template },
                        set: { newTpl in
                            meetingsStore.update(meeting.id) { $0.template = newTpl }
                        }
                    )
                ) {
                    ForEach(MeetingTemplate.allCases) { tpl in
                        Text(tpl.rawValue).tag(tpl)
                    }
                }
                .frame(width: 210)
            }

            Divider()

            Text("Живой блокнот встречи (ваши тезисы станут основой рекапа):")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextEditor(
                text: Binding(
                    get: { meeting.rawNotes },
                    set: { newNotes in
                        meetingsStore.update(meeting.id) { $0.rawNotes = newNotes }
                    }
                )
            )
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(12)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(20)
    }

    // MARK: - Completed / Processing Meeting View

    private func completedMeetingView(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Title & actions header
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(
                        "Название встречи",
                        text: Binding(
                            get: { meeting.title },
                            set: { newTitle in
                                meetingsStore.update(meeting.id) { $0.title = newTitle }
                            }
                        )
                    )
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)

                    HStack(spacing: 10) {
                        Label(Self.fullDateFormatter.string(from: meeting.date), systemImage: "calendar")
                        Label("\(max(1, Int((meeting.durationSeconds / 60).rounded()))) мин", systemImage: "clock")
                        Label(
                            meeting.stereoParties ? "Стерео: Вы + Собеседник" : "Диаризация спикеров",
                            systemImage: meeting.stereoParties ? "person.2.wave.2" : "waveform"
                        )
                        if let lang = meeting.languageSummary {
                            Text(lang)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { meeting.template },
                            set: { newTpl in
                                meetingsStore.update(meeting.id) { $0.template = newTpl }
                                Task {
                                    await appState.regenerateRecap(for: meeting.id)
                                }
                            }
                        )
                    ) {
                        ForEach(MeetingTemplate.allCases) { tpl in
                            Text(tpl.rawValue).tag(tpl)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 175)
                    .help("Сменить шаблон и пересобрать рекап")

                    Button {
                        TextInjector.copyToClipboard(meetingsStore.fullExportMarkdown(for: meeting))
                        copiedFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            copiedFeedback = false
                        }
                    } label: {
                        Label(copiedFeedback ? "Скопировано" : "Скопировать .md", systemImage: copiedFeedback ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        meetingsStore.revealMarkdownInFinder(meeting)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .help("Показать файл recap.md в Finder")

                    if meetingsStore.audioFileURL(for: meeting) != nil {
                        Button {
                            meetingsStore.revealAudioInFinder(meeting)
                        } label: {
                            Image(systemName: "waveform.circle")
                        }
                        .buttonStyle(.bordered)
                        .help("Показать сохранённую аудиозапись в Finder")
                    }

                    Button(role: .destructive) {
                        let idToDelete = meeting.id
                        meetingsStore.delete(idToDelete)
                        selectedMeetingID = meetingsStore.meetings.first?.id
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .help("Удалить встречу")
                }
            }

            // Processing / Error banner if applicable
            statusBanner(for: meeting)

            // Tab selector
            HStack {
                Picker("", selection: $detailTab) {
                    ForEach(DetailTab.allCases) { tab in
                        if tab == .transcript && !meeting.segments.isEmpty {
                            Text("Транскрипт (\(meeting.segments.count))").tag(tab)
                        } else {
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                Spacer()

                if meeting.status == .ready {
                    Button {
                        Task {
                            await appState.regenerateRecap(for: meeting.id)
                        }
                    } label: {
                        Label("Пересобрать рекап", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            // Tab body
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

    @ViewBuilder
    private func statusBanner(for meeting: MeetingRecord) -> some View {
        switch meeting.status {
        case .transcribing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                if let prog = meeting.progressSeconds, prog > 0 {
                    Text("Распознавание речи в gapi.uz: обработано \(Int(prog.rounded())) сек…")
                        .font(.callout)
                } else {
                    Text("Загрузка и распознавание аудио встречи в gapi.uz…")
                        .font(.callout)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .summarizing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Формирование структурированного рекапа и списка задач…")
                    .font(.callout)
                Spacer()
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .error(let msg):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.callout)
                Spacer()
                Button("Собрать рекап из заметок") {
                    Task {
                        await appState.regenerateRecap(for: meeting.id)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

        case .ready, .recording:
            EmptyView()
        }
    }

    // MARK: - Tab 1: Recap & Action Items

    private func recapTabView(_ meeting: MeetingRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Action Items checklist card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Задачи и следующие шаги", systemImage: "checklist")
                            .font(.headline)
                        Spacer()
                        Text("\(meeting.actionItems.filter(\.completed).count)/\(meeting.actionItems.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if meeting.actionItems.isEmpty {
                        Text("Задачи не обнаружены автоматически. Вы можете добавить их вручную ниже.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
                                    Image(systemName: item.completed ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(item.completed ? Color.accentColor : Color.secondary)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text)
                                        .font(.callout)
                                        .strikethrough(item.completed)
                                        .foregroundStyle(item.completed ? .secondary : .primary)
                                    HStack(spacing: 6) {
                                        if let assignee = item.assignee {
                                            Text(assignee)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                        if let ts = item.timestamp {
                                            Text("[\(MeetingRecord.formatTimestamp(ts))]")
                                                .font(.caption2.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                Button {
                                    meetingsStore.update(meeting.id) { rec in
                                        rec.actionItems.removeAll { $0.id == item.id }
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField("Добавить задачу…", text: $newActionItemText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addActionItem(to: meeting.id)
                            }
                        Button("Добавить") {
                            addActionItem(to: meeting.id)
                        }
                        .disabled(newActionItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Recap Markdown card
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Структурированный рекап", systemImage: "doc.richtext")
                            .font(.headline)
                        Spacer()
                        Button(isEditingRecapMarkdown ? "Готово" : "Редактировать Markdown") {
                            isEditingRecapMarkdown.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
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
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 280)
                        .padding(8)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else if meeting.recapMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Рекап пока пуст.")
                            .foregroundStyle(.secondary)
                    } else {
                        renderedMarkdownView(meeting.recapMarkdown)
                            .textSelection(.enabled)
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
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
                        .font(.title3.weight(.semibold))
                        .padding(.top, 8)
                } else if trimmed.hasPrefix("# ") {
                    Text(String(trimmed.dropFirst(2)))
                        .font(.title2.weight(.bold))
                        .padding(.top, 10)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundStyle(Color.accentColor)
                        Text((try? AttributedString(markdown: String(trimmed.dropFirst(2)))) ?? AttributedString(String(trimmed.dropFirst(2))))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if !trimmed.isEmpty {
                    Text((try? AttributedString(markdown: trimmed)) ?? AttributedString(trimmed))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tab 2: User Notes

    private func notesTabView(_ meeting: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ваши заметки со встречи (используются как скелет важности при генерации рекапа):")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task {
                        await appState.regenerateRecap(for: meeting.id)
                        detailTab = .recap
                    }
                } label: {
                    Label("Обновить рекап по заметкам", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            TextEditor(
                text: Binding(
                    get: { meeting.rawNotes },
                    set: { newNotes in
                        meetingsStore.update(meeting.id) { $0.rawNotes = newNotes }
                    }
                )
            )
            .font(.body)
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
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

        return VStack(alignment: .leading, spacing: 12) {
            // Speaker rename bar + transcript search
            HStack(spacing: 12) {
                if !speakerIDs.isEmpty {
                    HStack(spacing: 8) {
                        Text("Спикеры:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(speakerIDs, id: \.self) { spk in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(speakerColor(for: spk))
                                    .frame(width: 7, height: 7)
                                TextField(
                                    meeting.stereoParties ? (spk == 0 ? "Вы" : "Собеседник") : "Спикер \(spk + 1)",
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
                                .controlSize(.small)
                                .frame(width: 115)
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Поиск по репликам…", text: $transcriptSearch)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if filteredSegments.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(meeting.segments.isEmpty ? "Транскрипт пуст" : "Реплики не найдены")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(filteredSegments.enumerated()), id: \.offset) { _, seg in
                            HStack(alignment: .top, spacing: 10) {
                                Text(MeetingRecord.formatTimestamp(seg.start))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                    .padding(.top, 2)

                                Text(meeting.displayName(for: seg.speaker))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(speakerColor(for: seg.speaker ?? 0))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(speakerColor(for: seg.speaker ?? 0).opacity(0.12))
                                    .clipShape(Capsule())
                                    .frame(width: 110, alignment: .leading)

                                Text(seg.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.vertical, 4)
                            Divider().opacity(0.4)
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
        }
    }

    private func speakerColor(for speaker: Int) -> Color {
        switch speaker % 4 {
        case 0: return .blue
        case 1: return .purple
        case 2: return .teal
        default: return .orange
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
}
