import SwiftUI

struct DashboardHistoryView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    enum HistoryFilter: Hashable {
        case all
        case notInserted
    }

    @State private var filter: HistoryFilter = .all
    @State private var isSearchVisible = false
    @State private var searchQuery = ""
    @State private var expandedRecordID: UUID?
    @State private var showClearConfirm = false
    @State private var copiedID: UUID?
    @State private var reprocessedID: UUID?
    @State private var reprocessingID: UUID?

    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    private var notInsertedCount: Int {
        history.records.filter { $0.status != .inserted }.count
    }

    private var filteredRecords: [TranscriptionRecord] {
        let base: [TranscriptionRecord]
        switch filter {
        case .all:
            base = history.records
        case .notInserted:
            base = history.records.filter { $0.status != .inserted }
        }

        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return base }
        return base.filter { record in
            record.text.lowercased().contains(q)
                || (record.targetApp?.lowercased().contains(q) ?? false)
                || (record.errorMessage?.lowercased().contains(q) ?? false)
                || (record.engine?.lowercased().contains(q) ?? false)
        }
    }

    private struct DaySection: Identifiable {
        let dayStart: Date
        let dayNumber: String
        let dayLabel: String
        let records: [TranscriptionRecord]
        var id: Date { dayStart }
    }

    private var groupedByDay: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredRecords) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { day in
            let dayNum = String(calendar.component(.day, from: day))
            let label: String
            if calendar.isDateInToday(day) {
                label = "Сегодня"
            } else if calendar.isDateInYesterday(day) {
                label = "Вчера"
            } else {
                label = day.formatted(.dateTime.month(.wide).locale(Locale(identifier: "ru_RU")))
            }
            let sortedRecords = (grouped[day] ?? []).sorted { $0.date > $1.date }
            return DaySection(dayStart: day, dayNumber: dayNum, dayLabel: label, records: sortedRecords)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                PaperPageHeader(
                    "История",
                    subtitle: "Страховка для всех диктовок. Хранится локально в history.json (до 200 записей).",
                    systemImage: "clock",
                    tileTint: PaperTokens.historyGreen
                ) {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                isSearchVisible.toggle()
                                if !isSearchVisible {
                                    searchQuery = ""
                                }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .buttonStyle(PaperButtonStyle(role: isSearchVisible ? .primary : .secondary, compact: true))
                        .help("Поиск по истории")
                        .accessibilityLabel("Поиск по истории")

                        if !history.records.isEmpty {
                            Button("Очистить") {
                                showClearConfirm = true
                            }
                            .buttonStyle(PaperButtonStyle(role: .destructive, compact: true))
                        }
                    }
                }

                // Filter capsules
                if !history.records.isEmpty {
                    HStack(spacing: 8) {
                        filterCapsule(title: "Все", selected: filter == .all) {
                            filter = .all
                        }
                        filterCapsule(
                            title: notInsertedCount > 0 ? "Не вставилось · \(notInsertedCount)" : "Не вставилось",
                            selected: filter == .notInserted
                        ) {
                            filter = .notInserted
                        }
                        Spacer()
                    }
                }

                if isSearchVisible {
                    PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 10, verticalPadding: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11.5))
                                .foregroundStyle(paperTheme.secondaryInkColor)
                            TextField("Поиск по тексту, приложению или ошибке…", text: $searchQuery)
                                .textFieldStyle(.plain)
                                .font(fonts.ui)
                                .foregroundStyle(paperTheme.inkColor)
                            if !searchQuery.isEmpty {
                                Button {
                                    searchQuery = ""
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(paperTheme.secondaryInkColor)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Очистить поиск")
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, PaperTokens.contentPadding)
            .padding(.top, PaperTokens.contentPadding)
            .padding(.bottom, 16)

            Rectangle()
                .fill(paperTheme.borderColor)
                .frame(height: PaperTokens.hairline)

            if history.records.isEmpty {
                emptyState(
                    icon: "clock",
                    title: "История диктовок пуста",
                    subtitle: "Надиктуйте любой текст клавишей — записи появятся здесь."
                )
            } else if filteredRecords.isEmpty {
                emptyState(
                    icon: filter == .notInserted ? "checkmark.circle" : "magnifyingglass",
                    title: filter == .notInserted ? "Невставившихся записей нет" : "Ничего не найдено",
                    subtitle: filter == .notInserted ? "Все последние диктовки вставились в поля ввода." : "Попробуйте изменить поисковый запрос."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(groupedByDay) { section in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(section.dayNumber)
                                        .font(fonts.statNumber.monospacedDigit())
                                        .foregroundStyle(paperTheme.inkColor)
                                    Text(section.dayLabel)
                                        .font(fonts.uiMedium)
                                        .foregroundStyle(paperTheme.secondaryInkColor)
                                }
                                .padding(.horizontal, 4)

                                VStack(spacing: 0) {
                                    ForEach(Array(section.records.enumerated()), id: \.element.id) { idx, record in
                                        historyRow(record)
                                        if idx < section.records.count - 1 {
                                            Rectangle()
                                                .fill(paperTheme.borderColor)
                                                .frame(height: PaperTokens.hairline)
                                        }
                                    }
                                }
                                .background(
                                    paperTheme.isDark ? paperTheme.surfaceColor.opacity(0.92) : paperTheme.surfaceColor.opacity(0.84),
                                    in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                                        .strokeBorder(paperTheme.borderColor, lineWidth: 0.75)
                                )
                            }
                        }
                    }
                    .frame(maxWidth: 780, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, PaperTokens.contentPadding)
                    .padding(.vertical, 20)
                }
            }
        }
        .background { PaperBackground() }
        .confirmationDialog("Удалить всю историю расшифровок?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { history.clear() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История хранится только локально и после удаления не восстанавливается.")
        }
    }

    private func filterCapsule(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(PaperButtonStyle(role: selected ? .primary : .secondary, compact: true, isCapsule: true))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(paperTheme.tertiaryInkColor)
            Text(title)
                .font(fonts.uiMedium)
                .foregroundStyle(paperTheme.secondaryInkColor)
            Text(subtitle)
                .font(fonts.caption)
                .foregroundStyle(paperTheme.tertiaryInkColor)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func historyRow(_ record: TranscriptionRecord) -> some View {
        let isExpanded = expandedRecordID == record.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    expandedRecordID = isExpanded ? nil : record.id
                }
            } label: {
                HStack(spacing: 12) {
                    Text(record.date, format: .dateTime.hour().minute())
                        .font(fonts.caption.monospacedDigit())
                        .foregroundStyle(paperTheme.secondaryInkColor)
                        .frame(width: 42, alignment: .leading)

                    if record.text.isEmpty {
                        Text(record.errorMessage ?? "Не удалось распознать (тишина)")
                            .font(fonts.body)
                            .italic()
                            .foregroundStyle(paperTheme.secondaryInkColor)
                            .lineLimit(1)
                    } else {
                        Text(record.text)
                            .font(fonts.body)
                            .foregroundStyle(paperTheme.inkColor)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 10)

                    if let app = record.targetApp, !app.isEmpty {
                        Text(app)
                            .font(fonts.caption)
                            .foregroundStyle(paperTheme.secondaryInkColor)
                            .lineLimit(1)
                    }

                    statusIcon(for: record.status)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 12, verticalPadding: 10) {
                        Group {
                            if record.text.isEmpty {
                                Text(record.errorMessage ?? "Не удалось распознать речь.")
                                    .font(fonts.body)
                                    .italic()
                                    .foregroundStyle(paperTheme.secondaryInkColor)
                            } else {
                                Text(record.text)
                                    .font(fonts.body)
                                    .lineSpacing(3)
                                    .foregroundStyle(paperTheme.inkColor)
                                    .textSelection(.enabled)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Text(statusDescription(for: record))
                            .font(fonts.caption)
                            .foregroundStyle(paperTheme.secondaryInkColor)

                        if record.durationSeconds > 0 {
                            Text("· \(Int(record.durationSeconds)) с")
                                .font(fonts.caption)
                                .foregroundStyle(paperTheme.tertiaryInkColor)
                        }
                        if let engine = record.engine, !engine.isEmpty {
                            Text("· \(engine)")
                                .font(fonts.caption)
                                .foregroundStyle(paperTheme.tertiaryInkColor)
                        }
                        if let latency = record.formattedLatency {
                            Text("· \(latency)")
                                .font(fonts.caption.monospacedDigit())
                                .foregroundStyle(paperTheme.tertiaryInkColor)
                        }
                        Spacer()
                    }

                    if !record.text.isEmpty {
                        HStack(spacing: 8) {
                            Button {
                                TextInjector.copyToClipboard(record.text)
                                copiedID = record.id
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    if copiedID == record.id { copiedID = nil }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: copiedID == record.id ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                    Text(copiedID == record.id ? "Скопировано" : "Копировать")
                                }
                            }
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))

                            Button {
                                _ = appState.insertTextAgain(record.text)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.turn.down.left")
                                        .font(.system(size: 11))
                                    Text("Вставить снова")
                                }
                            }
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))

                            let hasClaudeKey = !settings.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            Menu {
                                ForEach(CleanupStyle.allCases.filter { $0 != .off }) { style in
                                    Button(style.shortTitle) {
                                        reprocessingID = record.id
                                        Task {
                                            await appState.reprocessRecord(record.id, with: style)
                                            reprocessingID = nil
                                            reprocessedID = record.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                if reprocessedID == record.id { reprocessedID = nil }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if reprocessingID == record.id {
                                        ProgressView().controlSize(.mini)
                                    } else {
                                        Image(systemName: reprocessedID == record.id ? "checkmark" : "sparkles")
                                            .font(.system(size: 11))
                                    }
                                    Text("Переобработать")
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .paperSurface(level: .l2OnPaper, cornerRadius: PaperTokens.controlRadius)
                            .disabled(!hasClaudeKey || reprocessingID == record.id)
                            .help(hasClaudeKey ? "Повторно обработать через Claude" : "Добавьте Anthropic API key в Настройках")

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 2)
            }
        }
    }

    private func statusIcon(for status: InsertStatus) -> some View {
        switch status {
        case .inserted:
            return Image(systemName: "checkmark.circle")
                .font(.system(size: 13))
                .foregroundStyle(paperTheme.successColor)
                .accessibilityLabel("Вставлено")
        case .clipboardOnly:
            return Image(systemName: "doc.on.clipboard")
                .font(.system(size: 12.5))
                .foregroundStyle(paperTheme.clipboardWarningColor)
                .accessibilityLabel("Только в буфере")
        case .failed:
            return Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 12.5))
                .foregroundStyle(paperTheme.errorColor)
                .accessibilityLabel("Ошибка")
        }
    }

    private func statusDescription(for record: TranscriptionRecord) -> String {
        switch record.status {
        case .inserted:
            if let app = record.targetApp, !app.isEmpty {
                return "Вставлено в \(app)"
            }
            return "Вставлено"
        case .clipboardOnly:
            return "Сохранено только в буфер"
        case .failed:
            return record.errorMessage ?? "Ошибка распознавания"
        }
    }
}
