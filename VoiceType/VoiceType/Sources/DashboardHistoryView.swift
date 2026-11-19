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
                            .font(.system(size: 24, weight: .medium, design: .serif))
                            .foregroundStyle(theme.ink)
                        Text("Хранится только на этом Mac в Application Support/VoiceType/history.json")
                            .font(.caption)
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
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(theme.secondaryInk)
                            .font(.caption)
                        TextField("Поиск по расшифровкам…", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(theme.ink)
                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(theme.secondaryInk)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider().overlay(theme.border)

            if history.records.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundStyle(theme.tertiaryInk)
                    Text("История диктовок пуста")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.secondaryInk)
                    Text("Надиктуйте любой текст по хоткею — расшифровки появятся здесь.")
                        .font(.caption)
                        .foregroundStyle(theme.tertiaryInk)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filteredRecords.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(theme.tertiaryInk)
                    Text("Ничего не найдено")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(theme.secondaryInk)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredRecords) { record in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(record.text)
                                        .font(.body)
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
                                    .font(.caption)
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
                                        Image(systemName: copiedID == record.id ? "checkmark" : "doc.on.doc")
                                        if copiedID == record.id {
                                            Text("Скопировано")
                                        }
                                    }
                                }
                                .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                                .help("Скопировать текст")
                            }
                            .claudeCard(theme, cornerRadius: 12, padding: 14)
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
