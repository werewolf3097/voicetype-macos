import SwiftUI

struct DashboardHistoryView: View {
    @EnvironmentObject var history: HistoryStore
    @State private var showClearConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("История").font(.largeTitle.bold())
                Spacer()
                if !history.records.isEmpty {
                    Button("Очистить историю", role: .destructive) {
                        showClearConfirm = true
                    }
                }
            }
            .padding([.horizontal, .top], 24)
            .padding(.bottom, 12)

            Text("Хранится только на этом Mac, в Application Support/VoiceType/history.json. Никуда не отправляется.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)

            if history.records.isEmpty {
                emptyState
            } else {
                List(history.records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.text)
                        HStack(spacing: 6) {
                            Text(record.date, format: .dateTime.day().month().hour().minute())
                            Text("· \(record.wordCount) слов")
                            if record.durationSeconds > 0 {
                                Text("· \(Int(record.durationSeconds))с записи")
                            }
                            if let lang = record.languageSummary, !lang.isEmpty {
                                Text("· \(lang)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Скопировать") { TextInjector.copyToClipboard(record.text) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog("Удалить всю историю расшифровок?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Удалить всё", role: .destructive) { history.clear() }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Пока пусто")
                .font(.headline)
            Text("Надиктуйте что-нибудь — расшифровки появятся здесь.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
