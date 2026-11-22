import SwiftUI

struct DashboardHistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    @State private var searchQuery = ""
    @State private var showClearConfirm = false
    @State private var copiedID: UUID?

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }
    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    private var filteredRecords: [TranscriptionRecord] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return history.records }
        return history.records.filter {
            $0.text.lowercased().contains(q)
                || ($0.languageSummary?.lowercased().contains(q) ?? false)
                || ($0.engine?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PaperPageHeader(
                    "История диктовок",
                    subtitle: "Хранится только на этом Mac в Application Support/VoiceType/history.json",
                    systemImage: "clock",
                    tileTint: PaperTokens.historyGreen
                ) {
                    if !history.records.isEmpty {
                        Button("Очистить") {
                            showClearConfirm = true
                        }
                        .buttonStyle(PaperButtonStyle(role: .destructive, compact: true))
                    }
                }

                if !history.records.isEmpty {
                    PaperInsetField(cornerRadius: PaperTokens.controlRadius, horizontalPadding: 10, verticalPadding: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11.5, weight: .regular))
                                .foregroundStyle(paperTheme.secondaryInkColor)
                            TextField("Поиск по расшифровкам…", text: $searchQuery)
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
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider().overlay(theme.border)

            if history.records.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    ClaudeIcon(name: "clock", size: 24, weight: .ultraLight)
                        .foregroundStyle(theme.tertiaryInk)
                    Text("История диктовок пуста")
                        .font(ClaudeFonts.uiMedium)
                        .foregroundStyle(theme.secondaryInk)
                    Text("Надиктуйте любой текст по хоткею — расшифровки появятся здесь.")
                        .font(ClaudeFonts.small)
                        .foregroundStyle(theme.tertiaryInk)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filteredRecords.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    ClaudeIcon(name: "magnifyingglass", size: 22, weight: .ultraLight)
                        .foregroundStyle(theme.tertiaryInk)
                    Text("Ничего не найдено")
                        .font(ClaudeFonts.uiMedium)
                        .foregroundStyle(theme.secondaryInk)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRecords) { record in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.text)
                                        .font(ClaudeFonts.body)
                                        .lineSpacing(3)
                                        .foregroundStyle(theme.ink)
                                        .textSelection(.enabled)

                                    HStack(spacing: 6) {
                                        Text(record.date, format: .dateTime.day().month().hour().minute())
                                        Text("·")
                                        Text("\(record.wordCount) слов")
                                        if record.durationSeconds > 0 {
                                            Text("·")
                                            Text("\(Int(record.durationSeconds))с")
                                        }
                                        if let lang = record.languageSummary, !lang.isEmpty {
                                            Text("·")
                                            Text(lang)
                                                .foregroundStyle(theme.accentInk)
                                        }
                                        if let engine = record.engine, !engine.isEmpty {
                                            Text("·")
                                            Text(engine)
                                        }
                                        if let latency = record.formattedLatency {
                                            Text("·")
                                            Text(latency)
                                                .monospacedDigit()
                                        }
                                    }
                                    .font(ClaudeFonts.small)
                                    .foregroundStyle(theme.secondaryInk)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    TextInjector.copyToClipboard(record.text)
                                    copiedID = record.id
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        if copiedID == record.id {
                                            copiedID = nil
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        ClaudeIcon(name: copiedID == record.id ? "checkmark" : "doc.on.doc", size: 11, weight: .light)
                                        if copiedID == record.id {
                                            Text("Скопировано")
                                        }
                                    }
                                }
                                .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                                .help("Скопировать текст")
                            }
                            .claudeCard(theme, cornerRadius: 11, padding: 13)
                            .contextMenu {
                                Button("Скопировать") {
                                    TextInjector.copyToClipboard(record.text)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
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
}
