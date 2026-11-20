import SwiftUI

struct DashboardHistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var searchQuery = ""
    @State private var showClearConfirm = false
    @State private var copiedID: UUID?

    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }

    private var filteredRecords: [TranscriptionRecord] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return history.records }
        return history.records.filter {
            $0.text.lowercased().contains(q)
                || ($0.languageSummary?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("История диктовок")
                            .font(ClaudeFonts.pageTitle)
                            .tracking(-0.35)
                            .foregroundStyle(theme.ink)
                        Text("Хранится только на этом Mac в Application Support/VoiceType/history.json")
                            .font(ClaudeFonts.small)
                            .foregroundStyle(theme.secondaryInk)
                    }

                    Spacer()

                    if !history.records.isEmpty {
                        Button("Очистить") {
                            showClearConfirm = true
                        }
                        .buttonStyle(ClaudeSecondaryButtonStyle(compact: true, isDestructive: true))
                    }
                }

                if !history.records.isEmpty {
                    HStack(spacing: 6) {
                        ClaudeIcon(name: "magnifyingglass", size: 11.5, weight: .light)
                            .foregroundStyle(theme.secondaryInk)
                        TextField("Поиск по расшифровкам…", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(ClaudeFonts.ui)
                            .foregroundStyle(theme.ink)
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                ClaudeIcon(name: "xmark", size: 10, weight: .regular)
                                    .foregroundStyle(theme.secondaryInk)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
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
        .background(theme.canvas)
        .confirmationDialog("Удалить всю историю расшифровок?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { history.clear() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("История хранится только локально и после удаления не восстанавливается.")
        }
    }
}
